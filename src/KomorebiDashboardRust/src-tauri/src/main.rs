#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
use dashboard_core::registry::{registry, Tab, Verb, TABS};
use dashboard_core::{locate_scripts, run, ScriptResult};
use dashboard_core::settings::{self, DashboardSettings, LoadOutcome};
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
/// The shipped AutoHotkey scripts annotated with their state on disk RIGHT NOW.
///
/// Not cached: the ticket's contract is that each row shows the state read at
/// read time, and the tab re-reads after every bulk verb through this same
/// command — which is what makes the UI reflect what actually happened rather
/// than assuming a write succeeded.
#[tauri::command]
fn list_ahk_scripts(state: tauri::State<'_, AppState>) -> Vec<dashboard_core::ahk::AhkScriptState> {
    dashboard_core::ahk::read_states(&state.scripts)
}
#[tauri::command]
fn app_info(state: tauri::State<'_, AppState>) -> serde_json::Value {
    serde_json::json!({"product":"Komorebi Admin Dashboard", "version":env!("CARGO_PKG_VERSION"),
        "gitSha":option_env!("DASHBOARD_GIT_SHA").unwrap_or("development"), "scriptsPath":state.scripts,
        // The elevation state arrives with the info so the shell can gate the
        // administrative rows the same way the backend does — one registry
        // flags reading, one answer, no second probe.
        "elevated": dashboard_core::is_elevated(),
        // Ticket 11: where the running executable lives (the one fact that
        // answers "which copy did I launch") and the runtime it runs on.
        "exePath": std::env::current_exe()
            .map(|p| p.display().to_string())
            .unwrap_or_else(|_| "(unavailable)".to_string()),
        "runtimeDescription": format!(
            "Tauri {} · {}",
            env!("CARGO_PKG_VERSION"),
            std::env::consts::OS
        ),
        // Ticket 06: where the settings document lives, so the Settings pane
        // can show the real path and Open Folder reveals the real directory
        // without the frontend re-implementing the profile lookup.
        "settingsPath": settings::settings_path().display().to_string()})
}
/// Relaunch this executable elevated (the `runas` verb) and exit.
///
/// This is the dialog's "Rerun as Administrator" action, and it is the whole
/// mechanism: the elevation prompt is the OS's, the current instance exits
/// immediately so there is never a second window serving the same config, and
/// the new process reads its own elevated state through `app_info` like any
/// other start.
///
/// A declined prompt (UAC says no) is a normal outcome: the call comes back as
/// an `Err`, this process stays alive, and the window remains — the ticket's
/// contract is exactly that ("returns cleanly to the unelevated window with no
/// error state"), which the frontend honours by simply closing the dialog.
#[cfg(windows)]
#[tauri::command]
fn relaunch_elevated() -> Result<(), String> {
    #[link(name = "shell32")]
    extern "system" {
        fn ShellExecuteW(
            hwnd: *mut core::ffi::c_void,
            operation: *const u16,
            file: *const u16,
            parameters: *const u16,
            directory: *const u16,
            show_command: i32,
        ) -> *mut core::ffi::c_void;
    }

    let executable = std::env::current_exe().map_err(|e| e.to_string())?;
    let wide = |text: &str| -> Vec<u16> { text.encode_utf16().chain(core::iter::once(0)).collect() };
    let (file, verb) = (wide(&executable.to_string_lossy()), wide("runas"));
    let result = unsafe {
        ShellExecuteW(
            core::ptr::null_mut(),
            verb.as_ptr(),
            file.as_ptr(),
            core::ptr::null(),
            core::ptr::null(),
            1, // SW_SHOWNORMAL
        )
    };
    // ShellExecuteW returns a value GREATER THAN 32 on success; anything at or
    // below 32 is a failure sentinel (SE_ERR_*). The sentinel family cannot say
    // WHY the launch failed — a declined UAC prompt and an out-of-memory both
    // land here — so this code deliberately does not claim a reason: the only
    // distinction it makes is "a new process was launched", which is the one
    // fact the caller acts on (success exits this process; anything else lets
    // the window stay up). `ShellExecuteExW` + `GetLastError` would give the
    // reason, and is not worth the extra surface for an action whose only
    // outcomes are relaunched or not.
    if result as usize <= 32 {
        return Err("The elevated relaunch did not start (the elevation prompt was declined, or Windows could not launch the new instance).".into());
    }
    std::process::exit(0);
}

/// Non-Windows: nothing to elevate into, so the dialog's action is a
/// deliberate no-op reported as one.
#[cfg(not(windows))]
#[tauri::command]
fn relaunch_elevated() -> Result<(), String> {
    Err("Elevated relaunch is only available on Windows.".into())
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

// =============================================================================
// Ticket 08 — font enumeration.
//
// `reg query` spawns a process and reads two registry keys: the call belongs
// OFF the UI thread, which is exactly what a Tauri async command gives us —
// the list opens instantly, and the enumeration happens once behind the
// sentinel.
// =============================================================================

#[tauri::command]
async fn list_installed_fonts() -> Vec<String> {
    dashboard_core::fonts::enumerate_installed()
}

// =============================================================================
// Ticket 06 — the settings document, over the IPC boundary.
// =============================================================================
//
// The load/save/reset commands are thin wrappers over the pure module: the
// directory is resolved once per call from the real profile, and every
// guarantee (normalization, atomic write, quarantine) is the module's.

/// Read the settings document. `quarantined` names the file a corrupt read was
/// moved to, so the frontend can REPORT the quarantine instead of silently
/// showing defaults.
#[tauri::command]
fn get_settings() -> LoadOutcome {
    settings::load_from(&settings::settings_dir())
}

/// Write the settings document atomically; returns the file path written.
#[tauri::command]
fn save_settings(settings: DashboardSettings) -> Result<String, String> {
    settings::save_to(&settings::settings_dir(), &settings)
        .map(|path| path.display().to_string())
}

/// Restore every preference to its default and persist that.
#[tauri::command]
fn reset_settings() -> Result<String, String> {
    settings::reset_to_defaults(&settings::settings_dir())
        .map(|path| path.display().to_string())
}

/// Open Explorer at the settings DIRECTORY — the folder, not the file: opening
/// a .json hands it to whatever the user associated with JSON, which may be an
/// editor, a browser, or nothing.
#[tauri::command]
fn reveal_settings_folder() -> Result<String, String> {
    let dir = settings::settings_dir();
    std::fs::create_dir_all(&dir).map_err(|e| format!("create {dir:?}: {e}"))?;
    reveal_path(&dir)
}

/// The three folders the About tab names, as a closed set.
///
/// A CLOSED enum, not a path parameter: the About tab reports folders the
/// backend itself declared (app_info's own answers), so a reveal action can
/// only ever name one of those — an arbitrary path from the frontend would be
/// an injection surface for no benefit.
#[derive(serde::Deserialize)]
#[serde(rename_all = "lowercase")]
enum FolderKind {
    Scripts,
    Settings,
    Exe,
}

#[tauri::command]
fn reveal_folder(kind: FolderKind, state: tauri::State<'_, AppState>) -> Result<String, String> {
    let dir = match kind {
        FolderKind::Scripts => state.scripts.clone(),
        FolderKind::Settings => {
            let dir = settings::settings_dir();
            std::fs::create_dir_all(&dir).map_err(|e| format!("create {dir:?}: {e}"))?;
            dir
        }
        FolderKind::Exe => std::env::current_exe()
            .ok()
            .and_then(|exe| exe.parent().map(|p| p.to_path_buf()))
            .ok_or_else(|| "cannot locate the executable".to_string())?,
    };
    reveal_path(&dir)
}

/// The three links the About tab offers, as a closed set — the same reason the
/// folder reveal is a closed enum: the URLs are backend-declared constants, and
/// an arbitrary URL parameter from the frontend would be an injection surface.
#[derive(serde::Deserialize)]
#[serde(rename_all = "lowercase")]
enum LinkKind {
    Site,
    Repository,
}

#[tauri::command]
fn open_link(kind: LinkKind) -> Result<(), String> {
    let url = match kind {
        LinkKind::Site => "https://davoodya.ir",
        LinkKind::Repository => "https://github.com/davoodya/komorebi-1click",
    };
    // Only http(s) ever reaches a spawn: the values above are the whole set, and
    // a `start`-style shell launch of any other scheme would be a shell escape.
    if !url.starts_with("https://") {
        return Err(format!("refusing to open {url}"));
    }
    #[cfg(windows)]
    {
        // cmd /c start hands the URL to the shell, which resolves the user's
        // default browser. A successful SPAWN is the signal, not the exit code.
        std::process::Command::new("cmd")
            .args(["/C", "start", "", url])
            .status()
            .map_err(|e| format!("launch browser: {e}"))?;
    }
    #[cfg(not(windows))]
    {
        return Err(format!("open links is only implemented on Windows (url: {url})"));
    }
    Ok(())
}

/// Open Explorer at a directory. A successful SPAWN is the signal, NOT the exit
/// code: explorer.exe is a shell facade that hands the window off to an existing
/// explorer process and routinely exits 1 having opened it.
fn reveal_path(dir: &std::path::Path) -> Result<String, String> {
    let dir_text = dir.display().to_string();

    #[cfg(windows)]
    {
        let _status = std::process::Command::new("explorer.exe")
            .arg(&dir_text)
            .status()
            .map_err(|e| format!("launch explorer: {e}"))?;
    }
    #[cfg(not(windows))]
    {
        return Err(format!("reveal is only implemented on Windows (dir: {dir_text})"));
    }
    Ok(dir_text)
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
            list_verbs,
            list_tabs,
            list_ahk_scripts,
            app_info,
            run_verb,
            cancel_run,
            relaunch_elevated,
            get_settings,
            save_settings,
            reset_settings,
            reveal_settings_folder,
            reveal_folder,
            open_link,
            list_installed_fonts
        ])
        .run(tauri::generate_context!())
        .expect("Dashboard runtime failed");
}
