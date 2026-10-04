namespace KomorebiDashboard.Models;

/// <summary>
/// The outcome of running a script. Returned by <c>ScriptService</c> and bound
/// to the output pane in the GUI, so it carries the exit code and the full
/// output rather than just "did it work".
/// </summary>
/// <param name="ExitCode">Process exit code. Zero means success.</param>
/// <param name="Output">Combined stdout and stderr, streamed from the script.</param>
/// <param name="Duration">Wall-clock time the script took.</param>
/// <param name="Verb">Which verb produced this, for display.</param>
public sealed record ScriptResult(
    int ExitCode,
    string Output,
    TimeSpan Duration,
    string Verb = "")
{
    /// <summary>True only when the script itself reported success.</summary>
    public bool Succeeded => ExitCode == 0;

    /// <summary>A one-line summary for the status bar.</summary>
    public string Summary =>
        $"{Verb} {(Succeeded ? "succeeded" : "FAILED")} (exit {ExitCode}, {Duration.TotalSeconds:0.0}s)";
}