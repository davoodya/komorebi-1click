pub mod registry;

use registry::Verb;
use serde::Serialize;
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{LazyLock, Mutex},
    time::{Duration, Instant},
};
use tokio::{
    io::{AsyncBufReadExt, AsyncRead, BufReader},
    process::Command,
    sync::{mpsc, oneshot},
};

/// The wall-clock budget a run gets when it does not carry one of its own.
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(300);

/// Exit code for a run the dashboard stopped because it overran its budget.
/// 124 is the conventional "timed out" code, and the spec fixes it for this case.
pub const TIMEOUT_EXIT_CODE: i32 = 124;

/// Exit code for a run the user stopped. 130 is the conventional interrupt code,
/// so a cancelled run is never mistaken for a script that failed on its own.
pub const CANCELLED_EXIT_CODE: i32 = 130;

/// The budget for a run.
///
/// `demo-stream` documents that it accepts `-TimeoutSeconds` "for symmetry with
/// the dashboard's own timeout option; this script does not enforce it itself.
/// The CALLER enforces it, which is the behaviour under test." So a run that
/// carries `-TimeoutSeconds <n>` sets its own budget, and everything else gets
/// [`DEFAULT_TIMEOUT`]. Parsing here — rather than in the fixture — is what keeps
/// the fixture honest and usable for the timeout probe.
pub fn timeout_for(arguments: &[String]) -> Duration {
    let mut remaining = arguments.iter();
    while let Some(argument) = remaining.next() {
        if argument.eq_ignore_ascii_case("-TimeoutSeconds") {
            if let Some(value) = remaining.next() {
                if let Ok(seconds) = value.parse::<u64>() {
                    if seconds > 0 {
                        return Duration::from_secs(seconds);
                    }
                }
            }
        }
    }
    DEFAULT_TIMEOUT
}

/// Remove the caller-side `-TimeoutSeconds <n>` pair from a request.
///
/// It is the caller's option, not the script's. Forwarding it would make every
/// script fail parameter binding on an option it never declared, and dropping a
/// bare `-TimeoutSeconds` with no value keeps a malformed pair from reaching the
/// script as a stray token. An invalid value is dropped too, so the run falls
/// back to the default budget instead of being refused.
///
/// Only the FIRST pair is removed: the argument is a single budget for the run,
/// and `timeout_for` reads the same first occurrence, so the two cannot disagree.
pub fn strip_timeout_option(arguments: &[String]) -> Vec<String> {
    let mut forwarded = Vec::with_capacity(arguments.len());
    let mut index = 0;
    while index < arguments.len() {
        if arguments[index].eq_ignore_ascii_case("-TimeoutSeconds") {
            // Skip the flag; skip its value only when one is actually there.
            if index + 1 < arguments.len() {
                index += 2;
            } else {
                index += 1;
            }
            break;
        }
        forwarded.push(arguments[index].clone());
        index += 1;
    }
    // Anything after the option is kept; only the pair itself is consumed.
    forwarded.extend_from_slice(&arguments[index.min(arguments.len())..]);
    forwarded
}

/// Live runs that a `cancel` can reach, keyed by run id.
///
/// A registry rather than a per-call token because the cancel arrives on a
/// different IPC call than the one running the verb: the frontend learns the run
/// id from the dispatch it made, and the backend has to find that same run again.
static LIVE_RUNS: LazyLock<Mutex<HashMap<String, oneshot::Sender<()>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Arms a receiver for a run and makes it reachable by [`request_cancel`].
fn arm_run(run_id: &str) -> oneshot::Receiver<()> {
    let (sender, receiver) = oneshot::channel();
    if let Ok(mut live) = LIVE_RUNS.lock() {
        live.insert(run_id.to_owned(), sender);
    }
    receiver
}

fn disarm_run(run_id: &str) {
    if let Ok(mut live) = LIVE_RUNS.lock() {
        live.remove(run_id);
    }
}

/// Removes a run from the registry however the run ends, including a panic or an
/// early return. Without this, a finished run id would linger and a later cancel
/// would look like it succeeded when nothing was listening.
struct RunRegistration<'a>(&'a str);
impl Drop for RunRegistration<'_> {
    fn drop(&mut self) {
        disarm_run(self.0);
    }
}

/// Ask a live run to stop. Returns false when the run already finished, which is
/// the honest answer for a cancel that arrived too late.
pub fn request_cancel(run_id: &str) -> bool {
    let sender = LIVE_RUNS
        .lock()
        .ok()
        .and_then(|mut live| live.remove(run_id));
    match sender {
        Some(sender) => sender.send(()).is_ok(),
        None => false,
    }
}

/// Kill a process together with everything it started.
///
/// `/T` is the point, not a flourish: killing only the direct child leaves
/// grandchildren alive holding the same pipe handles, so the read loops never
/// finish and a "cancelled" run keeps the caller waiting anyway — exactly the
/// trap the WPF build hit and documented.
pub async fn kill_process_tree(pid: u32) {
    #[cfg(windows)]
    {
        let mut kill = Command::new("taskkill.exe");
        kill.args(["/PID", &pid.to_string(), "/T", "/F"])
            .creation_flags(0x08000000);
        let _ = kill.output().await;
    }
    #[cfg(not(windows))]
    {
        // The direct child is always killed by the caller; only Windows needs a
        // separate tree walk, and this crate ships on Windows.
        let _ = pid;
    }
}

/// True when a process is still running. Used by the tests to prove that a stop
/// path left nothing behind.
pub fn process_exists(pid: u32) -> bool {
    #[cfg(windows)]
    {
        // Scoped: the trait is only needed for this one std command. Importing it
        // at the top of the file would shadow the inherent method tokio's own
        // command type uses elsewhere in this module.
        use std::os::windows::process::CommandExt;
        let output = std::process::Command::new("tasklist.exe")
            .args(["/FI", &format!("PID eq {pid}"), "/NH", "/FO", "CSV"])
            .creation_flags(0x08000000)
            .output();
        match output {
            Ok(output) => String::from_utf8_lossy(&output.stdout).contains(&format!("\"{pid}\"")),
            Err(_) => false,
        }
    }
    #[cfg(not(windows))]
    {
        let _ = pid;
        false
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct OutputLine {
    pub stream: String,
    pub text: String,
}
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OutputBatch {
    pub run_id: String,
    pub lines: Vec<OutputLine>,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScriptResult {
    pub run_id: String,
    pub verb: String,
    pub exit_code: i32,
    /// The user stopped this run. A distinct recorded fact, never inferred from
    /// the exit code, because the console has to say CANCELLED and not FAILED.
    pub cancelled: bool,
    /// The run overran its budget. Also its own fact: a timeout is not a script
    /// failure, and the spec requires the two to be reported differently.
    pub timed_out: bool,
    pub duration_ms: u64,
    pub stdout: String,
    pub stderr: String,
    pub summary: String,
}
impl ScriptResult {
    pub fn error(verb: &str, run_id: &str, code: i32, message: String) -> Self {
        Self {
            run_id: run_id.into(),
            verb: verb.into(),
            exit_code: code,
            cancelled: false,
            timed_out: false,
            duration_ms: 0,
            stdout: String::new(),
            stderr: message.clone(),
            summary: message,
        }
    }
    /// The verdict word the console shows. The spec fixes this vocabulary:
    /// succeeded / FAILED / cancelled / TIMED OUT.
    pub fn state(&self) -> &'static str {
        if self.cancelled {
            "CANCELLED"
        } else if self.timed_out {
            "TIMED OUT"
        } else if self.exit_code == 0 {
            "succeeded"
        } else {
            "FAILED"
        }
    }
}

/// What happened to a script that actually launched.
///
/// Internal to the runner: [`run`] turns this into the serializable
/// [`ScriptResult`]. Kept separate so a test can distinguish "the process was
/// stopped because it overran" from "the process failed on its own" without
/// reading a summary string.
/// `Default` is the "no verdict recorded yet" outcome: exit 0 with neither stop
/// flag set. Every field's zero value is meaningful here, so it is derived rather
/// than written out.
#[derive(Debug, Default)]
pub struct Outcome {
    pub exit_code: i32,
    pub cancelled: bool,
    pub timed_out: bool,
    pub duration_ms: u64,
    pub stdout: String,
    pub stderr: String,
}

impl Outcome {
    pub fn state(&self) -> &'static str {
        if self.cancelled {
            "CANCELLED"
        } else if self.timed_out {
            "TIMED OUT"
        } else if self.exit_code == 0 {
            "succeeded"
        } else {
            "FAILED"
        }
    }
}

/// Rendered help, generated from the registry table.
///
/// Ticket 01 hard-coded a `Debugging:` heading and the `demo-stream` argument
/// list here, because with two verbs there was nothing to generalise. With the
/// full registry that would be a second, hand-maintained copy of the table —
/// exactly what ADR-0013 forbids — so the text now comes from the rows.
pub fn help() -> String {
    registry::build_help()
}

pub fn locate_scripts(executable: &Path) -> PathBuf {
    let base = executable.parent().unwrap_or(Path::new("."));
    for parent in base.ancestors().take(10) {
        let candidate = parent.join("scripts");
        if candidate.join("kill-all.ps1").is_file() {
            return candidate;
        }
    }
    base.join("scripts")
}

fn powershell() -> PathBuf {
    for exe in ["pwsh.exe", "powershell.exe"] {
        if let Some(paths) = std::env::var_os("PATH") {
            for dir in std::env::split_paths(&paths) {
                let path = dir.join(exe);
                if path.is_file() {
                    return path;
                }
            }
        }
    }
    PathBuf::from(std::env::var_os("SystemRoot").unwrap_or_else(|| "C:\\Windows".into()))
        .join("System32/WindowsPowerShell/v1.0/powershell.exe")
}

async fn drain<R: AsyncRead + Unpin>(
    reader: R,
    stream: &'static str,
    tx: mpsc::Sender<OutputLine>,
) -> Result<(), String> {
    let mut lines = BufReader::new(reader).lines();
    loop {
        match lines.next_line().await {
            Ok(Some(text)) => {
                if tx
                    .send(OutputLine {
                        stream: stream.into(),
                        text,
                    })
                    .await
                    .is_err()
                {
                    return Ok(());
                }
            }
            Ok(None) => return Ok(()),
            Err(error) => return Err(format!("Cannot read {stream}: {error}")),
        }
    }
}

pub async fn run<F: FnMut(OutputBatch)>(
    scripts: &Path,
    requested: &str,
    arguments: &[String],
    run_id: &str,
    emit: F,
) -> ScriptResult {
    let Some(mut verb) = registry::find(requested) else {
        return ScriptResult::error(
            requested,
            run_id,
            2,
            format!("Unknown verb '{requested}'.\n{}", help()),
        );
    };

    // ADR-0013 spells the per-script forms `ahk enable <name>` and
    // `ahk disable <name>`, while `ahk on|off` toggles all three. The registry
    // stores the per-script forms as their own rows so each is a real row with
    // its own help, and the two-part spelling is folded onto that row here —
    // before the argument guards, so `ahk enable autocorrect` is judged by the
    // row it actually resolves to rather than by `ahk`'s own shape.
    let mut arguments = arguments.to_vec();
    if verb.verb == "ahk" && !arguments.is_empty() {
        let folded = match arguments[0].to_ascii_lowercase().as_str() {
            "enable" => Some("ahk-enable"),
            "disable" => Some("ahk-disable"),
            _ => None,
        };
        if let Some(row) = folded.and_then(registry::find) {
            verb = row;
            arguments.remove(0);
        }
    }
    // `-TimeoutSeconds` belongs to the CALLER, not to the script: it bounds this
    // invocation so a hung script cannot hang the shell that ran it. It is
    // consumed here rather than forwarded, because the scripts would reject an
    // option they never declared — and consumed BEFORE the guards below, so a
    // bare `status -TimeoutSeconds 5` is refused for the argument it actually
    // forwarded rather than for the budget itself.
    //
    // The budget is read from the ORIGINAL arguments first. Reading it after the
    // strip would always find nothing and silently fall back to the default,
    // which is how a caller's own timeout gets ignored without any error.
    let budget = timeout_for(&arguments);
    let arguments = strip_timeout_option(&arguments);
    let arguments = arguments.as_slice();
    // Two requests are refused before anything can be launched, in this order.
    //
    // First: a verb whose declared shape REQUIRES a value, sent bare. It is a
    // request for help, not a dispatch — running it would hand the script a
    // missing argument, which is how a parameter-binding failure gets reported
    // as if the operation itself had failed.
    if arguments.is_empty() && verb.requires_a_value() {
        return ScriptResult::error(
            requested,
            run_id,
            2,
            format!(
                "'{}' needs a value and was given none.\nUsage: {}\n{}",
                verb.verb,
                verb.usage(),
                help()
            ),
        );
    }
    // Second: a verb whose declared shape mentions no value must accept no
    // arguments at all. `fixed_arguments` is deliberately NOT part of this test:
    // those are the registry's own arguments, and letting them satisfy the check
    // would be exactly backwards — it would exempt the verbs that carry the most
    // dangerous fixed flags.
    //
    // `status` is the case that matters. It declares the fixed
    // `-Action status`, `RequiresAdmin: false`, and it is reached from a row with
    // no value box, so accepting `-Action install` here would turn an
    // unprivileged health check into an administrative operation with no
    // elevation gate in front of it — the gate arrives with ticket 05, and until
    // then the safe behaviour is to refuse.
    if !arguments.is_empty() && !verb.accepts_user_arguments() {
        return ScriptResult::error(
            requested,
            run_id,
            2,
            format!(
                "'{}' accepts no arguments.\nUsage: {}\n{}",
                verb.verb,
                verb.usage(),
                help()
            ),
        );
    }
    let script = scripts.join(verb.script);
    if !script.is_file() {
        return ScriptResult::error(
            requested,
            run_id,
            127,
            format!("Script not found: {}", script.display()),
        );
    }
    let outcome = execute(&script, verb, arguments, budget, run_id, emit).await;
    // Read the verdict before moving the outcome's fields into the result.
    let state = outcome.state();
    ScriptResult {
        run_id: run_id.into(),
        verb: verb.verb.into(),
        exit_code: outcome.exit_code,
        cancelled: outcome.cancelled,
        timed_out: outcome.timed_out,
        duration_ms: outcome.duration_ms,
        stdout: outcome.stdout,
        stderr: outcome.stderr,
        summary: format!(
            "{} {} — exit {} in {:.2}s",
            verb.label,
            state,
            outcome.exit_code,
            outcome.duration_ms as f64 / 1000.0
        ),
    }
}

/// Launch a script and run it under the no-lag execution contract, returning the
/// outcome rather than a message.
///
/// The contract, in one place:
/// * output is drained from **both** pipes continuously, so a chatty child can
///   never block on a full pipe buffer, and is emitted in ~50 ms batches;
/// * a user cancel and an overrun are distinct facts, and neither overwrites the
///   other — they are separate booleans on the outcome;
/// * either stop path kills the **whole process tree**, because a surviving
///   grandchild keeps the pipe handles open and the run would hang anyway;
/// * the window stays responsive because none of this runs on the caller's
///   thread: this is an async task that awaits, never blocks.
pub async fn execute<F: FnMut(OutputBatch)>(
    script: &Path,
    verb: &Verb,
    arguments: &[String],
    budget: Duration,
    run_id: &str,
    mut emit: F,
) -> Outcome {
    let started = Instant::now();
    let mut command = Command::new(powershell());
    command
        .args([
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
        ])
        .arg(script)
        .args(verb.fixed_arguments)
        .args(arguments)
        .current_dir(script.parent().unwrap_or(Path::new(".")))
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .stdin(std::process::Stdio::null())
        .kill_on_drop(true);
    #[cfg(windows)]
    command.creation_flags(0x08000000); // CREATE_NO_WINDOW: children never steal focus.
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            return Outcome {
                exit_code: 1,
                cancelled: false,
                timed_out: false,
                duration_ms: started.elapsed().as_millis() as u64,
                stdout: String::new(),
                stderr: format!("Cannot start PowerShell: {error}"),
            }
        }
    };
    // The child's own pid is what the tree kill targets, so it is captured now,
    // while the child is certainly alive.
    let pid = child.id();

    let (tx, mut rx) = mpsc::channel(1024);
    let out = tokio::spawn(drain(
        child.stdout.take().expect("piped stdout"),
        "stdout",
        tx.clone(),
    ));
    let err = tokio::spawn(drain(
        child.stderr.take().expect("piped stderr"),
        "stderr",
        tx,
    ));

    /// Kills the tree if the run ends without the child having exited on its own.
    /// Dropped on every return path, including a panic in this task.
    struct TreeGuard(Option<u32>, bool);
    impl TreeGuard {
        async fn disarm(&mut self, child: &mut tokio::process::Child) {
            // A natural exit needs no kill; a stop path leaves this armed so the
            // kill happens even if a later `await` in this function is skipped.
            if child.try_wait().ok().flatten().is_some() {
                self.1 = false;
            }
        }
    }
    impl Drop for TreeGuard {
        fn drop(&mut self) {
            if !self.1 {
                return;
            }
            let Some(pid) = self.0 else { return };
            // `Drop` cannot await, so the tree kill is handed to the runtime. This
            // is the safety net, not the main path: the stop path below kills and
            // awaits before returning.
            // Detached on purpose: this runs during unwinding/teardown and there
            // is nowhere to await it. `kill_process_tree` is also synchronous
            // enough for the process to be gone by the time the caller returns.
            drop(tokio::spawn(async move { kill_process_tree(pid).await }));
        }
    }
    let mut guard = TreeGuard(pid, true);

    let cancel_rx = arm_run(run_id);
    let _registration = RunRegistration(run_id);
    let deadline = tokio::time::sleep(budget);
    tokio::pin!(deadline);
    tokio::pin!(cancel_rx);

    let mut stdout = String::new();
    let mut stderr = String::new();
    let mut pending: Vec<OutputLine> = Vec::new();
    let mut timer = tokio::time::interval(Duration::from_millis(50));
    timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let mut cancelled = false;
    let mut timed_out = false;

    loop {
        tokio::select! {
            line = rx.recv() => match line {
                Some(line) => {
                    let buffer = if line.stream == "stdout" { &mut stdout } else { &mut stderr };
                    buffer.push_str(&line.text);
                    buffer.push('\n');
                    pending.push(line);
                }
                None => break,
            },
            _ = timer.tick() => if !pending.is_empty() {
                emit(OutputBatch { run_id: run_id.into(), lines: std::mem::take(&mut pending) });
            },
            // The user stopped the run.
            _ = &mut cancel_rx => {
                cancelled = true;
                break;
            },
            _ = &mut deadline => {
                timed_out = true;
                break;
            }
        }
    }
    // A cancel and an overrun are different facts and neither overwrites the
    // other. When both fired in the same window the run is recorded as cancelled:
    // the user's own action is never reported back as a timeout.
    if cancelled {
        timed_out = false;
    }

    // One kill path for both stop reasons, and one more for safety: the guard
    // fires when the run ended without the child having exited on its own, which
    // covers the stop arms below, an early return, and a panic.
    if cancelled || timed_out {
        if let Some(pid) = pid {
            kill_process_tree(pid).await;
        }
        let _ = child.kill().await;
    }
    guard.disarm(&mut child).await;

    // Whatever arrived in the last, partial window is flushed before the verdict,
    // so the final line of a cancelled or timed-out run is still shown.
    if !pending.is_empty() {
        emit(OutputBatch {
            run_id: run_id.into(),
            lines: pending,
        });
    }

    // The child is dead on a stop path, so the readers reach EOF promptly and the
    // tasks can be joined rather than abandoned — which is what lets the tree
    // kill be proven to have left nothing behind.
    let mut read_failed = false;
    for task in [out, err] {
        match task.await {
            Ok(Ok(())) => {}
            error => {
                read_failed = true;
                stderr.push_str(&format!("Stream error: {error:?}\n"));
            }
        }
    }
    let exit_code = match child.wait().await {
        Ok(code) => code.code().unwrap_or(1),
        Err(error) => {
            stderr.push_str(&error.to_string());
            1
        }
    };
    let exit_code = if cancelled {
        CANCELLED_EXIT_CODE
    } else if timed_out {
        TIMEOUT_EXIT_CODE
    } else if read_failed && exit_code == 0 {
        1
    } else {
        exit_code
    };
    Outcome {
        exit_code,
        cancelled,
        timed_out,
        duration_ms: started.elapsed().as_millis() as u64,
        stdout,
        stderr,
    }
}

/// Every registered verb. Kept as a re-export so callers that already name
/// `dashboard_core::registry()` keep working while the table itself lives in its
/// own module.
pub fn registry() -> &'static [Verb] {
    registry::registry()
}
