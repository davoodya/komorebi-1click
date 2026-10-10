// Ticket 12 — the crash log that lands beside the executable.
//
// A GUI binary that dies leaves the user with nothing: no console, no exit
// code anyone sees, no hint what was happening. This module installs a panic
// hook that APPENDS one record per crash to
// `<executable dir>\KomorebiDashboard-crash.log`, naming the action that was
// underway when it died.
//
// `note_action` is the seam the dispatcher calls around every verb/action run;
// `install` is called once from `main` before anything else can panic.
//
// The directory is overridable with KOMOREBI_CRASH_LOG_DIR so the tests can
// assert against a temp dir without touching the real log.

use std::fs::OpenOptions;
use std::io::Write;
use std::panic;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

/// The action currently underway. None means "startup, before any action".
static LAST_ACTION: Mutex<Option<String>> = Mutex::new(None);

/// The directory override read once per process (`KOMOREBI_CRASH_LOG_DIR`).
static LOG_DIR_OVERRIDE: Mutex<Option<PathBuf>> = Mutex::new(None);

const LOG_FILE_NAME: &str = "KomorebiDashboard-crash.log";

/// Record what the process is about to do, so a crash during it is named.
///
/// Cheap and lock-light on purpose: it wraps every dispatched action.
pub fn note_action(action: &str) {
    if let Ok(mut slot) = LAST_ACTION.lock() {
        *slot = Some(action.to_string());
    }
}

/// Clear the recorded action (a completed run leaves nothing dangling).
pub fn clear_action() {
    if let Ok(mut slot) = LAST_ACTION.lock() {
        *slot = None;
    }
}

/// Point the crash log at a directory (tests use a temp dir). None restores
/// the default: the executable's own directory.
pub fn set_log_dir(dir: Option<PathBuf>) {
    if let Ok(mut slot) = LOG_DIR_OVERRIDE.lock() {
        *slot = dir;
    }
}

/// The log file's path: the override when set, otherwise beside the running
/// executable (falling back to the current directory when that cannot be
/// determined — a log in the wrong place still beats no log).
pub fn log_path() -> PathBuf {
    if let Ok(slot) = LOG_DIR_OVERRIDE.lock() {
        if let Some(dir) = slot.as_ref() {
            return dir.join(LOG_FILE_NAME);
        }
    }
    match std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_path_buf()))
    {
        Some(dir) => dir.join(LOG_FILE_NAME),
        None => std::env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join(LOG_FILE_NAME),
    }
}

/// Install the panic hook. Call once from `main`, before any work.
///
/// The hook KEEPS the default behaviour (printing to stderr) after writing
/// the record — it adds evidence, it does not swallow the crash.
pub fn install() {
    let default_hook = panic::take_hook();
    panic::set_hook(Box::new(move |info| {
        let _ = write_record(info);
        default_hook(info);
    }));
}

/// One appended record: timestamp, the action underway, the panic message
/// and its location when the platform reports one.
fn write_record(info: &panic::PanicHookInfo) -> std::io::Result<()> {
    let action = LAST_ACTION
        .lock()
        .ok()
        .and_then(|slot| slot.clone())
        .unwrap_or_else(|| "(startup, no action underway)".to_string());
    let message = info
        .payload()
        .downcast_ref::<&str>()
        .map(|s| s.to_string())
        .or_else(|| info.payload().downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "<non-string panic payload>".to_string());
    let location = info
        .location()
        .map(|l| format!("{}:{}", l.file(), l.line()))
        .unwrap_or_else(|| "<unknown location>".to_string());
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);

    let line = format!(
        "[{stamp}] CRASH action=\"{action}\" message=\"{message}\" location={location}\n"
    );

    let path = log_path();
    let mut file = OpenOptions::new().create(true).append(true).open(&path)?;
    file.write_all(line.as_bytes())?;
    file.flush()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Once;

    static INSTALL: Once = Once::new();

    fn temp_dir(name: &str) -> PathBuf {
        let mut dir = std::env::temp_dir();
        dir.push(format!("komorebi-crashlog-test-{name}"));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("temp dir");
        dir
    }

    // The panic hook and the last-action slot are PROCESS-GLOBAL, and cargo
    // runs a module's tests in parallel threads — so the record assertions
    // live in ONE test that drives the crashes in sequence. Splitting them
    // would race two crashes onto the same log through the same globals.
    #[test]
    fn crash_records_name_the_action_underway_and_append() {
        INSTALL.call_once(|| install());
        let dir = temp_dir("records");

        // 1. A crash during an action names that action.
        set_log_dir(Some(dir.clone()));
        clear_action();
        let result = std::panic::catch_unwind(|| {
            note_action("ahk-script.ps1 -Name autocorrect -State enabled");
            panic!("boom from the deliberate crash test");
        });
        assert!(result.is_err(), "the panic must propagate to the caller");

        let text = std::fs::read_to_string(dir.join(LOG_FILE_NAME)).expect("the crash log exists");
        assert!(
            text.contains("action=\"ahk-script.ps1 -Name autocorrect -State enabled\""),
            "the record names the failing action: {text}"
        );
        assert!(
            text.contains("message=\"boom from the deliberate crash test\""),
            "the record carries the panic payload: {text}"
        );
        assert!(text.contains("CRASH "), "the record is marked a crash: {text}");

        // 2. A crash during startup still writes a record — and says so.
        clear_action();
        let result = std::panic::catch_unwind(|| panic!("startup failure"));
        assert!(result.is_err());
        let text = std::fs::read_to_string(dir.join(LOG_FILE_NAME)).expect("log exists");
        assert!(
            text.contains("action=\"(startup, no action underway)\""),
            "the record says no action was underway: {text}"
        );
        assert!(text.contains("message=\"startup failure\""));

        // 3. The first record survives the second: append, never clobber.
        assert!(
            text.contains("message=\"boom from the deliberate crash test\""),
            "the first record is kept when a second crash appends: {text}"
        );

        set_log_dir(None);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_default_path_sits_beside_the_executable() {
        set_log_dir(None);
        let path = log_path();
        assert_eq!(
            path.file_name().and_then(|n| n.to_str()),
            Some(LOG_FILE_NAME),
            "the log lands beside the executable: {path:?}"
        );
    }
}
