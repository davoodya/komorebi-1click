using CommunityToolkit.Mvvm.ComponentModel;

namespace KomorebiDashboard.Models;

/// <summary>
/// One rendered row: a registry verb plus the value the user has typed into that
/// row's own box.
///
/// WHY A WRAPPER AND NOT THE RECORD ITSELF
///   <see cref="VerbDefinition"/> is shared, immutable registry data. The value a
///   user types is per-row state, so binding the row's box to a single shared
///   argument would make every row mirror the same text — type "85" into Set
///   Transparency, and "85" appears in Import Config's box too, which then gets
///   passed to a script that rejects it. Ownership of the value belongs to the
///   row.
///
/// The pass-through properties exist so the row template can bind one item
/// without reaching through <c>Definition.</c> on every line.
/// </summary>
public sealed partial class VerbRow : ObservableObject
{
    /// <summary>The registry entry this row renders.</summary>
    public VerbDefinition Definition { get; }

    /// <summary>What the user typed for this row. Empty when the row takes no value.</summary>
    [ObservableProperty]
    private string _argument = string.Empty;

    public VerbRow(VerbDefinition definition)
    {
        Definition = definition;
    }

    /// <summary>
    /// Keep a numeric row numeric.
    ///
    /// Enforced HERE rather than with a PreviewTextInput handler in the View: a
    /// keystroke filter only sees typing, so a paste, a drag-and-drop, an IME
    /// composition or a programmatic assignment all bypass it. Filtering the
    /// value itself catches every route, and it keeps the rule out of the View
    /// layer, which the project's tests require to hold no logic.
    ///
    /// Filtering rather than rejecting keeps typing usable: a stray letter is
    /// dropped as it arrives instead of leaving the box in a state the user has
    /// to notice and clear.
    /// </summary>
    partial void OnArgumentChanged(string value)
    {
        if (!Definition.IsNumeric) return;
        if (string.IsNullOrEmpty(value)) return;

        var digits = new string(value.Where(char.IsAsciiDigit).ToArray());
        if (digits != value) Argument = digits;
    }

    public string Verb => Definition.Verb;
    public string Label => Definition.Label;
    public string Help => Definition.Help;
    public bool IsReadOnly => Definition.IsReadOnly;
    public bool AcceptsUserArguments => Definition.AcceptsUserArguments;
    public string Hint => Definition.Hint;

    /// <summary>True when the row's box accepts digits only.</summary>
    public bool IsNumeric => Definition.IsNumeric;

    /// <summary>
    /// What the row's button says. Falls back to the row's name when the
    /// registry does not set one, so a row can never render a blank button.
    ///
    /// The caption belongs on the definition (ADR-0013) rather than in markup:
    /// one row is rendered by the shared template in App.xaml, and also by the
    /// AutoHotkey tab's own template, so a caption chosen in a View would have
    /// to be chosen twice and could differ between them.
    /// </summary>
    public string ActionLabel =>
        string.IsNullOrWhiteSpace(Definition.ActionLabel) ? Definition.Label : Definition.ActionLabel;
}