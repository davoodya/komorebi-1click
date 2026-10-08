use serde::Serialize;
use std::{
    path::{Path, PathBuf},
    time::{Duration, Instant},
};
use tokio::{
    io::{AsyncBufReadExt, AsyncRead, BufReader},
    process::Command,
    sync::mpsc,
};

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
            duration_ms: 0,
            stdout: String::new(),
            stderr: message.clone(),
            summary: message,
        }
    }
}

pub fn help() -> String {
    let mut text = String::from(
        "Komorebi Admin Dashboard\nUsage: KomorebiDashboard <verb> [arguments]\n\nDebugging:\n",
    );
    for verb in registry() {
        text.push_str(&format!("  {:16} {} [read-only]\n", verb.verb, verb.help));
    }
    text.push_str(
        "\ndemo-stream arguments: -Lines <n> -DelayMs <ms> -StdErrEvery <n> -FailWith <code>\n",
    );
    text
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
    mut emit: F,
) -> ScriptResult {
    let Some(verb) = registry()
        .iter()
        .find(|v| v.verb.eq_ignore_ascii_case(requested))
    else {
        return ScriptResult::error(
            requested,
            run_id,
            2,
            format!("Unknown verb '{requested}'.\n{}", help()),
        );
    };
    // The health tracer must never accept -Action install/restart from either surface.
    if verb.verb == "status" && !arguments.is_empty() {
        return ScriptResult::error(
            requested,
            run_id,
            2,
            "status accepts no arguments.\n".to_owned() + &help(),
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
        .arg(&script)
        .args(verb.fixed_arguments)
        .args(arguments)
        .current_dir(scripts)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .stdin(std::process::Stdio::null())
        .kill_on_drop(true);
    #[cfg(windows)]
    command.creation_flags(0x08000000); // CREATE_NO_WINDOW: children never steal focus.
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            return ScriptResult::error(
                requested,
                run_id,
                1,
                format!("Cannot start PowerShell: {error}"),
            )
        }
    };
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
    let mut stdout = String::new();
    let mut stderr = String::new();
    let mut pending = Vec::new();
    let mut timer = tokio::time::interval(Duration::from_millis(50));
    timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let deadline = tokio::time::sleep(Duration::from_secs(300));
    tokio::pin!(deadline);
    let mut timed_out = false;
    loop {
        tokio::select! {
            line = rx.recv() => match line {
                Some(line) => {
                    let buffer = if line.stream == "stdout" { &mut stdout } else { &mut stderr };
                    buffer.push_str(&line.text); buffer.push('\n'); pending.push(line);
                }
                None => break,
            },
            _ = timer.tick() => if !pending.is_empty() { emit(OutputBatch { run_id: run_id.into(), lines: std::mem::take(&mut pending) }); },
            _ = &mut deadline => {
                timed_out = true;
                if let Some(pid) = child.id() {
                    let mut kill = Command::new("taskkill.exe");
                    kill.args(["/PID", &pid.to_string(), "/T", "/F"]);
                    #[cfg(windows)]
                    kill.creation_flags(0x08000000);
                    let _ = kill.output().await;
                }
                let _ = child.kill().await;
                out.abort(); err.abort();
                break;
            }
        }
    }
    if !pending.is_empty() {
        emit(OutputBatch {
            run_id: run_id.into(),
            lines: pending,
        });
    }
    let mut read_failed = false;
    if !timed_out {
        for task in [out, err] {
            match task.await {
                Ok(Ok(())) => {}
                error => {
                    read_failed = true;
                    stderr.push_str(&format!("Stream error: {error:?}\n"));
                }
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
    let exit_code = if timed_out {
        124
    } else if read_failed && exit_code == 0 {
        1
    } else {
        exit_code
    };
    let duration_ms = started.elapsed().as_millis() as u64;
    let state = if timed_out {
        "TIMED OUT"
    } else if exit_code == 0 {
        "succeeded"
    } else {
        "FAILED"
    };
    ScriptResult {
        run_id: run_id.into(),
        verb: verb.verb.into(),
        exit_code,
        duration_ms,
        stdout,
        stderr,
        summary: format!(
            "{} {state} — exit {exit_code} in {:.2}s",
            verb.label,
            duration_ms as f64 / 1000.0
        ),
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Verb {
    pub verb: &'static str,
    pub script: &'static str,
    pub label: &'static str,
    pub help: &'static str,
    pub fixed_arguments: &'static [&'static str],
    pub action_label: &'static str,
    pub is_read_only: bool,
    pub accepts_arguments: bool,
    pub hint: &'static str,
}

pub fn registry() -> &'static [Verb] {
    static VERBS: [Verb; 2] = [
        Verb {
            verb: "status",
            script: "komorebi-service.ps1",
            label: "Status",
            help: "Read-only health check",
            fixed_arguments: &["-Action", "status"],
            action_label: "Check",
            is_read_only: true,
            accepts_arguments: false,
            hint: "",
        },
        Verb {
            verb: "demo-stream",
            script: "demo-stream.ps1",
            label: "Demo Stream",
            help: "Chatty output stream: proves no-lag streaming",
            fixed_arguments: &[],
            action_label: "Stream",
            is_read_only: true,
            accepts_arguments: true,
            hint: "Number of lines (default 50)",
        },
    ];
    &VERBS
}
