using KomorebiDashboard.Services;

namespace KomorebiDashboard.ViewModels;

/// <summary>
/// Settings tab. The button list is generated from
/// <see cref="VerbRegistry"/>, so every ADR-0013 mechanism that belongs to this
/// tab has a button without any wiring here.
/// </summary>
public sealed partial class SettingsViewModel : TabViewModelBase
{
    public SettingsViewModel(ScriptService scripts) : base(scripts, VerbRegistry.Tabs.Settings) { }

    /// <summary>One-line description shown at the top of the tab.</summary>
    public string Description => "Startup tasks and configuration export/import.";
}
