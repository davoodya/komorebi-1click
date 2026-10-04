using KomorebiDashboard.Models;

namespace KomorebiDashboard.Services;

/// <summary>
/// THE single registry table (ADR-0013). The GUI binds its buttons from this,
/// the CLI dispatches through this, and <c>--help</c> is rendered from this.
/// Adding a verb is one row here plus one handler in ScriptService; nothing in
/// the parser or any View changes.
///
/// The verb set is transcribed from ADR-0013 and must match it exactly.
/// tests/ticket10-dashboard-shell.tests.ps1 cross-checks it.
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
    /// Every verb, in tab order. Arguments use &lt;&gt; for required and [] for
    /// optional, matching ADR-0013's notation so the two read identically.
    /// </summary>
    private static readonly VerbDefinition[] Definitions =
    {
        // ---- Kill / Start -------------------------------------------------
        // kill-all / kill-komorebi / kill-whkd / kill-yasb are ONE script
        // (kill-all.ps1) selected by -Components; only whkd-alone has its own
        // file, because spawning whkd without komorebi is the pairing bug.
        new("kill-all",        "kill-all.ps1",           "",              true,  "Stop komorebi, whkd and yasb",                 Tabs.KillStart,  "Kill All",      FixedArguments: "-Components all"),
        new("kill-komorebi",   "kill-all.ps1",           "",              true,  "Stop komorebi (and whkd, which runs with it)", Tabs.KillStart,  "Kill Komorebi", FixedArguments: "-Components komorebi-whkd"),
        new("kill-whkd",       "kill-whkd.ps1",          "",              true,  "Stop whkd only",                               Tabs.KillStart,  "Kill WHKD"),
        new("kill-yasb",       "kill-all.ps1",           "",              false, "Stop yasb only",                               Tabs.KillStart,  "Kill YASB",     FixedArguments: "-Components yasb"),
        new("start-all",       "start-all.ps1",          "",              false, "Start komorebi, whkd and yasb",               Tabs.KillStart,  "Start All",     FixedArguments: "-Components all"),
        new("start-komorebi",  "start-all.ps1",          "",              true,  "Start komorebi (and whkd, which runs with it)", Tabs.KillStart, "Start Komorebi", FixedArguments: "-Components komorebi-whkd"),
        new("start-whkd",      "start-whkd.ps1",         "",              true,  "Start whkd only (delegates to the safe path)", Tabs.KillStart, "Start WHKD"),
        new("start-yasb",      "start-all.ps1",          "",              false, "Start yasb only",                              Tabs.KillStart,  "Start YASB",    FixedArguments: "-Components yasb"),

        // ---- Restart ------------------------------------------------------
        new("restart-all",       "restart-all.ps1",       "",              false, "Safely restart everything (0-SAFE-RESTART)",   Tabs.Restart,    "Restart All"),
        new("restart-komorebi",  "restart-komorebi.ps1",  "",              false, "Restart komorebi (and whkd)",                 Tabs.Restart,    "Restart Komorebi"),
        new("restart-whkd",      "restart-whkd.ps1",      "",              false, "Restart whkd only",                           Tabs.Restart,    "Restart WHKD"),
        new("restart-yasb",      "restart-yasb.ps1",      "",              false, "Restart yasb (PATH rebuild preserved)",        Tabs.Restart,    "Restart YASB"),

        // ---- Settings / config -------------------------------------------
        new("startup",           "komorebi-service.ps1",  "add|remove",    true,  "Add or remove the logon + watchdog tasks",      Tabs.Settings,   "Startup"),
        new("export",            "komorebi-backup.ps1",   "export [-Path <dir>]", false, "Export the live configuration",            Tabs.Settings,   "Export Config"),
        new("import",            "komorebi-backup.ps1",   "import [-Path <zip>]", false, "Restore the configuration from a backup",   Tabs.Settings,   "Import Config"),
        new("set-transparency",  "toggle-transparency.ps1", "<0-100>",   false, "Set window transparency percent",             Tabs.Settings,   "Set Transparency"),

        // ---- Debugging ----------------------------------------------------
        new("status",            "komorebi-service.ps1",  "status",        false, "Read-only health check",                      Tabs.Debugging,  "Status",        IsReadOnly: true),
        new("recover-monitors",  "recover-monitors.ps1",  "",              false, "After plug/unplug: restore orphans and retile", Tabs.Debugging, "Recover Monitors"),
        new("display-diag",      "display-diag.ps1",      "",              false, "Compare monitor geometry across three sources", Tabs.Debugging, "Display Diagnostics", IsReadOnly: true),
        new("reset-workspaces",  "reset-workspaces.ps1",  "",              false, "Renumber workspaces 1..9 on every monitor",     Tabs.Debugging,  "Reset Workspaces"),
        new("repair-whkdrc",     "repair-whkdrc.ps1",     "",              false, "Rewrite whkdrc into the form whkd accepts",     Tabs.Debugging,  "Repair whkdrc"),

        // ---- AutoHotkey ---------------------------------------------------
        new("ahk",               "ahk-toggle.ps1",        "on|off",        false, "Turn all configured AHK scripts on or off",    Tabs.AutoHotkey, "AHK All"),
        new("ahk-enable",        "ahk-script.ps1",        "enable <name>", false, "Enable one AHK script",                        Tabs.AutoHotkey, "AHK Enable"),
        new("ahk-disable",       "ahk-script.ps1",        "disable <name>", false, "Disable one AHK script",                      Tabs.AutoHotkey, "AHK Disable"),

        // ---- Uninstall / Cleanup ------------------------------------------
        new("uninstall",         "uninstall-komorebi-whkd.ps1", "<scope>", true,  "Uninstall software (all|komorebi-whkd|yasb|autohotkey)", Tabs.Uninstall, "Uninstall"),
        new("cleanup",           "cleanup-komorebi-whkd.ps1",   "<scope>", true,  "Remove leftover traces (all|komorebi-whkd|yasb|autohotkey)", Tabs.Uninstall, "Cleanup"),
    };

    private static readonly Dictionary<string, VerbDefinition> ByVerb =
        Definitions.ToDictionary(d => d.Verb, StringComparer.OrdinalIgnoreCase);

    /// <summary>Every registered verb, in tab order.</summary>
    public static IReadOnlyList<VerbDefinition> All => Definitions;

    /// <summary>Look a verb up, or null when unknown.</summary>
    public static VerbDefinition? Find(string verb) =>
        ByVerb.TryGetValue(verb, out var d) ? d : null;

    /// <summary>The verbs belonging to one tab, for a View to bind to.</summary>
    public static IEnumerable<VerbDefinition> ForTab(string tab) =>
        Definitions.Where(d => string.Equals(d.Tab, tab, StringComparison.Ordinal));

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
                sb.AppendLine($"    {d.Usage,-34}{d.Help}{admin}");
            }
            sb.AppendLine();
        }

        sb.AppendLine("Notes:");
        sb.AppendLine("  [admin]  needs an elevated shell; the GUI relaunches itself as needed.");
        sb.AppendLine("  kill-komorebi and start-komorebi also act on whkd, which runs with komorebi.");
        sb.AppendLine("  See docs/adr/0013-cli-verb-set.md for the rationale.");
        return sb.ToString();
    }
}