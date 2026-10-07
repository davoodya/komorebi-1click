using KomorebiDashboard.Models;

namespace KomorebiDashboard.Services;

/// <summary>
/// THE single registry table (ADR-0013). The GUI binds its rows from this, the
/// CLI dispatches through this, and <c>--help</c> is rendered from this.
/// Adding a verb is one row here; nothing in the parser or any View changes.
///
/// ARGUMENT SHAPES ARE READ FROM THE SCRIPTS, NOT FROM THE ADR.
///   Every row's arguments and fixed arguments were checked against the target
///   script's real <c>param</c> block. Two earlier rows were not, and were dead
///   on arrival:
///     * <c>startup</c> advertised <c>add|remove</c> while
///       komorebi-service.ps1's <c>-Action</c> is a ValidateSet of
///       install|uninstall|start|stop|restart|status|retile|watchdog, so every
///       click failed parameter binding and changed nothing.
///     * <c>ahk</c> advertised <c>on|off</c> while ahk-toggle.ps1's
///       <c>-State</c> accepts enabled|disabled.
///   A registry row that names an argument the script rejects is worse than a
///   missing row: the button looks present and silently does nothing.
/// </summary>
public static class VerbRegistry
{
    /// <summary>Tab names, kept as constants so a typo cannot orphan a verb.</summary>
    public static class Tabs
    {
        public const string KillStart   = "KillStart";
        public const string Restart     = "Restart";
        public const string Settings    = "Settings";
        public const string AutoHotkey  = "AutoHotkey";
        public const string Debugging   = "Debugging";
        public const string Uninstall   = "Uninstall";

        public static readonly string[] All =
            { KillStart, Restart, Settings, AutoHotkey, Debugging, Uninstall };
    }

    /// <summary>
    /// Every verb, in tab order. tests/ticket10-dashboard-shell.tests.ps1 scans
    /// this file for rows in the recorded call shape and checks that each named
    /// .ps1 exists under scripts/, so keep new rows in that shape.
    ///
    /// CAUTION: do not write a literal sample of the call anywhere in this file.
    /// The scan strips line comments but not doc comments, and it cannot tell a
    /// sample from a row, so a sample registers as a verb of its own and the
    /// suite reports a script that was never meant to exist as missing. This
    /// comment used to contain such a sample, and it did exactly that.
    /// </summary>
    private static readonly VerbDefinition[] Definitions =
    {
        // ---- Kill / Start -------------------------------------------------
        // kill-all / kill-komorebi / kill-yasb are ONE script (kill-all.ps1)
        // selected by -Components; only whkd-alone has its own file, because
        // spawning whkd without komorebi is the pairing bug.
        new("kill-all",        "kill-all.ps1",           "-Components all|komorebi-whkd|yasb", true,  "Stop komorebi, whkd and yasb",                 Tabs.KillStart,  "Kill All",      FixedArguments: "-Components all", ActionLabel: "Kill"),
        new("kill-komorebi",   "kill-all.ps1",           "-Components komorebi-whkd",          true,  "Stop komorebi (and whkd, which runs with it)", Tabs.KillStart,  "Kill Komorebi", FixedArguments: "-Components komorebi-whkd", ActionLabel: "Kill"),
        new("kill-whkd",       "kill-whkd.ps1",          "",                                   true,  "Stop whkd only",                               Tabs.KillStart,  "Kill WHKD",     ActionLabel: "Kill"),
        new("kill-yasb",       "kill-all.ps1",           "-Components yasb",                   false, "Stop yasb only",                               Tabs.KillStart,  "Kill YASB",     FixedArguments: "-Components yasb", ActionLabel: "Kill"),
        new("start-all",       "start-all.ps1",          "-Components all|komorebi-whkd|yasb", false, "Start komorebi, whkd and yasb",               Tabs.KillStart,  "Start All",     FixedArguments: "-Components all", ActionLabel: "Start"),
        new("start-komorebi",  "start-all.ps1",          "-Components komorebi-whkd",          true,  "Start komorebi (and whkd, which runs with it)", Tabs.KillStart, "Start Komorebi", FixedArguments: "-Components komorebi-whkd", ActionLabel: "Start"),
        new("start-whkd",      "start-whkd.ps1",         "-Force (switch)",                    true,  "Start whkd only (delegates to the whkd-safe path)", Tabs.KillStart, "Start WHKD", ActionLabel: "Start"),
        new("start-yasb",      "start-all.ps1",          "-Components yasb",                   false, "Start yasb only",                              Tabs.KillStart,  "Start YASB",    FixedArguments: "-Components yasb", ActionLabel: "Start"),

        // ---- Restart ------------------------------------------------------
        new("restart-all",       "restart-all.ps1",       "",   false, "Safely restart everything (0-SAFE-RESTART)",   Tabs.Restart, "Restart All", ActionLabel: "Restart"),
        new("restart-komorebi",  "restart-komorebi.ps1",  "",   false, "Restart komorebi (and whkd)",                 Tabs.Restart, "Restart Komorebi", ActionLabel: "Restart"),
        new("restart-whkd",      "restart-whkd.ps1",      "",   false, "Restart whkd only",                           Tabs.Restart, "Restart WHKD", ActionLabel: "Restart"),
        new("restart-yasb",      "restart-yasb.ps1",      "",   false, "Restart yasb (PATH rebuild preserved)",        Tabs.Restart, "Restart YASB", ActionLabel: "Restart"),

        // ---- Settings / config -------------------------------------------
        // -Action, not add|remove: see the class comment. -Mode, not a bare
        // positional, or the first argument binds to the partition switch and
        // trips its ValidateSet instead of reaching -ZipPath.
        new("startup",         "komorebi-service.ps1",    "-Action install|uninstall", true,  "Register or remove the logon + watchdog tasks", Tabs.Settings, "Startup", FixedArguments: "-Action install", RenderInGui: false),
        new("startup-install", "komorebi-service.ps1",    "-Action install",           true,  "Start komorebi + whkd automatically at logon, with a watchdog", Tabs.Settings, "Add to Startup",   FixedArguments: "-Action install",   ActionLabel: "Add"),
        new("startup-remove",  "komorebi-service.ps1",    "-Action uninstall",         true,  "Remove the logon and watchdog tasks; the running session is untouched", Tabs.Settings, "Remove from Startup", FixedArguments: "-Action uninstall", ActionLabel: "Remove"),
        new("export",          "komorebi-backup.ps1",     "-ZipPath [directory]",      false, "Export the live configuration",                Tabs.Settings, "Export Config", FixedArguments: "-Mode export", Hint: "folder to write the backup into (optional)", ActionLabel: "Export"),
        new("import",          "komorebi-backup.ps1",     "-ZipPath [file or folder]", false, "Restore the configuration from a backup",      Tabs.Settings, "Import Config", FixedArguments: "-Mode import", Hint: "backup folder to restore (optional)", ActionLabel: "Import"),
        new("set-transparency", "toggle-transparency.ps1", "-Percent <0-100>",         false, "Set window transparency percent",              Tabs.Settings, "Set Transparency", Hint: "enter percentage only", ActionLabel: "Apply", NumericOnly: true),

        // On a multi-monitor desk komorebi mis-handles some WPF windows (this
        // Dashboard included) when it spans or crosses a monitor boundary. The
        // fix is a real komorebi ignore rule, written by the script and
        // hot-reloaded, so the window keeps its own place on screen.
        //
        // The Help text is a full sentence because it is shown verbatim under the
        // row title: it is the only place the user is told WHY this exists.
        new("ignore-dashboard", "ignore-dashboard.ps1",   "",                          false,
            "On a multi-monitor system komorebi can push some WPF windows across a monitor boundary. " +
            "This is a known komorebi bug and it affects other windows too, such as ncpa.cpl, Device Manager " +
            "and Disk Management. Adding the rule makes komorebi stop managing KomorebiDashboard.exe.",
            Tabs.Settings, "Ignore KomorebiDashboard", ActionLabel: "Add Rule"),

        // ---- Debugging ----------------------------------------------------
        new("status",            "komorebi-service.ps1",  "status", false, "Read-only health check",                      Tabs.Debugging,  "Status",        IsReadOnly: true, FixedArguments: "-Action status", ActionLabel: "Check"),
        new("recover-monitors",  "recover-monitors.ps1",  "",       false, "After plug/unplug: restore orphans and retile", Tabs.Debugging, "Recover Monitors", ActionLabel: "Recover"),
        new("display-diag",      "display-diag.ps1",      "",       false, "Compare monitor geometry across three sources", Tabs.Debugging, "Display Diagnostics", IsReadOnly: true, ActionLabel: "Inspect"),
        new("reset-workspaces",  "reset-workspaces.ps1",  "",       false, "Renumber workspaces 1..9 on every monitor",     Tabs.Debugging,  "Reset Workspaces", ActionLabel: "Reset"),
        new("repair-whkdrc",     "repair-whkdrc.ps1",     "",       false, "Rewrite whkdrc into the form whkd accepts",     Tabs.Debugging,  "Repair whkdrc", ActionLabel: "Repair"),

        // Deliberately chatty and long-running (ticket 11). It touches nothing
        // on the system — pure console output — so it is safe to run anywhere,
        // including on a live box, and it is what proves the UI stays
        // responsive while output streams.
        new("demo-stream",       "demo-stream.ps1",       "-Lines [n] -DelayMs [ms]", false, "Chatty output stream: proves no-lag streaming", Tabs.Debugging, "Demo Stream", IsReadOnly: true, Hint: "number of lines (default 50)", ActionLabel: "Stream"),

        // ---- AutoHotkey ---------------------------------------------------
        // The CLI keeps ADR-0013's `ahk on|off` spelling; the STATE value is
        // enabled|disabled, which is what ahk-toggle.ps1 -State accepts.
        new("ahk",               "ahk-toggle.ps1",        "-State enabled|disabled",   false, "Turn all configured AHK scripts on or off",   Tabs.AutoHotkey, "AHK All", FixedArguments: "-State enabled", RenderInGui: false),
        new("ahk-enable-all",    "ahk-toggle.ps1",        "-State enabled",            false, "Enable every shipped AHK script and rewrite AppRunner.vbs", Tabs.AutoHotkey, "Enable All AHK Scripts",  FixedArguments: "-State enabled", ActionLabel: "Enable"),
        new("ahk-disable-all",   "ahk-toggle.ps1",        "-State disabled",           false, "Disable every shipped AHK script and rewrite AppRunner.vbs", Tabs.AutoHotkey, "Disable All AHK Scripts", FixedArguments: "-State disabled", ActionLabel: "Disable"),
        // -Name takes the manifest key (autocorrect, ChangeLangF3, NewFile), not
        // the display label: the scripts resolve names against the installer
        // manifest, so a label would be rejected as unknown.
        new("ahk-enable",        "ahk-script.ps1",        "-Name <key> -State enabled",  false, "Enable one AHK script",  Tabs.AutoHotkey, "Enable AHK Script",  RenderInGui: false, Hint: "script key: autocorrect | ChangeLangF3 | NewFile", FixedArguments: "-State enabled"),
        new("ahk-disable",       "ahk-script.ps1",        "-Name <key> -State disabled", false, "Disable one AHK script", Tabs.AutoHotkey, "Disable AHK Script", RenderInGui: false, Hint: "script key: autocorrect | ChangeLangF3 | NewFile", FixedArguments: "-State disabled"),

        // Troubleshooting rows. All three read state and report; none of them
        // writes anything, which is why they are marked IsReadOnly and are safe
        // to run on a working installation. The installer's AutoHotkey setup is
        // deliberately NOT reconfigured from here.
        new("ahk-versions",      "ahk-doctor.ps1",        "-Action versions",  false, "Where AutoHotkey v1 and v2 are installed, and which one resolves on PATH", Tabs.AutoHotkey, "AHK Interpreter Versions", IsReadOnly: true, FixedArguments: "-Action versions", ActionLabel: "Check AHK 2"),
        new("ahk-newfile-check", "ahk-doctor.ps1",        "-Action newfile",   false, "Check the WIN+CTRL+N new-file script: enabled, and its interpreter present", Tabs.AutoHotkey, "New File Script WIN+CTRL+N", IsReadOnly: true, FixedArguments: "-Action newfile", ActionLabel: "Check WIN+CTRL+N"),
        new("ahk-diagnose",      "ahk-doctor.ps1",        "-Action status",    false, "Per-script state and interpreter, for troubleshooting a script that does not fire", Tabs.AutoHotkey, "AutoHotkey Diagnostics", IsReadOnly: true, FixedArguments: "-Action status", ActionLabel: "Diagnose"),

        // ---- Uninstall / Cleanup ------------------------------------------
        new("uninstall",         "uninstall-komorebi-whkd.ps1", "-Scope <all|komorebi-whkd|yasb|autohotkey>", true, "Uninstall software", Tabs.Uninstall, "Uninstall", Hint: "all", ActionLabel: "Uninstall"),
        new("cleanup",           "cleanup-komorebi-whkd.ps1",   "-Scope <all|komorebi-whkd|yasb|autohotkey>", true, "Remove leftover traces", Tabs.Uninstall, "Cleanup",   Hint: "all", ActionLabel: "Clean Up"),
    };

    private static readonly Dictionary<string, VerbDefinition> ByVerb =
        Definitions.ToDictionary(d => d.Verb, StringComparer.OrdinalIgnoreCase);

    /// <summary>Every registered verb, in tab order.</summary>
    public static IReadOnlyList<VerbDefinition> All => Definitions;

    /// <summary>Look a verb up, or null when unknown.</summary>
    public static VerbDefinition? Find(string verb) =>
        ByVerb.TryGetValue(verb, out var d) ? d : null;

    /// <summary>
    /// The verbs belonging to one tab, for a View to bind to. Includes verbs whose
    /// row is suppressed in favour of a more specific one, so callers that need the
    /// full mechanism set (the CLI, --help, the elevation message) still see them.
    /// </summary>
    public static IEnumerable<VerbDefinition> ForTab(string tab) =>
        Definitions.Where(d => string.Equals(d.Tab, tab, StringComparison.Ordinal));

    /// <summary>
    /// The verbs that get a row on their own tab, in registry order. This is what
    /// the generic row list binds to.
    /// </summary>
    public static IEnumerable<VerbDefinition> RowsForTab(string tab) =>
        ForTab(tab).Where(d => d.RenderInGui);

    /// <summary>
    /// Rendered --help. Generated from the table on every call, so it cannot go
    /// stale the way a hand-written help file does.
    /// </summary>
    public static string BuildHelp()
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine("Komorebi Admin Dashboard");
        sb.AppendLine();
        sb.AppendLine("Usage: KomorebiDashboard <verb> [arguments]");
        sb.AppendLine();
        sb.AppendLine("Verbs:");

        foreach (var tab in Tabs.All)
        {
            sb.AppendLine($"  {tab}:");
            foreach (var d in ForTab(tab))
            {
                var admin = d.RequiresAdmin ? " [admin]" : "";
                sb.AppendLine($"    {d.Usage,-58}{d.Help}{admin}");
            }
            sb.AppendLine();
        }

        sb.AppendLine("Notes:");
        sb.AppendLine("  [admin]  needs an elevated shell; the GUI offers to relaunch itself as needed.");
        sb.AppendLine("  kill-komorebi and start-komorebi also act on whkd, which runs with komorebi.");
        sb.AppendLine("  ahk enable <key> / ahk disable <key> also work; keys are autocorrect, ChangeLangF3, NewFile.");
        sb.AppendLine("  Argument values are checked by the scripts themselves; an invalid value exits non-zero.");
        return sb.ToString();
    }
}