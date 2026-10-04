using KomorebiDashboard.Services;

namespace KomorebiDashboard.ViewModels;

/// <summary>
/// AutoHotkey Scripts tab. The button list is generated from
/// <see cref="VerbRegistry"/>, so every ADR-0013 mechanism that belongs to this
/// tab has a button without any wiring here.
/// </summary>
public sealed partial class AutoHotkeyViewModel : TabViewModelBase
{
    public AutoHotkeyViewModel(ScriptService scripts) : base(scripts, VerbRegistry.Tabs.AutoHotkey) { }

    /// <summary>One-line description shown at the top of the tab.</summary>
    public string Description => "Enable, disable and inspect the AutoHotkey scripts.";
}
