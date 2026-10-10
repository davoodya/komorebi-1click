// Ticket 10 — the shipped AutoHotkey scripts and their on-disk state.
//
// Parsimony first: no new dependency. The state file is a flat
// `{"autocorrect": true}` JSON object, so `serde_json` — already a dependency of
// the settings document — reads it directly.

use std::path::{Path, PathBuf};

/// One shipped AutoHotkey script, as declared by the installer manifest.
///
/// The `Key` values MUST match `[script:AutoHotkeyScripts].Name` in
/// `scripts/Install-Common.ps1` exactly: that list is what `ahk-script.ps1`
/// resolves `-Name` against and what `ahk-state.json` is keyed by. A rename on
/// either side silently orphans a row — the tab would render a switch for a
/// script the script itself refuses by name. There is no automated cross-check
/// of these strings against the manifest; verify by hand when either side
/// changes.
pub struct AhkScript {
    pub key: &'static str,
    pub label: &'static str,
    pub description: &'static str,
    pub hotkey: &'static str,
    pub interpreter: &'static str,
}

/// The manifest from `Install-Common.ps1`, in its order.
///
/// Transcribed, not enumerated from disk: listing `autohotkey\*.ahk` would pick
/// up a script the user dropped there, which `ahk-script.ps1` refuses by name.
/// The tab must never offer a button that cannot work.
pub const SCRIPTS: [AhkScript; 3] = [
    AhkScript {
        key: "autocorrect",
        label: "Autocorrect Script",
        description: "Auto-correct common typing mistakes as you type.",
        hotkey: "runs on every word",
        interpreter: "v1",
    },
    AhkScript {
        key: "ChangeLangF3",
        label: "Change Language F3 Script",
        description: "Switch the keyboard input language with F3.",
        hotkey: "F3",
        interpreter: "v1",
    },
    AhkScript {
        key: "NewFile",
        label: "Create New File WIN+CTRL+N Script",
        description: "Create a new file in the active folder.",
        hotkey: "Win+Ctrl+N",
        interpreter: "v2",
    },
];

/// A script's row state: the manifest row plus whether it is enabled on disk.
#[derive(serde::Serialize)]
pub struct AhkScriptState {
    pub key: String,
    pub label: &'static str,
    pub description: &'static str,
    pub hotkey: &'static str,
    pub interpreter: &'static str,
    pub enabled: bool,
}

/// Path of the state file, given the scripts directory.
///
/// The installer keeps it under `<repo root>\autohotkey\`, which is the scripts
/// directory's sibling — the same rule as `Get-AhkStateFile -RepoRoot`.
pub fn state_file_path(scripts_directory: &Path) -> PathBuf {
    let root = scripts_directory.parent().unwrap_or(scripts_directory);
    root.join("autohotkey").join("ahk-state.json")
}

/// Read the current state of every shipped script.
///
/// A missing or unreadable file means "everything enabled" — the installer's own
/// default — so the tab still opens with a usable answer rather than a broken
/// one. A key that is no longer in the manifest is not honoured: a name removed
/// from the repo must not be carried forward.
pub fn read_states(scripts_directory: &Path) -> Vec<AhkScriptState> {
    let saved = read_state_file(scripts_directory);
    SCRIPTS
        .iter()
        .map(|script| AhkScriptState {
            key: script.key.to_string(),
            label: script.label,
            description: script.description,
            hotkey: script.hotkey,
            interpreter: script.interpreter,
            enabled: saved
                .get(script.key)
                .copied()
                .unwrap_or(true),
        })
        .collect()
}

/// The raw `key -> enabled` map behind the rows. Missing file = empty map.
fn read_state_file(scripts_directory: &Path) -> std::collections::HashMap<String, bool> {
    let path = state_file_path(scripts_directory);
    let Ok(text) = std::fs::read_to_string(&path) else {
        return std::collections::HashMap::new();
    };
    let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&text) else {
        return std::collections::HashMap::new();
    };
    let Some(map) = parsed.as_object() else {
        return std::collections::HashMap::new();
    };
    map.iter()
        .filter_map(|(key, value)| {
            // Only a real JSON bool counts: the installer's own reader checks
            // `-is [bool]` before honouring a key, and a null or string must
            // not silently flip a script off.
            value.as_bool().map(|on| (key.clone(), on))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scripts_dir() -> PathBuf {
        PathBuf::from(r"C:\repo\scripts")
    }

    #[test]
    fn the_state_file_is_a_sibling_of_the_scripts_directory() {
        // The installer's Get-AhkStateFile keeps it under the repo root.
        assert_eq!(
            state_file_path(&scripts_dir()),
            PathBuf::from(r"C:\repo\autohotkey\ahk-state.json")
        );
    }

    #[test]
    fn every_shipped_script_reports_enabled_when_no_state_file_exists() {
        // A missing file is the installer's own default, not an error.
        let states = read_states(&PathBuf::from(r"C:\repo-does-not-exist\scripts"));
        assert_eq!(states.len(), 3);
        assert!(states.iter().all(|s| s.enabled));
    }

    #[test]
    fn reads_the_state_file_with_only_manifest_keys_honoured() {
        let dir = std::env::temp_dir().join("komorebi-ahk-test");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("autohotkey")).unwrap();
        std::fs::write(
            dir.join("autohotkey").join("ahk-state.json"),
            r#"{"autocorrect": false, "NewFile": true, "Obsolete": true}"#,
        )
        .unwrap();

        let states = read_states(&dir.join("scripts"));
        let by_key: std::collections::HashMap<&str, bool> =
            states.iter().map(|s| (s.key.as_str(), s.enabled)).collect();
        assert_eq!(by_key.get("autocorrect"), Some(&false));
        assert_eq!(by_key.get("ChangeLangF3"), Some(&true)); // default
        assert_eq!(by_key.get("NewFile"), Some(&true));
        assert!(!by_key.contains_key("Obsolete"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_corrupt_or_non_boolean_state_file_defaults_everything_enabled() {
        let dir = std::env::temp_dir().join("komorebi-ahk-corrupt");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("autohotkey")).unwrap();
        std::fs::write(
            dir.join("autohotkey").join("ahk-state.json"),
            r#"{"autocorrect": "yes", "ChangeLangF3": null}"#,
        )
        .unwrap();

        let states = read_states(&dir.join("scripts"));
        assert!(states.iter().all(|s| s.enabled));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_manifest_matches_the_installer_order_and_interpreter_pinning() {
        // The order is the tab's row order; the interpreter question inside the
        // row text must not assert anything false about which interpreter runs
        // which script.
        assert_eq!(
            SCRIPTS.iter().map(|s| s.key).collect::<Vec<_>>(),
            vec!["autocorrect", "ChangeLangF3", "NewFile"]
        );
        assert!(SCRIPTS.iter().all(|s| !s.key.is_empty() && !s.label.is_empty()));
        // NewFile is the v2 script; the other two are v1. A transcription that
        // flips them would tell the user the wrong interpreter is missing.
        let versions: std::collections::HashMap<&str, &str> =
            SCRIPTS.iter().map(|s| (s.key, s.interpreter)).collect();
        assert_eq!(versions.get("NewFile"), Some(&"v2"));
        assert_eq!(versions.get("autocorrect"), Some(&"v1"));
        assert_eq!(versions.get("ChangeLangF3"), Some(&"v1"));
    }
}
