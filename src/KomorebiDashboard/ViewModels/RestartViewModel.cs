using KomorebiDashboard.Services;

namespace KomorebiDashboard.ViewModels;

/// <summary>
/// Restart and Reloading tab. The button list is generated from
/// <see cref="VerbRegistry"/>, so every ADR-0013 mechanism that belongs to this
/// tab has a button without any wiring here.
/// </summary>
public sealed partial class RestartViewModel : TabViewModelBase
{
    public RestartViewModel(ScriptService scripts) : base(scripts, VerbRegistry.Tabs.Restart) { }

    /// <summary>One-line description shown at the top of the tab.</summary>
    public string Description => "Restart components to apply a configuration change.";
}
