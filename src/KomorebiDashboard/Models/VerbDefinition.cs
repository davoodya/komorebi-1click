namespace KomorebiDashboard.Models;

/// <summary>
/// One registry row: the single description of a verb. The GUI button, the CLI
/// dispatch and the help text are all generated from these, which is what makes
/// it impossible for the GUI and the CLI to disagree (ADR-0013).
/// </summary>
/// <param name="Verb">The name used on the command line.</param>
/// <param name="Script">File name of the .ps1 that does the actual work.</param>
/// <param name="Arguments">Shape of the arguments this verb takes.</param>
/// <param name="RequiresAdmin">True when the script needs an elevated host.</param>
/// <param name="Help">One line of help, also used by --help.</param>
/// <param name="Tab">Which tab owns the button. Every verb appears in exactly one.</param>
/// <param name="Label">Button caption.</param>
/// <param name="IsReadOnly">True when the verb changes nothing on the system.</param>
/// <param name="FixedArguments">
/// Arguments always passed to the script, before any the user typed. Several
/// verbs share one script and differ only by a flag -- kill-komorebi,
/// kill-whkd and kill-yasb are all kill-all.ps1 -Components &lt;x&gt; -- so this
/// is what keeps those rows pointing at real, existing scripts instead of at
/// six .ps1 files that were never written.
/// </param>
public sealed record VerbDefinition(
    string Verb,
    string Script,
    string Arguments,
    bool RequiresAdmin,
    string Help,
    string Tab,
    string Label,
    bool IsReadOnly = false,
    string FixedArguments = "")
{
    /// <summary>
    /// The command line form, rendered from the same fields the GUI uses. Kept
    /// here rather than in the parser so help and dispatch cannot diverge.
    /// </summary>
    public string Usage => Arguments.Length == 0
        ? Verb
        : $"{Verb} {Arguments}";
}