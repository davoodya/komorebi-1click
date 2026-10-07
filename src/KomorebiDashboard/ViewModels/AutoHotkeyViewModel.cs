using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using KomorebiDashboard.Models;
using KomorebiDashboard.Services;

namespace KomorebiDashboard.ViewModels;

/// <summary>
/// One shipped AutoHotkey script as a row: its metadata from the installer
/// manifest, the state it currently has on disk, and the state the user has
/// selected but not yet applied.
///
/// WHY THE SELECTION IS SEPARATE FROM THE APPLIED STATE
///   Every applied change launches <c>ahk-script.ps1</c>, which rewrites
///   AppRunner.vbs and starts or stops a process. Wiring the radio buttons
///   straight to the script would mean three process launches for three clicks,
///   racing each other over the same generated file. So the radio pair moves the
///   SELECTION, and Apply is what commits it.
/// </summary>
public sealed partial class AhkScriptRow : ObservableObject
{
    /// <summary>The manifest key the scripts accept by name.</summary>
    public string Key { get; }

    /// <summary>What the user sees.</summary>
    public string Label { get; }

    /// <summary>One line, shown under the name.</summary>
    public string Description { get; }

    /// <summary>The hotkey, shown as a badge.</summary>
    public string Hotkey { get; }

    /// <summary>AutoHotkey v1 or v2 — the manifest pins which interpreter runs it.</summary>
    public string Interpreter { get; }

    /// <summary>
    /// Radio-button group name, so two rows can never steal each other's selection.
    /// Null-safe: WPF treats an empty GroupName as "no group" and every radio on
    /// the tab would then be one group.
    /// </summary>
    public string GroupName => $"ahk-{Key}";

    /// <summary>The state on disk, refreshed after every Apply.</summary>
    [ObservableProperty] private bool _appliedEnabled;

    /// <summary>What the user has selected for the next Apply.</summary>
    [ObservableProperty] private bool _isEnabled;

    /// <summary>True when the selection differs from what the scripts have.</summary>
    public bool IsDirty => IsEnabled != AppliedEnabled;

    /// <summary>Short state line shown in the row.</summary>
    public string StatusText => IsDirty
        ? $"Will be {(IsEnabled ? "enabled" : "disabled")} when you press Apply."
        : $"Currently {(AppliedEnabled ? "enabled" : "disabled")} · AutoHotkey {Interpreter}";

    /// <summary>Convenience inverse, so the "Disable" radio binds without a converter.</summary>
    public bool IsDisabled
    {
        get => !IsEnabled;
        set => IsEnabled = !value;
    }

    public AhkScriptRow(AhkScriptInfo info, bool appliedEnabled)
    {
        Key = info.Key;
        Label = info.Label;
        Description = info.Description;
        Hotkey = info.Hotkey;
        Interpreter = info.Interpreter;

        _appliedEnabled = appliedEnabled;
        _isEnabled = appliedEnabled;
    }

    partial void OnIsEnabledChanged(bool value)
    {
        OnPropertyChanged(nameof(IsDisabled));
        RaiseStatusChanged();
    }

    partial void OnAppliedEnabledChanged(bool value) => RaiseStatusChanged();

    private void RaiseStatusChanged()
    {
        OnPropertyChanged(nameof(IsDirty));
        OnPropertyChanged(nameof(StatusText));
    }

    /// <summary>Accept the pending selection as the applied state.</summary>
    public void MarkApplied() => AppliedEnabled = IsEnabled;

    /// <summary>Discard the pending selection.</summary>
    public void Revert() => IsEnabled = AppliedEnabled;
}

/// <summary>
/// AutoHotkey Scripts tab.
///
/// Inherits <see cref="TabViewModelBase"/> so the console, the busy state and the
/// cancel/clear commands are the shared ones rather than a second implementation
/// (which is what the previous version had, and why it flushed output differently
/// from every other tab).
/// </summary>
public sealed partial class AutoHotkeyViewModel : TabViewModelBase
{
    private readonly string _scriptsDirectory;

    /// <summary>The three shipped scripts, with their real on-disk state.</summary>
    /// <remarks>
    /// Named ScriptRows, not Scripts: the base class already exposes a protected
    /// Scripts property holding the ScriptService, and shadowing it made every
    /// Scripts.RunAsync call in this file bind to the collection instead.
    /// </remarks>
    public ObservableCollection<AhkScriptRow> ScriptRows { get; }

    /// <summary>The registry's "all scripts" rows (disable-all, enable-all).</summary>
    public ObservableCollection<VerbRow> AllScriptsRows { get; }

    /// <summary>
    /// The read-only troubleshooting rows: interpreter versions, the WIN+CTRL+N
    /// check, and per-script diagnostics.
    ///
    /// Kept in their own collection rather than folded into
    /// <see cref="AllScriptsRows"/>: one group changes state and the other only
    /// reads it, and mixing them would put "Check AHK 2" next to "Enable All"
    /// where the difference is invisible.
    /// </summary>
    public ObservableCollection<VerbRow> DiagnosticRows { get; }

    /// <summary>Guidance under the Apply button, and the pending-change count.</summary>
    [ObservableProperty] private string _applyHint = string.Empty;

    public AutoHotkeyViewModel(ScriptService scripts)
        : base(scripts, VerbRegistry.Tabs.AutoHotkey)
    {
        _scriptsDirectory = scripts.ScriptsDirectory;

        var state = AhkScriptCatalog.ReadState(_scriptsDirectory);
        ScriptRows = new ObservableCollection<AhkScriptRow>(
            AhkScriptCatalog.Scripts.Select(info =>
                new AhkScriptRow(info, state.TryGetValue(info.Key, out var on) ? on : true)));

        // Only the two "all" verbs get a row: ahk-enable / ahk-disable are
        // per-script and are driven by the rows below, so showing them as generic
        // rows would ask the user to type a script key instead of choosing one.
        var wanted = new HashSet<string>(new[] { "ahk-enable-all", "ahk-disable-all" },
            StringComparer.OrdinalIgnoreCase);
        AllScriptsRows = new ObservableCollection<VerbRow>(Rows.Where(r => wanted.Contains(r.Verb)));

        // The diagnostic rows come from the same registry, so a new check appears
        // here by being added there and nowhere else.
        var diagnostics = new HashSet<string>(
            new[] { "ahk-versions", "ahk-newfile-check", "ahk-diagnose" },
            StringComparer.OrdinalIgnoreCase);
        DiagnosticRows = new ObservableCollection<VerbRow>(
            Rows.Where(r => diagnostics.Contains(r.Verb)));

        foreach (var row in ScriptRows) row.PropertyChanged += (_, _) => UpdateApplyHint();
        UpdateApplyHint();
    }

    private void UpdateApplyHint()
    {
        var changed = ScriptRows.Count(s => s.IsDirty);

        ApplyHint = changed == 0
            ? "Every script already matches its stored state. No changes to write."
            : $"{changed} script{(changed == 1 ? "" : "s")} changed. Apply runs the per-script script for each one, then stores the result.";
    }

    /// <summary>
    /// Commit every changed script, then persist the resulting state.
    ///
    /// Serial, not parallel: each <c>ahk-script.ps1</c> rewrites the same
    /// generated AppRunner.vbs, so running them concurrently would let two writers
    /// interleave and leave the file describing a state neither of them intended.
    /// The loop also stops at the first failure, because a state file written after
    /// a failed call would claim a change that did not happen.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanApply))]
    private async Task ApplyAsync()
    {
        var pending = ScriptRows.Where(s => s.IsDirty).ToList();
        if (pending.Count == 0)
        {
            Status = "Nothing to apply — every script already matches its stored state.";
            return;
        }

        ConsoleBegin($"[ahk] applying {pending.Count} script change{(pending.Count == 1 ? "" : "s")}");

        foreach (var row in pending)
        {
            var verb = row.IsEnabled ? "ahk-enable" : "ahk-disable";
            var state = row.IsEnabled ? "enabled" : "disabled";

            ConsoleWriteLine($"$ ahk-script.ps1 -Name {row.Key} -State {state}");

            // The argument ORDER must be -Name first: the script's param block
            // declares -State with a ValidateSet, and PowerShell binds positionally
            // in declaration order, so a bare value would land on -Name.
            var result = await Scripts.RunAsync(
                verb,
                new[] { row.Key },
                ConsoleWriteLine,
                CancellationToken.None);

            ConsoleWriteLine($"[{row.Label}] {result.Summary}");

            if (!result.Succeeded)
            {
                row.Revert();
                FlushConsole();
                Status = $"{row.Label} could not be set to {state}. No further changes were applied.";
                UpdateApplyHint();
                return;
            }

            row.MarkApplied();
        }

        PersistStates();
        FlushConsole();
        Status = $"Applied {pending.Count} script change{(pending.Count == 1 ? "" : "s")}.";
        UpdateApplyHint();
    }

    private bool CanApply() => !IsBusy;

    /// <summary>
    /// Store the applied states in the Dashboard's own settings file, so the tab
    /// opens showing what the scripts have even before ahk-state.json is read.
    /// </summary>
    private void PersistStates()
    {
        var states = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        foreach (var row in ScriptRows) states[row.Key] = row.AppliedEnabled;

        SettingsStore.Current.AhkScriptStates = states;
        SettingsStore.Save();
    }

    /// <summary>
    /// Re-read the on-disk state after the generic "all scripts" rows have run, so
    /// the radio pairs do not keep showing a state the scripts have already left.
    /// </summary>
    protected override void OnVerbCompleted(string verb)
    {
        if (!verb.StartsWith("ahk-", StringComparison.OrdinalIgnoreCase)) return;

        var state = AhkScriptCatalog.ReadState(_scriptsDirectory);

        foreach (var row in ScriptRows)
        {
            var applied = state.TryGetValue(row.Key, out var on) ? on : true;
            row.AppliedEnabled = applied;
            row.IsEnabled = applied;
        }

        PersistStates();
        UpdateApplyHint();
    }
}