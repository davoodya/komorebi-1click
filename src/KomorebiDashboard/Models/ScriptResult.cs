namespace KomorebiDashboard.Models;

/// <summary>
/// The outcome of running a script. Returned by <c>ScriptService</c> and bound
/// to the output pane in the GUI, so it carries the exit code, the duration and
/// the raw output rather than just "did it work".
///
/// <para>stdout and stderr are kept apart as well as combined. PowerShell
/// writes plenty of real errors to stderr while still exiting 0 (a cmdlet
/// warning, a Write-Warning), so treating any stderr as failure would make the
/// dashboard cry wolf; but discarding stderr would swallow exactly the detail
/// needed to diagnose a failure. Both are exposed.</para>
/// </summary>
/// <param name="ExitCode">Process exit code. Zero means success.</param>
/// <param name="Output">Combined stdout and stderr, streamed from the script.</param>
/// <param name="Duration">Wall-clock time the script took.</param>
/// <param name="Verb">Which verb produced this, for display.</param>
/// <param name="StandardError">Only the stderr text, kept separate for diagnosis.</param>
/// <param name="Cancelled">True when the user cancelled the run.</param>
/// <param name="TimedOut">True when the run exceeded its wall-clock budget.</param>
public sealed record ScriptResult(
    int ExitCode,
    string Output,
    TimeSpan Duration,
    string Verb = "",
    string StandardError = "",
    bool Cancelled = false,
    bool TimedOut = false)
{
    /// <summary>True only when the script itself reported success.</summary>
    public bool Succeeded => ExitCode == 0 && !Cancelled && !TimedOut;

    /// <summary>True when the run did not finish on its own terms.</summary>
    public bool Interrupted => Cancelled || TimedOut;

    /// <summary>One line for the status bar. Names the real reason, never "FAILED".</summary>
    public string Summary
    {
        get
        {
            if (TimedOut) return $"{Verb} TIMED OUT after {Duration.TotalSeconds:0.0}s";
            if (Cancelled) return $"{Verb} cancelled after {Duration.TotalSeconds:0.0}s";
            return $"{Verb} {(Succeeded ? "succeeded" : "FAILED")} (exit {ExitCode}, {Duration.TotalSeconds:0.0}s)";
        }
    }
}