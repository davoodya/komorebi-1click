#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
use dashboard_core::registry::{registry, Tab, Verb, TABS};
use dashboard_core::{locate_scripts, run, ScriptResult};
use std::{
    io::Write,
    path::PathBuf,
    sync::atomic::{AtomicBool, Ordering},
};
use tauri::Emitter;

struct AppState {
    scripts: PathBuf,
    busy: AtomicBool,
}
struct BusyGuard<'a>(&'a AtomicBool);
impl Drop for BusyGuard<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::Release);
    }
}
#[tauri::command]
fn list_verbs() -> &'static [Verb] {
    registry()
}
/// The tabs, in the order they are drawn.
///
/// Served from the backend so the strip's labels, `--help`'s group headings and
/// the elevation message all name the same tabs. A frontend that kept its own
/// copy would be the second table ADR-0013 exists to prevent.
#[tauri::command]
fn list_tabs() -> &'static [Tab] {
    &TABS
}
#[tauri::command]
fn app_info(state: tauri::State<'_, AppState>) -> serde_json::Value {
    serde_json::json!({"product":"Komorebi Admin Dashboard", "version":env!("CARGO_PKG_VERSION"),
        "gitSha":option_env!("DASHBOARD_GIT_SHA").unwrap_or("development"), "scriptsPath":state.scripts})
}
/// Stop a live run.
///
/// Returns whether a run was actually stopped. `false` is a normal answer: the
/// run may have finished between the user's click and this call arriving, and
/// saying so is more honest than reporting a cancel that did nothing.
///
/// This deliberately does **not** consult the busy guard. Cancelling has to work
/// while a verb is running — that is the whole point — and the guard exists to
/// stop a second verb from starting, not to stop a cancel from landing.
#[tauri::command]
fn cancel_run(run_id: String) -> bool {
    dashboard_core::request_cancel(&run_id)
}
/// Dispatch a verb and stream its output to the frontend.
///
/// Returns `Result` because this is an **async** command that borrows the
/// managed state: Tauri requires async commands with a borrowed input
/// (`State<'_, _>`) to return a `Result`, or the future cannot be driven to
/// `'static`. The `Err` arm is reserved for a genuine boundary failure; every
/// outcome the scripts can produce — unknown verb (2), missing script (127),
/// non-zero exit, timeout, cancellation — is a *structured* `Ok(ScriptResult)`
/// value, because the spec's error contract says a failure never throws across
/// the boundary.
///
/// Two rules, and they are deliberately different:
///
/// * The busy flag stops a second verb from starting while one is running, which
///   is what keeps the shared console pane coherent. It is released on every
///   return path — normal exit, non-zero exit, timeout and cancellation alike —
///   because the guard is dropped when this command returns, and it always
///   returns: a timed-out run is a structured result, never a hung future.
/// * The flag is not what makes cancellation possible. `cancel_run` does not
///   consult it, so a cancel lands while a run is live, which is the whole point
///   of having a cancel.
#[tauri::command]
async fn run_verb(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    verb: String,
    arguments: Vec<String>,
    run_id: String,
) -> Result<ScriptResult, String> {
    let _guard = BusyGuard(&state.busy);
    Ok(run(&state.scripts, &verb, &arguments, &run_id, |batch| {
        let _ = app.emit("script-output", batch);
    })
    .await)
}
/// Make the CLI genuinely interruptible, so Ctrl+C cancels the child instead of
/// orphaning it (spec US 55).
///
/// Two Windows facts shape this, both confirmed by measurement rather than
/// assumed:
///
/// 1. The release binary is a **windows-subsystem** build (`windows_subsystem =
///    "windows"`), so it never flashes a console. A process with no console can
///    never receive a console control event, so on a terminal it must attach to
///    the console it was launched from before an interrupt can arrive at all.
///
/// 2. That attach is **conditional on purpose**. `AttachConsole` rebinds this
///    process's standard handles onto the console it attaches to, so calling it
///    unconditionally destroys output capture: a shell running
///    `dashboard status | grep up`, or any test harness that reads the child's
///    pipes, would stop receiving output entirely. The WPF build documented
///    exactly this trap ("the output stops being captured entirely — which is
///    strictly worse than not calling it") and deliberately never attached.
///
/// So the rule is: attach only when this process is talking to a real terminal
/// and has no console yet. When stdout is redirected, the inherited console is
/// already reachable and capture must win over interruptibility.
#[cfg(windows)]
mod console {
    use std::io::IsTerminal;

    /// `(DWORD)-1`, i.e. ATTACH_PARENT_PROCESS: attach to the console of the
    /// process that launched us.
    const ATTACH_PARENT_PROCESS: u32 = u32::MAX;

    #[link(name = "kernel32")]
    extern "system" {
        fn AttachConsole(dw_process_id: u32) -> i32;
        fn GetConsoleWindow() -> *mut core::ffi::c_void;
    }

    /// True when a console is now reachable, either because one was already
    /// attached or because the parent's was attached here.
    pub fn ensure_console() -> bool {
        unsafe {
            if !GetConsoleWindow().is_null() {
                return true;
            }
            if !std::io::stdout().is_terminal() {
                // Redirected: the inherited console is what carries an event, and
                // attaching would clobber the pipe this process is writing to.
                return false;
            }
            AttachConsole(ATTACH_PARENT_PROCESS) != 0
        }
    }
}

#[cfg(not(windows))]
mod console {
    /// The crate ships on Windows; elsewhere there is nothing to attach and
    /// signals arrive without help.
    pub fn ensure_console() -> bool {
        true
    }
}

/// Run the child and let Ctrl+C stop it, rather than killing this process and
/// leaving the script behind.
///
/// The child is already registered under the run id `"cli"`, so an interrupt
/// only has to call the same `request_cancel` path the window's Cancel button
/// uses and the existing tree kill does the rest — there is no second stop
/// mechanism to keep correct.
async fn run_cli(scripts: &std::path::Path, args: &[String]) -> ScriptResult {
    console::ensure_console();
    let (verb, arguments) = args
        .split_first()
        .expect("caller checked for an empty argv");

    // Pinned so the SAME future can be awaited again after an interrupt: the run
    // has to finish through its own stop path, which is what performs the tree
    // kill and decides the exit code. Starting a second run instead would leave
    // the first child running with nothing left to stop it.
    let mut running = Box::pin(run(scripts, verb, arguments, "cli", emit_to_stdio));

    tokio::select! {
        result = &mut running => result,
        // `ctrl_c` is CTRL_C_EVENT on Windows and SIGINT elsewhere. Where a
        // console can never deliver one, this arm simply never fires and the run
        // ends the select by finishing on its own.
        _ = tokio::signal::ctrl_c() => {
            // Reaches the run that is ALREADY in flight, through the same
            // `request_cancel` path the window's Cancel button uses — there is no
            // second stop mechanism to keep correct.
            dashboard_core::request_cancel("cli");
            // A second Ctrl+C is not special-cased on purpose: the first press
            // already asked the child to stop and the tree kill follows
            // immediately, so a later press has nothing left to change. The await
            // below is what collects the cancelled result — exit 130 — instead of
            // tearing this process down before the child is reaped.
            running.await
        }
    }
}

/// Forward a batch to this process's stdout/stderr, flushing per batch so a
/// redirected pipeline sees output as it arrives rather than at exit.
fn emit_to_stdio(batch: dashboard_core::OutputBatch) {
    for line in batch.lines {
        if line.stream == "stderr" {
            let _ = writeln!(std::io::stderr(), "{}", line.text);
        } else {
            let _ = writeln!(std::io::stdout(), "{}", line.text);
        }
    }
    let _ = std::io::stdout().flush();
    let _ = std::io::stderr().flush();
}

fn main() {
    let executable = std::env::current_exe().expect("Cannot locate executable");
    let scripts = locate_scripts(&executable);
    let args: Vec<String> = std::env::args().skip(1).collect();
    if !args.is_empty() {
        if matches!(args[0].as_str(), "--help" | "-h" | "help") {
            println!("{}", dashboard_core::help());
            return;
        }
        let runtime = tokio::runtime::Runtime::new().expect("Cannot start runtime");
        let result = runtime.block_on(run_cli(&scripts, &args));
        eprintln!("{}", result.summary);
        std::process::exit(result.exit_code);
    }
    tauri::Builder::default()
        .manage(AppState {
            scripts,
            busy: AtomicBool::new(false),
        })
        .invoke_handler(tauri::generate_handler![
            list_verbs, list_tabs, app_info, run_verb, cancel_run
        ])
        .run(tauri::generate_context!())
        .expect("Dashboard runtime failed");
}
