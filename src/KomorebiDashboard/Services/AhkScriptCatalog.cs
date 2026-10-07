using System.IO;
using System.Text.Json;

namespace KomorebiDashboard.Services;

/// <summary>One shipped AutoHotkey script, as declared by the installer manifest.</summary>
/// <param name="Key">
/// The name the scripts use on the command line and in
/// <c>autohotkey\ahk-state.json</c> — <c>autocorrect</c>, <c>ChangeLangF3</c>,
/// <c>NewFile</c>. This is the identity of the script; the label is only for
/// display.
/// </param>
/// <param name="Label">Human-readable name shown in the tab.</param>
/// <param name="Description">What the script does, one line, for the row tooltip.</param>
/// <param name="Hotkey">The hotkey it binds, for the row text.</param>
/// <param name="Interpreter">Which AutoHotkey major version runs it.</param>
public sealed record AhkScriptInfo(
    string Key,
    string Label,
    string Description,
    string Hotkey,
    string Interpreter);

/// <summary>
/// The shipped AutoHotkey scripts, plus the on-disk state the installer reads.
///
/// WHY THE LIST IS NOT ENUMERATED FROM DISK
///   The authoritative list is <c>[script:AutoHotkeyScripts]</c> in
///   <c>scripts\Install-Common.ps1</c> — it is what the installer, the
///   <c>-List</c> switch and the state file all agree on. Enumerating
///   <c>autohotkey\*.ahk</c> would pick up a script the user dropped there,
///   which <c>ahk-script.ps1</c> would then refuse by name (it resolves names
///   against the manifest only). Transcribing the manifest here is what keeps
///   the tab from offering a button that cannot work.
///
/// WHY THE STATE FILE IS READ
///   <c>ahk-state.json</c> is written by the installer and by every ahk script,
///   so it is the real current state. Reading it means the tab opens showing
///   what is actually configured rather than assuming everything is enabled —
///   and it lets Apply skip the three subprocesses when nothing changed.
/// </summary>
public static class AhkScriptCatalog
{
    /// <summary>
    /// The manifest from Install-Common.ps1, in its order. The <c>Key</c> values
    /// MUST match <c>[script:AutoHotkeyScripts].Name</c> exactly, because that
    /// list is what <c>ahk-script.ps1</c> resolves <c>-Name</c> against and what
    /// <c>ahk-state.json</c> is keyed by. A rename on either side silently
    /// orphans a row: the tab would render a switch for a script the script
    /// itself refuses by name.
    ///
    /// tests/ticket08-ahk.tests.ps1 covers the manifest and the state mechanism;
    /// there is no automated cross-check of THESE strings against the installer,
    /// so verify by hand when either side changes:
    ///   grep -n -A4 'AutoHotkeyScripts' scripts/Install-Common.ps1
    /// </summary>
    public static readonly IReadOnlyList<AhkScriptInfo> Scripts = new[]
    {
        new AhkScriptInfo("autocorrect",  "Autocorrect Script",               "Auto-correct common typing mistakes as you type.", "runs on every word",   "v1"),
        new AhkScriptInfo("ChangeLangF3", "Change Language F3 Script",        "Switch the keyboard input language with F3.",      "F3",                   "v1"),
        new AhkScriptInfo("NewFile",      "Create New File WIN+CTRL+N Script", "Create a new file in the active folder.",         "Win+Ctrl+N",           "v2"),
    };

    /// <summary>Look a script up by its manifest key, or null.</summary>
    public static AhkScriptInfo? Find(string key) =>
        Scripts.FirstOrDefault(s => string.Equals(s.Key, key, StringComparison.OrdinalIgnoreCase));

    /// <summary>Path of the state file the installer writes.</summary>
    public static string StateFilePath(string scriptsDirectory) =>
        Path.Combine(RepoRoot(scriptsDirectory), "autohotkey", "ahk-state.json");

    /// <summary>
    /// Read the current state. A missing or unreadable file means "everything
    /// enabled", which is the installer's own default, so the tab still opens
    /// with a usable answer.
    /// </summary>
    public static Dictionary<string, bool> ReadState(string scriptsDirectory)
    {
        var state = Scripts.ToDictionary(s => s.Key, _ => true, StringComparer.OrdinalIgnoreCase);
        var path = StateFilePath(scriptsDirectory);

        if (!File.Exists(path)) return state;

        try
        {
            using var stream = File.OpenRead(path);
            var saved = JsonSerializer.Deserialize<Dictionary<string, bool>>(stream);
            if (saved is null) return state;

            foreach (var (key, enabled) in saved)
            {
                // Only names still in the manifest are honoured: a key that was
                // removed from the repo must not be carried forward.
                if (Find(key) is { } known) state[known.Key] = enabled;
            }
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            Console.WriteLine($"[KomorebiDashboard] ahk state unreadable ({ex.GetType().Name}); assuming all enabled");
        }

        return state;
    }

    /// <summary>
    /// The repo root, given the <c>scripts</c> directory. The installer keeps the
    /// state file under <c>&lt;repo&gt;\autohotkey\</c>, which is its sibling.
    /// </summary>
    private static string RepoRoot(string scriptsDirectory) =>
        Directory.GetParent(scriptsDirectory)?.FullName ?? scriptsDirectory;
}