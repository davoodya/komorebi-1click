using KomorebiDashboard.Services;

namespace KomorebiDashboard.ViewModels;

/// <summary>
/// Kill and Start tab. The button list is generated from
/// <see cref="VerbRegistry"/>, so every ADR-0013 mechanism that belongs to this
/// tab has a button without any wiring here.
/// </summary>
public sealed partial class KillStartViewModel : TabViewModelBase
{
    public KillStartViewModel(ScriptService scripts) : base(scripts, VerbRegistry.Tabs.KillStart) { }

    /// <summary>One-line description shown at the top of the tab.</summary>
    public string Description => "Stop and start the whole stack, or any single component.";
}
