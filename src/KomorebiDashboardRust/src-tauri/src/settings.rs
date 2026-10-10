// Ticket 06 — the Dashboard's user preferences as a typed document.
//
// The WPF build keeps these in `%APPDATA%\KomorebiDashboard\settings.json`
// through SettingsStore; this is the Rust twin's copy, with the same file
// layout, the same field names, and the same guarantees, because the two
// builds are expected to read each other's files:
//
//   1. defaults live ON THE TYPE, so a first run, a corrupted file and Factory
//      Reset all land on exactly the same values;
//   2. every load and every save passes through `normalize`, so no code path
//      can persist a value the UI cannot render (an out-of-range value is
//      normalized into a renderable one, never rejected — the ticket's
//      "clamped on load rather than rejected", implemented with the WPF
//      store's exact reset-to-default rule so the two builds agree);
//   3. a write is atomic (temp file + rename inside the same directory, which
//      is atomic on NTFS), so an interrupted write cannot tear the JSON;
//   4. a corrupted file is QUARANTINED — moved aside with a timestamp — never
//      silently overwritten, because the user's previous preferences are still
//      in it and the next save would otherwise destroy the only copy.
//
// Every function here takes the settings DIRECTORY as a parameter instead of
// resolving `%APPDATA%` internally. That is the test seam: the unit tests run
// against a temp directory, so nothing they do can touch a real profile, and
// the app resolves the real directory exactly once, in `settings_dir`.

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

/// The folder the settings file lives in, under the roaming profile.
pub const APP_DIR_NAME: &str = "KomorebiDashboard";

/// The settings file name.
pub const FILE_NAME: &str = "settings.json";

// ---- defaults ---------------------------------------------------------------
//
// One constant per field, referenced by the type's initializers and by
// `normalize`: a default spelled twice is a default that can drift.

pub const DEFAULT_THEME: &str = "Dark";
pub const DEFAULT_COLOR_SCHEME: &str = "Blue";
pub const DEFAULT_FONT_SIZE: f64 = 14.0;
pub const DEFAULT_FONT_FAMILY: &str = "Segoe UI";
pub const DEFAULT_UI_SCALE: f64 = 100.0;
pub const DEFAULT_CONSOLE_PERCENT: f64 = 25.0;
pub const DEFAULT_ACCENT_COLOR: &str = "";
pub const DEFAULT_CONSOLE_FONT_FAMILY: &str = "Cascadia Mono, Consolas, Courier New";
pub const DEFAULT_CONSOLE_FONT_SIZE: f64 = 12.0;

/// The toggle key for the multi-monitor monitor-boundary workaround.
pub const MULTI_MONITOR_FIX_KEY: &str = "MultiMonitorFix";

/// The sentinel `color_scheme` value that means "use `accent_color`".
pub const CUSTOM_COLOR_SENTINEL: &str = "Custom";

/// The one preference-set document.
///
/// `#[serde(default)]` is what makes an older file upgrade silently: a member
/// the file does not have is filled from `Default` instead of failing the
/// whole parse. Combined with `normalize` on load, a file written by last
/// year's build loads with today's defaults for everything it never had.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct DashboardSettings {
    pub theme: String,
    pub color_scheme: String,
    pub font_size: f64,
    pub font_family: String,
    pub ui_scale: f64,
    pub console_percent: f64,
    /// `#RRGGBB`. Only consulted when `color_scheme` is the custom sentinel.
    pub accent_color: String,
    pub console_font_family: String,
    pub console_font_size: f64,
    /// Toggle preferences by key (the Customization tab grows these).
    pub toggles: BTreeMap<String, bool>,
    /// AutoHotkey script enable state by manifest key.
    pub ahk_script_states: BTreeMap<String, bool>,
}

impl Default for DashboardSettings {
    fn default() -> Self {
        Self {
            theme: DEFAULT_THEME.to_string(),
            color_scheme: DEFAULT_COLOR_SCHEME.to_string(),
            font_size: DEFAULT_FONT_SIZE,
            font_family: DEFAULT_FONT_FAMILY.to_string(),
            ui_scale: DEFAULT_UI_SCALE,
            console_percent: DEFAULT_CONSOLE_PERCENT,
            accent_color: DEFAULT_ACCENT_COLOR.to_string(),
            console_font_family: DEFAULT_CONSOLE_FONT_FAMILY.to_string(),
            console_font_size: DEFAULT_CONSOLE_FONT_SIZE,
            toggles: BTreeMap::new(),
            ahk_script_states: BTreeMap::new(),
        }
    }
}

impl DashboardSettings {
    /// A deep copy, so a caller can stage edits and discard them.
    pub fn clone_document(&self) -> Self {
        self.clone()
    }

    /// The hex colour behind a custom accent, when one is actually selected.
    ///
    /// A named scheme never consults the hex, so a stale `accent_color` left
    /// over from an earlier custom choice cannot override the named scheme the
    /// user picked afterwards.
    pub fn custom_accent_hex(&self) -> Option<&str> {
        if self.color_scheme == CUSTOM_COLOR_SENTINEL && is_hex_color(&self.accent_color) {
            Some(&self.accent_color)
        } else {
            None
        }
    }
}

/// The outcome of a load: the document, plus what happened to a corrupt file.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoadOutcome {
    pub settings: DashboardSettings,
    /// The path a corrupted file was moved to, when there was one.
    pub quarantined: Option<PathBuf>,
}

/// `#RRGGBB`, exactly — the only accent shape the CSS can consume.
pub fn is_hex_color(value: &str) -> bool {
    let bytes = value.as_bytes();
    bytes.len() == 7
        && bytes[0] == b'#'
        && bytes[1..].iter().all(|b| b.is_ascii_hexdigit())
}

/// The real settings directory: the roaming profile, or a deterministic
/// fallback when the profile cannot be resolved (headless test runs).
pub fn settings_dir() -> PathBuf {
    if let Some(appdata) = std::env::var_os("APPDATA") {
        if !appdata.is_empty() {
            return PathBuf::from(appdata).join(APP_DIR_NAME);
        }
    }
    PathBuf::from(format!(".{APP_DIR_NAME}"))
}

/// The real settings file path.
pub fn settings_path() -> PathBuf {
    settings_dir().join(FILE_NAME)
}

/// Read the document from `dir`, falling back to defaults.
///
/// A corrupt file is MOVED ASIDE (quarantined) rather than merely ignored:
/// the user's previous preferences are still in it, and silently overwriting
/// them on the next save would destroy the only copy.
pub fn load_from(dir: &Path) -> LoadOutcome {
    let path = dir.join(FILE_NAME);
    if !path.exists() {
        return LoadOutcome {
            settings: DashboardSettings::default(),
            quarantined: None,
        };
    }

    let text = match std::fs::read_to_string(&path) {
        Ok(text) => text,
        Err(_) => {
            // Unreadable (locked, permissions): defaults, and the file is left
            // exactly as it is — moving a file we could not even read may fail
            // too, and a failed move must not look like a quarantine.
            return LoadOutcome {
                settings: DashboardSettings::default(),
                quarantined: None,
            };
        }
    };

    let parsed: Result<DashboardSettings, _> = serde_json::from_str(&text);
    let mut settings = match parsed {
        Ok(settings) => settings,
        Err(_) => {
            let mut settings = DashboardSettings::default();
            normalize(&mut settings);
            return LoadOutcome {
                settings,
                quarantined: quarantine(&path),
            };
        }
    };
    normalize(&mut settings);
    LoadOutcome {
        settings,
        quarantined: None,
    }
}

/// Write the document to `dir` atomically: temp file, then rename.
///
/// Rename within one directory is atomic on NTFS, so a crash halfway through
/// can only leave the temp file behind — never a half-written settings.json.
pub fn save_to(dir: &Path, settings: &DashboardSettings) -> Result<PathBuf, String> {
    let mut normalized = settings.clone_document();
    normalize(&mut normalized);

    std::fs::create_dir_all(dir).map_err(|e| format!("create {dir:?}: {e}"))?;
    let json = serde_json::to_string_pretty(&normalized).map_err(|e| e.to_string())?;

    let path = dir.join(FILE_NAME);
    let temp = dir.join(format!("{FILE_NAME}.tmp"));
    std::fs::write(&temp, json).map_err(|e| format!("write {temp:?}: {e}"))?;
    std::fs::rename(&temp, &path).map_err(|e| format!("rename {temp:?} -> {path:?}: {e}"))?;
    Ok(path)
}

/// Replace the document in `dir` with the defaults and persist that.
///
/// The file is KEPT (written with defaults) rather than deleted, so the state
/// is explicit and the same on the next launch.
pub fn reset_to_defaults(dir: &Path) -> Result<PathBuf, String> {
    save_to(dir, &DashboardSettings::default())
}

/// Move a corrupt file aside so the user's earlier preferences survive.
///
/// The suffix is a unix timestamp in milliseconds — unique enough for a
/// settings file a user opens a handful of times, and stable text when the
/// same file is quarantined twice.
fn quarantine(path: &Path) -> Option<PathBuf> {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    let mut target = PathBuf::from(format!("{}-corrupt-{stamp}", path.display()));
    if target.exists() {
        target = PathBuf::from(format!("{}-corrupt-{stamp}-2", path.display()));
    }
    match std::fs::rename(path, &target) {
        Ok(()) => Some(target),
        Err(_) => None,
    }
}

/// Force every value into its valid range.
///
/// Runs on every load and before every save, so no code path can persist a
/// value the UI cannot render. An out-of-range value is RESET to the field's
/// default — the WPF store's exact rule (`if (s.FontSize is < 8 or > 40)
/// s.FontSize = Default;`), kept identical here so the two builds cannot
/// disagree about what a hand-edited file means.
pub fn normalize(settings: &mut DashboardSettings) {
    if settings.theme.trim().is_empty() {
        settings.theme = DEFAULT_THEME.to_string();
    }
    if settings.color_scheme.trim().is_empty() {
        settings.color_scheme = DEFAULT_COLOR_SCHEME.to_string();
    }
    if settings.font_family.trim().is_empty() {
        settings.font_family = DEFAULT_FONT_FAMILY.to_string();
    }
    if settings.console_font_family.trim().is_empty() {
        settings.console_font_family = DEFAULT_CONSOLE_FONT_FAMILY.to_string();
    }

    // Reset-to-default, matching the WPF store: a value outside its band is a
    // value the UI cannot render, and guessing a bound would silently lie
    // about what the user asked for.
    if !(8.0..=40.0).contains(&settings.font_size) {
        settings.font_size = DEFAULT_FONT_SIZE;
    }
    if !(50.0..=300.0).contains(&settings.ui_scale) {
        settings.ui_scale = DEFAULT_UI_SCALE;
    }
    if !(10.0..=60.0).contains(&settings.console_percent) {
        settings.console_percent = DEFAULT_CONSOLE_PERCENT;
    }
    if !(8.0..=32.0).contains(&settings.console_font_size) {
        settings.console_font_size = DEFAULT_CONSOLE_FONT_SIZE;
    }

    // A custom accent is only meaningful with a real hex behind it.
    if settings.color_scheme == CUSTOM_COLOR_SENTINEL && !is_hex_color(&settings.accent_color) {
        settings.color_scheme = DEFAULT_COLOR_SCHEME.to_string();
        settings.accent_color = DEFAULT_ACCENT_COLOR.to_string();
    }
    if settings.color_scheme != CUSTOM_COLOR_SENTINEL {
        settings.accent_color = DEFAULT_ACCENT_COLOR.to_string();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A fresh temp directory per test — the seam that keeps every assertion
    /// away from the real `%APPDATA%`.
    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("k1c-settings-test-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("temp dir");
        dir
    }

    fn write_raw(dir: &Path, text: &str) {
        std::fs::write(dir.join(FILE_NAME), text).expect("write raw");
    }

    #[test]
    fn defaults_live_on_the_type() {
        let d = DashboardSettings::default();
        assert_eq!(d.theme, "Dark");
        assert_eq!(d.color_scheme, "Blue");
        assert_eq!(d.font_size, 14.0);
        assert_eq!(d.ui_scale, 100.0);
        assert_eq!(d.console_percent, 25.0);
        assert_eq!(d.console_font_family, "Cascadia Mono, Consolas, Courier New");
        assert!(d.toggles.is_empty());
    }

    #[test]
    fn every_settings_key_round_trips_across_a_restart() {
        let dir = temp_dir("round-trip");
        let mut settings = DashboardSettings::default();
        settings.theme = "Light".into();
        settings.color_scheme = "Teal".into();
        settings.font_size = 18.0;
        settings.font_family = "Cascadia Mono".into();
        settings.ui_scale = 125.0;
        settings.console_percent = 40.0;
        settings.console_font_family = "Consolas".into();
        settings.console_font_size = 15.0;
        settings.toggles.insert(MULTI_MONITOR_FIX_KEY.into(), true);
        settings
            .ahk_script_states
            .insert("ChangeLangF3".into(), false);

        save_to(&dir, &settings).expect("save");
        // The "restart": a brand-new load in a brand-new process-like state.
        let outcome = load_from(&dir);
        assert_eq!(outcome.settings, settings);
        assert!(outcome.quarantined.is_none());
    }

    #[test]
    fn an_absent_file_falls_back_to_defaults() {
        let dir = temp_dir("absent");
        let loaded = load_from(&dir).settings;
        assert_eq!(loaded, DashboardSettings::default());
    }

    #[test]
    fn an_absent_key_falls_back_to_its_default() {
        let dir = temp_dir("absent-key");
        write_raw(&dir, r#"{"theme":"Light"}"#);
        let loaded = load_from(&dir).settings;
        assert_eq!(loaded.theme, "Light");
        // Everything the file never had arrives at its default, not at zero —
        // a zero would show up as a 0px font and an invisible UI.
        assert_eq!(loaded.font_size, DEFAULT_FONT_SIZE);
        assert_eq!(loaded.ui_scale, DEFAULT_UI_SCALE);
        assert_eq!(loaded.color_scheme, DEFAULT_COLOR_SCHEME);
    }

    #[test]
    fn an_out_of_range_value_is_reset_not_rejected() {
        let dir = temp_dir("clamp");
        write_raw(&dir, r#"{"fontSize":45,"uiScale":48,"consolePercent":65}"#);
        let loaded = load_from(&dir).settings;
        // Every one of these is outside its band, so each is reset to the
        // field's default — the WPF store's rule, not a silent clamp.
        assert_eq!(loaded.font_size, DEFAULT_FONT_SIZE);
        assert_eq!(loaded.ui_scale, DEFAULT_UI_SCALE);
        assert_eq!(loaded.console_percent, DEFAULT_CONSOLE_PERCENT);
        // A value inside its band is kept exactly.
        let dir2 = temp_dir("clamp-ok");
        write_raw(&dir2, r#"{"fontSize":18,"consoleFontSize":16}"#);
        let ok = load_from(&dir2).settings;
        assert_eq!(ok.font_size, 18.0);
        assert_eq!(ok.console_font_size, 16.0);
    }

    #[test]
    fn a_corrupt_file_is_quarantined_not_silently_replaced() {
        let dir = temp_dir("quarantine");
        write_raw(&dir, "{ this is not json ");
        let outcome = load_from(&dir);
        assert_eq!(outcome.settings, DashboardSettings::default());
        let moved = outcome.quarantined.expect("the corrupt file must be moved aside");
        assert!(moved.exists(), "the quarantined file must survive on disk");
        assert!(
            !dir.join(FILE_NAME).exists(),
            "the corrupt file must not stay at the live path"
        );
        // The quarantine keeps the user's earlier text — that is the point.
        assert!(std::fs::read_to_string(&moved)
            .unwrap()
            .contains("this is not json"));
    }

    #[test]
    fn a_quarantined_load_then_save_keeps_the_quarantine() {
        let dir = temp_dir("quarantine-then-save");
        write_raw(&dir, "not json at all");
        let first = load_from(&dir);
        assert!(first.quarantined.is_some());
        save_to(&dir, &first.settings).expect("save after quarantine");
        let second = load_from(&dir);
        assert!(second.quarantined.is_none(), "the new file is valid");
        assert_eq!(second.settings, DashboardSettings::default());
        assert_eq!(
            std::fs::read_dir(&dir)
                .unwrap()
                .filter(|e| {
                    e.as_ref()
                        .unwrap()
                        .file_name()
                        .to_string_lossy()
                        .contains("-corrupt-")
                })
                .count(),
            1,
            "exactly one quarantined file remains beside the live one"
        );
    }

    #[test]
    fn save_is_atomic_and_leaves_no_temp_behind() {
        let dir = temp_dir("atomic");
        save_to(&dir, &DashboardSettings::default()).expect("save");
        assert!(dir.join(FILE_NAME).exists());
        assert!(
            !dir.join(format!("{FILE_NAME}.tmp")).exists(),
            "a finished save must not leave its temp file behind"
        );
    }

    #[test]
    fn reset_to_defaults_writes_the_defaults_back() {
        let dir = temp_dir("reset");
        let mut settings = DashboardSettings::default();
        settings.theme = "Light".into();
        save_to(&dir, &settings).expect("save");
        reset_to_defaults(&dir).expect("reset");
        let outcome = load_from(&dir);
        assert_eq!(outcome.settings, DashboardSettings::default());
        assert!(outcome.quarantined.is_none());
    }

    #[test]
    fn a_custom_accent_needs_a_real_hex_behind_it() {
        let mut s = DashboardSettings::default();
        assert!(s.custom_accent_hex().is_none());
        s.color_scheme = CUSTOM_COLOR_SENTINEL.into();
        assert!(s.custom_accent_hex().is_none(), "no hex yet");
        s.accent_color = "#1e90FF".into();
        assert_eq!(s.custom_accent_hex(), Some("#1e90FF"));
        // A named scheme never consults a stale hex.
        s.color_scheme = "Blue".into();
        assert!(s.custom_accent_hex().is_none());

        assert!(is_hex_color("#1e90ff"));
        assert!(!is_hex_color("1e90ff"), "no leading #");
        assert!(!is_hex_color("#1e90f"), "wrong length");
        assert!(!is_hex_color("#1e90fg"), "non-hex digit");
    }

    #[test]
    fn a_custom_accent_without_a_hex_falls_back_to_the_named_default() {
        let dir = temp_dir("custom-no-hex");
        write_raw(&dir, r#"{"colorScheme":"Custom","accentColor":""}"#);
        let loaded = load_from(&dir).settings;
        assert_eq!(loaded.color_scheme, DEFAULT_COLOR_SCHEME);
    }
}
