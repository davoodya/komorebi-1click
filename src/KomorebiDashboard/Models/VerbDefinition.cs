namespace KomorebiDashboard.Models;

/// <summary>
/// One registry row: the single description of a verb. The GUI button, the CLI
/// dispatch and the help text are all generated from these, which is what makes
/// it impossible for the GUI and the CLI to disagree (ADR-0013).
/// </summary>
/// <param name="Verb">The name used on the command line.</param>
/// <param name="Script">File name of the .ps1 that does the actual work.</param>
/// <param name="Arguments">
/// Shape of the arguments this verb takes, for help and for the GUI's argument
/// box. <c>&lt;x&gt;</c> marks a required value and <c>[x]</c> an optional one,
/// matching ADR-0013's notation.
/// </param>
/// <param name="RequiresAdmin">True when the script needs an elevated host.</param>
/// <param name="Help">One line of help, also used by --help and as the row tooltip.</param>
/// <param name="Tab">Which tab owns the button. Every verb appears in exactly one.</param>
/// <param name="Label">Button caption.</param>
/// <param name="IsReadOnly">
/// True when the verb changes nothing on the system. Read-only rows are marked in
/// the UI so a diagnostic can never be mistaken for an action.
/// </param>
/// <param name="FixedArguments">
/// Arguments always passed to the script, BEFORE any the user typed. Several
/// verbs share one script and differ only by a flag — kill-komorebi, kill-whkd
/// and kill-yasb are all <c>kill-all.ps1 -Components &lt;x&gt;</c> — so this is
/// what keeps those rows pointing at real, existing scripts instead of at six
/// .ps1 files that were never written.
/// </param>
/// <param name="RenderInGui">
/// False for verbs that exist for the CLI and for <c>--help</c> but have no row
/// of their own because a more specific pair of rows supersedes them in the tab
/// (e.g. <c>startup</c> is reached from the GUI as Add/Remove to Startup).
/// The verb stays fully dispatchable; only the row is suppressed.
/// </param>
/// <param name="Hint">
/// Placeholder text for the row's input box, e.g. <c>0-100</c>. Stated
/// explicitly rather than derived from <see cref="Arguments"/>: the shape is
/// notation for <c>--help</c>, and a value a user should type is a different
/// string.
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
    string FixedArguments = "",
    bool RenderInGui = true,
    string Hint = "",
    string ActionLabel = "",
    bool NumericOnly = false)
{
    /// <summary>
    /// The command line form, rendered from the same fields the GUI uses. Kept
    /// here rather than in the parser so help and dispatch cannot diverge.
    /// </summary>
    public string Usage => Arguments.Length == 0 ? Verb : $"{Verb} {Arguments}";

    /// <summary>
    /// True when the user has to supply a value, i.e. the shape mentions one
    /// (either required <c>&lt;x&gt;</c> or optional <c>[x]</c>).
    ///
    /// This is what decides whether a row draws an input box. Deriving it from
    /// the registry means a new verb gets the right row shape with no view
    /// change — and a verb that takes no value can never show a box whose
    /// contents would be silently ignored.
    /// </summary>
    public bool AcceptsUserArguments => Arguments.Contains('<') || Arguments.Contains('[');

    /// <summary>
    /// True when the only acceptable value is a whole number, so the row draws a
    /// narrow numeric box and the typed text is filtered to digits.
    ///
    /// A separate flag from <see cref="AcceptsUserArguments"/>: that one decides
    /// whether a box exists at all, this one decides what may go in it. A verb
    /// can take a free-text path (Import Config) or a bare number (Set
    /// Transparency), and deriving one from the other by inspecting the argument
    /// shape would mean guessing from punctuation.
    /// </summary>
    public bool IsNumeric => NumericOnly;
}