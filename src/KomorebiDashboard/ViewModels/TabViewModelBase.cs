using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using KomorebiDashboard.Models;
using KomorebiDashboard.Services;

namespace KomorebiDashboard.ViewModels;

/// <summary>
/// Base for the six tab ViewModels (ADR-0009 middle tier).
///
/// Holds no business logic: every button resolves its verb through
/// <see cref="VerbRegistry"/> and asks <see cref="ScriptService"/> to run it.
/// The Views bind to <see cref="Commands"/> and <see cref="Output"/> and hold no
/// logic of their own.
/// </summary>
public abstract partial class TabViewModelBase : ObservableObject
{
    protected readonly ScriptService Scripts;

    /// <summary>
    /// The buttons for this tab, generated from the registry. There is exactly
    /// one constructor because Commands is derived from the tab name: a second
    /// constructor taking only the service would have to leave Commands unset.
    /// </summary>
    public ObservableCollection<VerbDefinition> Commands { get; }

    /// <summary>Live script output, bound to the output pane.</summary>
    [ObservableProperty]
    private string _output = "Ready.";

    /// <summary>One-line summary of the last run.</summary>
    [ObservableProperty]
    private string _status = "No command run yet.";

    /// <summary>True while a script is running, so buttons can be disabled.</summary>
    [ObservableProperty]
    // Names the generated COMMAND property, not the method: [RelayCommand]
    // produces RunVerbCommand, and the attribute is validated against the
    // members of this type rather than against the source-generation output.
    [NotifyCanExecuteChangedFor(nameof(RunVerbCommand))]
    private bool _isBusy;

    /// <summary>Argument entered for verbs that take one, e.g. a transparency value.</summary>
    [ObservableProperty]
    private string _argument = string.Empty;

    protected TabViewModelBase(ScriptService scripts, string tab)
    {
        Scripts = scripts;
        Commands = new ObservableCollection<VerbDefinition>(VerbRegistry.ForTab(tab));
    }

    /// <summary>
    /// The single execution path. The GUI button and the CLI verb both end up
    /// here, which is what keeps them behaving identically.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanRun))]
    private async Task RunVerbAsync(string verb)
    {
        var def = VerbRegistry.Find(verb);
        if (def is null) { Status = $"Unknown verb '{verb}'."; return; }

        IsBusy = true;
        Output = $"$ {def.Script}{(string.IsNullOrWhiteSpace(Argument) ? "" : " " + Argument.Trim())}";

        try
        {
            var args = SplitArguments(Argument);
            var result = await Scripts.RunAsync(verb, args, line => Output += line + Environment.NewLine);

            Output += Environment.NewLine + result.Output;
            Status = result.Summary;
        }
        catch (Exception ex)
        {
            // A failure here is the user's problem to see, never to swallow.
            Output += Environment.NewLine + ex.Message;
            Status = $"{verb} threw: {ex.Message}";
        }
        finally
        {
            IsBusy = false;
        }
    }

    private bool CanRun() => !IsBusy;

    /// <summary>
    /// Split the argument box on whitespace, honouring simple double quotes so a
    /// path with spaces survives.
    /// </summary>
    private static IReadOnlyList<string> SplitArguments(string input)
    {
        if (string.IsNullOrWhiteSpace(input)) return Array.Empty<string>();

        var parts = new List<string>();
        var current = new System.Text.StringBuilder();
        var inQuotes = false;

        foreach (var ch in input.Trim())
        {
            if (ch == '"') { inQuotes = !inQuotes; continue; }
            if (char.IsWhiteSpace(ch) && !inQuotes)
            {
                if (current.Length > 0) { parts.Add(current.ToString()); current.Clear(); }
                continue;
            }
            current.Append(ch);
        }

        if (current.Length > 0) parts.Add(current.ToString());
        return parts;
    }
}