using System.Diagnostics;
using System.Security.Principal;
using KomorebiDashboard.Models;

namespace KomorebiDashboard.Services;

/// <summary>
/// Per-operation elevation (ADR-0012).
///
/// WHY PER-OPERATION AND NOT "ALWAYS ELEVATED"
///   The Dashboard mixes per-user work (status, restart, transparency, AHK
///   toggles) with administrative work (uninstall, cleanup, startup tasks).
///   Running elevated all the time is bad practice and widens the blast radius
///   of any bug; never elevating makes half the tabs fail. So the app starts
///   unelevated and elevates per operation.
///
/// WHAT THIS CLASS GUARANTEES
///   - The answer to "am I elevated?" comes from the real Windows token, not a
///     heuristic.
///   - The dialog's message is GENERATED from VerbRegistry's RequiresAdmin
///     flags, so a newly added admin verb appears in the message with no code
///     change. A hardcoded list would silently go stale, and a stale list tells
///     the user the wrong thing about what will work.
///   - The unelevated instance EXITS after spawning the elevated one. Two live
///     instances racing over the same scheduled tasks is a real failure mode
///     (ADR-0012 Consequences), not a theoretical one.
/// </summary>
public sealed class ElevationService
{
    /// <summary>Exit code used when a verb needs Administrator and the CLI lacks it.</summary>
    public const int InsufficientPrivilegeExitCode = 740;

    /// <summary>True when this process holds an elevated administrator token.</summary>
    public static bool IsElevated
    {
        get
        {
            using var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
    }

    /// <summary>True when <paramref name="verb"/> may run in the current token.</summary>
    public static bool CanRun(VerbDefinition verb) => !verb.RequiresAdmin || IsElevated;

    /// <summary>
    /// The CLI refusal for a verb that needs Administrator and did not get it.
    ///
    /// Names the verb and says what to do. A bare "access denied" or, worse,
    /// exit 0 with no output, is the failure ADR-0012 explicitly calls out: a
    /// silent skip on <c>uninstall</c> is a data-loss-class surprise.
    /// </summary>
    public static string RefusalMessage(VerbDefinition verb)
    {
        var adminVerbs = AdminVerbNames();

        return $"" +
            $"'{verb.Verb}' requires Administrator rights." + Environment.NewLine +
            Environment.NewLine +
            $"  What it does      : {verb.Help}" + Environment.NewLine +
            $"  Usage             : {verb.Usage}" + Environment.NewLine +
            Environment.NewLine +
            (adminVerbs.Count > 0
                ? $"Administrator-only features: {string.Join(", ", adminVerbs)}{Environment.NewLine}"
                : string.Empty) +
            Environment.NewLine +
            "Rerun as Administrator to use it, for example from an elevated shell:" + Environment.NewLine +
            $"    Start-Process -FilePath \"<path-to>\\{Environment.ProcessPath}\" -Verb RunAs" + Environment.NewLine +
            Environment.NewLine +
            "Nothing was changed.";
    }

    /// <summary>
    /// The features that need Administrator, taken from the registry so the
    /// message cannot drift from reality.
    /// </summary>
    public static IReadOnlyList<string> AdminVerbNames() =>
        VerbRegistry.All.Where(v => v.RequiresAdmin).Select(v => v.Verb).ToList();

    /// <summary>
    /// The message shown in the "Rerun as Administrator" dialog.
    ///
    /// ADR-0012 requires it to name the SPECIFIC features rather than say
    /// "needs admin", because the user has to decide whether elevating is worth
    /// it — and that decision depends on which features are in play.
    /// </summary>
    public static string BuildElevationPrompt()
    {
        var adminVerbs = AdminVerbNames();

        var lines = new List<string>
        {
            "Some features in this Dashboard need Administrator rights:",
            "",
        };

        foreach (var name in adminVerbs)
        {
            lines.Add($"  • {name}");
        }

        lines.Add("");
        lines.Add("Without Administrator, those features cannot run. Everything else —");
        lines.Add("status, restarts, transparency, AutoHotkey — works normally as your user.");

        if (Environment.ProcessPath is { } exePath)
        {
            lines.Add("");
            lines.Add($"Rerun as Administrator to enable them:");
            lines.Add($"    {exePath}");
        }

        return string.Join(Environment.NewLine, lines);
    }

    /// <summary>
    /// Relaunch this app elevated and terminate the current instance.
    ///
    /// Returns false when the launch could not even be attempted; the caller
    /// must NOT exit in that case, or the user would lose the window they were
    /// looking at and gain nothing.
    /// </summary>
    public static bool RelaunchElevated()
    {
        if (Environment.ProcessPath is not { } exePath) return false;

        try
        {
            // "runas" is what triggers the UAC consent prompt. UseShellExecute
            // MUST be true for it to work at all: the shell has to be involved
            // in the elevation handshake, and ProcessStartInfo rejects the
            // combination of runas with UseShellExecute=false.
            Process.Start(new ProcessStartInfo
            {
                FileName = exePath,
                UseShellExecute = true,
                Verb = "runas",
                WorkingDirectory = Environment.CurrentDirectory,
            });

            return true;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            // Win32Exception(1223) is "The operation was canceled by the user"
            // — declining the UAC prompt. That is a choice, not a failure, and
            // must not be reported as one.
            return false;
        }
    }
}