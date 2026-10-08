#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
use dashboard_core::{locate_scripts, registry, run, ScriptResult, Verb};
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
        let result = runtime.block_on(run(&scripts, &args[0], &args[1..], "cli", |batch| {
            for line in batch.lines {
                if line.stream == "stderr" {
                    let _ = writeln!(std::io::stderr(), "{}", line.text);
                } else {
                    let _ = writeln!(std::io::stdout(), "{}", line.text);
                }
            }
            let _ = std::io::stdout().flush();
            let _ = std::io::stderr().flush();
        }));
        eprintln!("{}", result.summary);
        std::process::exit(result.exit_code);
    }
    tauri::Builder::default()
        .manage(AppState {
            scripts,
            busy: AtomicBool::new(false),
        })
        .invoke_handler(tauri::generate_handler![
            list_verbs, app_info, run_verb, cancel_run
        ])
        .run(tauri::generate_context!())
        .expect("Dashboard runtime failed");
}
