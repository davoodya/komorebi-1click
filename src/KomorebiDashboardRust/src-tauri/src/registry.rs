//! The single verb registry (ADR-0013) — the one place a verb is defined.
//!
//! Four consumers are generated from this table and never from a second copy:
//! the GUI's rows, the CLI dispatch, `--help`, and (from ticket 05) the elevation
//! dialog's feature list. Adding a verb is one row here and nothing else.
//!
//! ## Provenance
//!
//! Every row was transferred from the shipping C# `Services/VerbRegistry.cs` by a
//! parser rather than typed by hand, because a hand-copied row is where a silent
//! divergence starts. The C# table is the parity source: this translation must not
//! invent, drop or rename a verb, and `tests/registry.rs` asserts the invariants
//! that hold over the whole table.
//!
//! ## Argument shapes are read from the scripts, not from the ADR
//!
//! Each row's `arguments` and `fixed_arguments` were checked against the target
//! script's real `param` block. Two earlier rows in the WPF table were not, and
//! were dead on arrival: `startup` advertised `add|remove` while
//! `komorebi-service.ps1 -Action` is a ValidateSet of
//! `install|uninstall|start|stop|restart|status|retile|watchdog`, and `ahk`
//! advertised `on|off` while `ahk-toggle.ps1 -State` accepts `enabled|disabled`.
//! A row naming an argument the script rejects is worse than a missing row: the
//! button looks present and silently does nothing.
//!
//! CAUTION: do not write a literal sample of a registry row anywhere in this file.
//! The project's own scans cannot tell a sample from a row, so a sample registers
//! as a verb of its own and reports a script that was never meant to exist as
//! missing.

use serde::Serialize;

/// One tab in the dashboard.
///
/// The order of [`TABS`] is the order on screen and the order in `--help`. Only
/// the tabs that carry registry verbs appear in help, so `Customization` and
/// `About` — which are hand-built surfaces rather than row lists — are drawn in
/// the window and skipped in help instead of printing an empty heading.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Tab {
    pub id: &'static str,
    pub label: &'static str,
    pub description: &'static str,
}

pub const TABS: [Tab; 8] = [
    Tab {
        id: "KillStart",
        label: "Kill and Start",
        description: "Stop and start komorebi, whkd and yasb, separately or together.",
    },
    Tab {
        id: "Restart",
        label: "Restart and Reloading",
        description: "Restart the running stack through the safe restart paths.",
    },
    Tab {
        id: "Settings",
        label: "Settings",
        description: "Startup tasks, configuration export/import and dashboard rules.",
    },
    Tab {
        id: "Customization",
        label: "Customization",
        description: "Appearance and layout controls.",
    },
    Tab {
        id: "AutoHotkey",
        label: "AutoHotkey Scripts",
        description: "Enable, disable and diagnose the shipped AutoHotkey scripts.",
    },
    Tab {
        id: "Debugging",
        label: "Debugging",
        description: "Health checks, monitor recovery and the streaming test verb.",
    },
    Tab {
        id: "Uninstall",
        label: "Uninstall and Cleanup",
        description: "Remove the stack, or the traces it leaves behind.",
    },
    Tab {
        id: "About",
        label: "About",
        description: "Product identity, version and paths.",
    },
];

/// One registry row: the single description of a verb.
///
/// The GUI button, the CLI dispatch, the `--help` text and the elevation
/// message are all generated from these fields, which is what makes it
/// impossible for the GUI and the CLI to disagree (ADR-0013).
///
/// `Clone` exists so a test can extend the real table and prove the extension
/// rule through the same rendering path the shipped help uses.
#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Verb {
    /// The name used on the command line.
    pub verb: &'static str,
    /// File name of the `.ps1` that does the actual work, resolved against the
    /// located `scripts/` directory.
    pub script: &'static str,
    /// Shape of the arguments this verb takes, for help and for the GUI's
    /// argument box. `<x>` marks a required value and `[x]` an optional one,
    /// matching ADR-0013's notation.
    pub arguments: &'static str,
    /// True when the script needs an elevated host. This is the flag the
    /// elevation gate and the dialog's feature list read.
    pub requires_admin: bool,
    /// One line of help, also used by `--help` and as the row's subtitle.
    pub help: &'static str,
    /// Which tab owns the button. Every verb appears in exactly one.
    pub tab: &'static str,
    /// Button caption.
    pub label: &'static str,
    /// True when the verb changes nothing on the system. Read-only rows are
    /// badged so a diagnostic can never be mistaken for an action.
    pub is_read_only: bool,
    /// Arguments always passed to the script, BEFORE any the user typed.
    ///
    /// Several verbs share one script and differ only by a flag — `kill-all`,
    /// `kill-komorebi` and `kill-yasb` are all `kill-all.ps1 -Components <x>` —
    /// so this is what keeps those rows pointing at real, existing scripts
    /// instead of at `.ps1` files that were never written.
    pub fixed_arguments: &'static [&'static str],
    /// False for verbs that exist for the CLI and for `--help` but have no row
    /// of their own, because a more specific pair of rows supersedes them in the
    /// tab (for example `startup` is reached from the GUI as Add/Remove to
    /// Startup). The verb stays fully dispatchable; only the row is suppressed.
    pub render_in_gui: bool,
    /// Placeholder text for the row's input box. Stated explicitly rather than
    /// derived from `arguments`: the shape is notation for `--help`, and a value
    /// a user should type is a different string.
    pub hint: &'static str,
    /// What the row's button says. Falls back to `label` when empty.
    pub action_label: &'static str,
    /// True when the only acceptable value is a whole number, so the row draws a
    /// narrow numeric box and the typed text is filtered to digits.
    pub numeric_only: bool,
}

impl Verb {
    /// The command-line form, rendered from the same fields the GUI uses, so
    /// help and dispatch cannot diverge.
    pub fn usage(&self) -> String {
        if self.arguments.is_empty() {
            self.verb.to_string()
        } else {
            format!("{} {}", self.verb, self.arguments)
        }
    }

    /// True when the user has to supply a value, i.e. the shape mentions one
    /// (either required `<x>` or optional `[x]`).
    ///
    /// This is what decides whether a row draws an input box. Deriving it from
    /// the registry means a new verb gets the right row shape with no view
    /// change — and a verb that takes no value can never show a box whose
    /// contents would be silently ignored.
    pub fn accepts_user_arguments(&self) -> bool {
        self.arguments.contains('<') || self.arguments.contains('[')
    }

    /// True when running this verb with no arguments must print help instead of
    /// dispatching: it declares a REQUIRED value (`<x>`), so launching it bare
    /// would run a script with a missing argument.
    pub fn requires_a_value(&self) -> bool {
        self.arguments.contains('<')
    }

    /// True when the row appears on its tab. The verb stays dispatchable either
    /// way; only the row is suppressed.
    pub fn has_row(&self) -> bool {
        self.render_in_gui
    }

    /// The caption the row's button carries.
    pub fn button_label(&self) -> &'static str {
        if self.action_label.is_empty() {
            self.label
        } else {
            self.action_label
        }
    }
}
/// Every verb, in tab order. `tests/registry.rs` derives its counts from this
/// table, so the numbers in the documents can be checked instead of trusted.
static VERBS: [Verb; 35] = [
    // ---- Kill and Start ------------------------------------------
    Verb {
        verb: "kill-all",
        script: "kill-all.ps1",
        arguments: "-Components all|komorebi-whkd|yasb",
        requires_admin: true,
        help: "Stop komorebi, whkd and yasb",
        tab: "KillStart",
        label: "Kill All",
        is_read_only: false,
        fixed_arguments: &["-Components", "all"],
        render_in_gui: true,
        hint: "",
        action_label: "Kill",
        numeric_only: false,
    },
    Verb {
        verb: "kill-komorebi",
        script: "kill-all.ps1",
        arguments: "-Components komorebi-whkd",
        requires_admin: true,
        help: "Stop komorebi (and whkd, which runs with it)",
        tab: "KillStart",
        label: "Kill Komorebi",
        is_read_only: false,
        fixed_arguments: &["-Components", "komorebi-whkd"],
        render_in_gui: true,
        hint: "",
        action_label: "Kill",
        numeric_only: false,
    },
    Verb {
        verb: "kill-whkd",
        script: "kill-whkd.ps1",
        arguments: "",
        requires_admin: true,
        help: "Stop whkd only",
        tab: "KillStart",
        label: "Kill WHKD",
        is_read_only: false,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "",
        action_label: "Kill",
        numeric_only: false,
    },
    Verb {
        verb: "kill-yasb",
        script: "kill-all.ps1",
        arguments: "-Components yasb",
        requires_admin: false,
        help: "Stop yasb only",
        tab: "KillStart",
        label: "Kill YASB",
        is_read_only: false,
        fixed_arguments: &["-Components", "yasb"],
        render_in_gui: true,
        hint: "",
        action_label: "Kill",
        numeric_only: false,
    },
    Verb {
        verb: "start-all",
        script: "start-all.ps1",
        arguments: "-Components all|komorebi-whkd|yasb",
        requires_admin: false,
        help: "Start komorebi, whkd and yasb",
        tab: "KillStart",
        label: "Start All",
        is_read_only: false,
        fixed_arguments: &["-Components", "all"],
        render_in_gui: true,
        hint: "",
        action_label: "Start",
        numeric_only: false,
    },
    Verb {
        verb: "start-komorebi",
        script: "start-all.ps1",
        arguments: "-Components komorebi-whkd",
        requires_admin: true,
        help: "Start komorebi (and whkd, which runs with it)",
        tab: "KillStart",
        label: "Start Komorebi",
        is_read_only: false,
        fixed_arguments: &["-Components", "komorebi-whkd"],
        render_in_gui: true,
        hint: "",
        action_label: "Start",
        numeric_only: false,
    },
    Verb {
        verb: "start-whkd",
        script: "start-whkd.ps1",
        arguments: "-Force (switch)",
        requires_admin: true,
        help: "Start whkd only (delegates to the whkd-safe path)",
        tab: "KillStart",
        label: "Start WHKD",
        is_read_only: false,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "",
        action_label: "Start",
        numeric_only: false,
    },
    Verb {
        verb: "start-yasb",
        script: "start-all.ps1",
        arguments: "-Components yasb",
        requires_admin: false,
        help: "Start yasb only",
        tab: "KillStart",
        label: "Start YASB",
        is_read_only: false,
        fixed_arguments: &["-Components", "yasb"],
        render_in_gui: true,
        hint: "",
        action_label: "Start",
        numeric_only: false,
    },
    // ---- Restart and Reloading -----------------------------------
    Verb {
        verb: "restart-all",
        script: "restart-all.ps1",
        arguments: "",
        requires_admin: false,
        help: "Safely restart everything (0-SAFE-RESTART)",
        tab: "Restart",
        label: "Restart All",
        is_read_only: false,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "",
        action_label: "Restart",
        numeric_only: false,
    },
    Verb {
        verb: "restart-komorebi",
        script: "restart-komorebi.ps1",
        arguments: "",
        requires_admin: false,
        help: "Restart komorebi (and whkd)",
        tab: "Restart",
        label: "Restart Komorebi",
        is_read_only: false,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "",
        action_label: "Restart",
        numeric_only: false,
    },
    Verb {
        verb: "restart-whkd",
        script: "restart-whkd.ps1",
        arguments: "",
        requires_admin: false,
        help: "Restart whkd only",
        tab: "Restart",
        label: "Restart WHKD",
        is_read_only: false,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "",
        action_label: "Restart",
        numeric_only: false,
    },
    Verb {
        verb: "restart-yasb",
        script: "restart-yasb.ps1",
        arguments: "",
        requires_admin: false,
        help: "Restart yasb (PATH rebuild preserved)",
        tab: "Restart",
        label: "Restart YASB",
        is_read_only: false,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "",
        action_label: "Restart",
        numeric_only: false,
    },
    // ---- Settings ------------------------------------------------
    Verb {
        verb: "startup",
        script: "komorebi-service.ps1",
        arguments: "-Action install|uninstall",
        requires_admin: true,
        help: "Register or remove the logon + watchdog tasks",
        tab: "Settings",
        label: "Startup",
        is_read_only: false,
        fixed_arguments: &["-Action", "install"],
        render_in_gui: false,
        hint: "",
        action_label: "",
        numeric_only: false,
    },
    Verb {
        verb: "startup-install",
        script: "komorebi-service.ps1",
        arguments: "-Action install",
        requires_admin: true,
        help: "Start komorebi + whkd automatically at logon, with a watchdog",
        tab: "Settings",
        label: "Add to Startup",
        is_read_only: false,
        fixed_arguments: &["-Action", "install"],
        render_in_gui: true,
        hint: "",
        action_label: "Add",
        numeric_only: false,
    },
    Verb {
        verb: "startup-remove",
        script: "komorebi-service.ps1",
        arguments: "-Action uninstall",
        requires_admin: true,
        help: "Remove the logon and watchdog tasks; the running session is untouched",
        tab: "Settings",
        label: "Remove from Startup",
        is_read_only: false,
        fixed_arguments: &["-Action", "uninstall"],
        render_in_gui: true,
        hint: "",
        action_label: "Remove",
        numeric_only: false,
    },
    Verb {
        verb: "export",
        script: "komorebi-backup.ps1",
        arguments: "-ZipPath [directory]",
        requires_admin: false,
        help: "Export the live configuration",
        tab: "Settings",
        label: "Export Config",
        is_read_only: false,
        fixed_arguments: &["-Mode", "export"],
        render_in_gui: true,
        hint: "folder to write the backup into (optional)",
        action_label: "Export",
        numeric_only: false,
    },
    Verb {
        verb: "import",
        script: "komorebi-backup.ps1",
        arguments: "-ZipPath [file or folder]",
        requires_admin: false,
        help: "Restore the configuration from a backup",
        tab: "Settings",
        label: "Import Config",
        is_read_only: false,
        fixed_arguments: &["-Mode", "import"],
        render_in_gui: true,
        hint: "backup folder to restore (optional)",
        action_label: "Import",
        numeric_only: false,
    },
    Verb {
        verb: "set-transparency",
        script: "toggle-transparency.ps1",
        arguments: "-Percent <0-100>",
        requires_admin: false,
        help: "Set window transparency percent",
        tab: "Settings",
        label: "Set Transparency",
        is_read_only: false,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "enter percentage only",
        action_label: "Apply",
        numeric_only: true,
    },
    Verb {
        verb: "ignore-dashboard",
        script: "ignore-dashboard.ps1",
        arguments: "",
        requires_admin: false,
        help: "On a multi-monitor system komorebi can push some WPF windows across a monitor boundary. This is a known komorebi bug and it affects other windows too, such as ncpa.cpl, Device Manager and Disk Management. Adding the rule makes komorebi stop managing KomorebiDashboard.exe.",
        tab: "Settings",
        label: "Ignore KomorebiDashboard",
        is_read_only: false,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "",
        action_label: "Add Rule",
        numeric_only: false,
    },
    // ---- Debugging -----------------------------------------------
    Verb {
        verb: "status",
        script: "komorebi-service.ps1",
        arguments: "status",
        requires_admin: false,
        help: "Read-only health check",
        tab: "Debugging",
        label: "Status",
        is_read_only: true,
        fixed_arguments: &["-Action", "status"],
        render_in_gui: true,
        hint: "",
        action_label: "Check",
        numeric_only: false,
    },
    Verb {
        verb: "recover-monitors",
        script: "recover-monitors.ps1",
        arguments: "",
        requires_admin: false,
        help: "After plug/unplug: restore orphans and retile",
        tab: "Debugging",
        label: "Recover Monitors",
        is_read_only: false,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "",
        action_label: "Recover",
        numeric_only: false,
    },
    Verb {
        verb: "display-diag",
        script: "display-diag.ps1",
        arguments: "",
        requires_admin: false,
        help: "Compare monitor geometry across three sources",
        tab: "Debugging",
        label: "Display Diagnostics",
        is_read_only: true,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "",
        action_label: "Inspect",
        numeric_only: false,
    },
    Verb {
        verb: "reset-workspaces",
        script: "reset-workspaces.ps1",
        arguments: "",
        requires_admin: false,
        help: "Renumber workspaces 1..9 on every monitor",
        tab: "Debugging",
        label: "Reset Workspaces",
        is_read_only: false,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "",
        action_label: "Reset",
        numeric_only: false,
    },
    Verb {
        verb: "repair-whkdrc",
        script: "repair-whkdrc.ps1",
        arguments: "",
        requires_admin: false,
        help: "Rewrite whkdrc into the form whkd accepts",
        tab: "Debugging",
        label: "Repair whkdrc",
        is_read_only: false,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "",
        action_label: "Repair",
        numeric_only: false,
    },
    Verb {
        verb: "demo-stream",
        script: "demo-stream.ps1",
        arguments: "-Lines [n] -DelayMs [ms]",
        requires_admin: false,
        help: "Chatty output stream: proves no-lag streaming",
        tab: "Debugging",
        label: "Demo Stream",
        is_read_only: true,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "number of lines (default 50)",
        action_label: "Stream",
        numeric_only: false,
    },
    // ---- AutoHotkey Scripts --------------------------------------
    Verb {
        verb: "ahk",
        script: "ahk-toggle.ps1",
        arguments: "-State enabled|disabled",
        requires_admin: false,
        help: "Turn all configured AHK scripts on or off",
        tab: "AutoHotkey",
        label: "AHK All",
        is_read_only: false,
        fixed_arguments: &["-State", "enabled"],
        render_in_gui: false,
        hint: "",
        action_label: "",
        numeric_only: false,
    },
    Verb {
        verb: "ahk-enable-all",
        script: "ahk-toggle.ps1",
        arguments: "-State enabled",
        requires_admin: false,
        help: "Enable every shipped AHK script and rewrite AppRunner.vbs",
        tab: "AutoHotkey",
        label: "Enable All AHK Scripts",
        is_read_only: false,
        fixed_arguments: &["-State", "enabled"],
        render_in_gui: true,
        hint: "",
        action_label: "Enable",
        numeric_only: false,
    },
    Verb {
        verb: "ahk-disable-all",
        script: "ahk-toggle.ps1",
        arguments: "-State disabled",
        requires_admin: false,
        help: "Disable every shipped AHK script and rewrite AppRunner.vbs",
        tab: "AutoHotkey",
        label: "Disable All AHK Scripts",
        is_read_only: false,
        fixed_arguments: &["-State", "disabled"],
        render_in_gui: true,
        hint: "",
        action_label: "Disable",
        numeric_only: false,
    },
    Verb {
        verb: "ahk-enable",
        script: "ahk-script.ps1",
        arguments: "-Name <key> -State enabled",
        requires_admin: false,
        help: "Enable one AHK script",
        tab: "AutoHotkey",
        label: "Enable AHK Script",
        is_read_only: false,
        fixed_arguments: &["-State", "enabled"],
        render_in_gui: false,
        hint: "script key: autocorrect | ChangeLangF3 | NewFile",
        action_label: "",
        numeric_only: false,
    },
    Verb {
        verb: "ahk-disable",
        script: "ahk-script.ps1",
        arguments: "-Name <key> -State disabled",
        requires_admin: false,
        help: "Disable one AHK script",
        tab: "AutoHotkey",
        label: "Disable AHK Script",
        is_read_only: false,
        fixed_arguments: &["-State", "disabled"],
        render_in_gui: false,
        hint: "script key: autocorrect | ChangeLangF3 | NewFile",
        action_label: "",
        numeric_only: false,
    },
    Verb {
        verb: "ahk-versions",
        script: "ahk-doctor.ps1",
        arguments: "-Action versions",
        requires_admin: false,
        help: "Where AutoHotkey v1 and v2 are installed, and which one resolves on PATH",
        tab: "AutoHotkey",
        label: "AHK Interpreter Versions",
        is_read_only: true,
        fixed_arguments: &["-Action", "versions"],
        render_in_gui: true,
        hint: "",
        action_label: "Check AHK 2",
        numeric_only: false,
    },
    Verb {
        verb: "ahk-newfile-check",
        script: "ahk-doctor.ps1",
        arguments: "-Action newfile",
        requires_admin: false,
        help: "Check the WIN+CTRL+N new-file script: enabled, and its interpreter present",
        tab: "AutoHotkey",
        label: "New File Script WIN+CTRL+N",
        is_read_only: true,
        fixed_arguments: &["-Action", "newfile"],
        render_in_gui: true,
        hint: "",
        action_label: "Check WIN+CTRL+N",
        numeric_only: false,
    },
    Verb {
        verb: "ahk-diagnose",
        script: "ahk-doctor.ps1",
        arguments: "-Action status",
        requires_admin: false,
        help: "Per-script state and interpreter, for troubleshooting a script that does not fire",
        tab: "AutoHotkey",
        label: "AutoHotkey Diagnostics",
        is_read_only: true,
        fixed_arguments: &["-Action", "status"],
        render_in_gui: true,
        hint: "",
        action_label: "Diagnose",
        numeric_only: false,
    },
    // ---- Uninstall and Cleanup -----------------------------------
    Verb {
        verb: "uninstall",
        script: "uninstall-komorebi-whkd.ps1",
        arguments: "-Scope <all|komorebi-whkd|yasb|autohotkey>",
        requires_admin: true,
        help: "Uninstall software",
        tab: "Uninstall",
        label: "Uninstall",
        is_read_only: false,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "all",
        action_label: "Uninstall",
        numeric_only: false,
    },
    Verb {
        verb: "cleanup",
        script: "cleanup-komorebi-whkd.ps1",
        arguments: "-Scope <all|komorebi-whkd|yasb|autohotkey>",
        requires_admin: true,
        help: "Remove leftover traces",
        tab: "Uninstall",
        label: "Cleanup",
        is_read_only: false,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "all",
        action_label: "Clean Up",
        numeric_only: false,
    },
];

/// Every registered verb, in tab order.
pub fn registry() -> &'static [Verb] {
    &VERBS
}

/// Look a verb up case-insensitively, or `None` when unknown.
pub fn find(verb: &str) -> Option<&'static Verb> {
    find_in(&VERBS, verb)
}

/// Look a verb up in an arbitrary table, case-insensitively.
///
/// [`find`] is this applied to the real table. Split out because the extension
/// rule must be provable against a table that contains a verb which is not
/// shipped — and a process-wide table cannot be mutated to say so.
pub fn find_in<'a>(verbs: &'a [Verb], verb: &str) -> Option<&'a Verb> {
    verbs.iter().find(|v| v.verb.eq_ignore_ascii_case(verb))
}

/// The verbs belonging to one tab, in registry order.
///
/// Includes verbs whose row is suppressed in favour of a more specific one, so
/// callers that need the full mechanism set — the CLI, `--help`, the elevation
/// message — still see them.
pub fn verbs_in_tab(id: &str) -> impl Iterator<Item = &'static Verb> + use<'_> {
    VERBS.iter().filter(move |v| v.tab == id)
}

/// The verbs that get a row on their own tab, in registry order. This is what
/// the generic row list binds to.
pub fn rows_in_tab(id: &str) -> impl Iterator<Item = &'static Verb> + use<'_> {
    verbs_in_tab(id).filter(|v| v.has_row())
}

/// The verbs that need an elevated host, for the elevation dialog's feature list
/// and for the CLI's refusal message. Generated from the registry, so it cannot
/// drift from what will actually be refused.
pub fn admin_verbs() -> impl Iterator<Item = &'static Verb> {
    VERBS.iter().filter(|v| v.requires_admin)
}

/// Rendered `--help` for a given table.
///
/// Taking the table as a parameter is what makes the extension rule testable:
/// a test can hand it a synthetic verb and prove that the new verb appears in
/// help, under its own tab heading, with no other change anywhere. The real
/// [`build_help`] is this function applied to the real table, so there is no
/// second copy of the text to drift.
pub fn render_help(verbs: &[Verb], tabs: &[Tab]) -> String {
    let mut text = String::from(
        "Komorebi Admin Dashboard\n\nUsage: KomorebiDashboard <verb> [arguments]\n\nVerbs:\n",
    );

    for tab in tabs {
        let mut section = String::new();
        for verb in verbs.iter().filter(|v| v.tab == tab.id) {
            let admin = if verb.requires_admin { " [admin]" } else { "" };
            // Pad the usage to a fixed column so the help text lines up. The
            // widest shape in the table is well under this, and a shape that
            // outgrows it simply pushes its own help right rather than clipping.
            section.push_str(&format!("    {:<58}{}{}\n", verb.usage(), verb.help, admin));
        }
        if section.is_empty() {
            continue;
        }
        text.push_str(&format!("  {}:\n{}", tab.label, section));
        text.push('\n');
    }

    text.push_str("Notes:\n");
    text.push_str(
        "  [admin]  needs an elevated shell; the GUI offers to relaunch itself as needed.\n",
    );
    text.push_str(
        "  kill-komorebi and start-komorebi also act on whkd, which runs with komorebi.\n",
    );
    text.push_str(
        "  ahk enable <key> / ahk disable <key> also work; keys are autocorrect, ChangeLangF3, NewFile.\n",
    );
    text.push_str(
        "  Argument values are checked by the scripts themselves; an invalid value exits non-zero.\n",
    );
    text
}

/// Rendered `--help` for the real table, generated on every call.
///
/// It cannot go stale the way a hand-written help file does, and a verb added to
/// the table appears here with no edit — the section comes from the row's own
/// tab, so a row cannot be registered in a place help does not show.
pub fn build_help() -> String {
    render_help(&VERBS, &TABS)
}
