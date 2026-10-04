using KomorebiDashboard.Services;

namespace KomorebiDashboard.ViewModels;

/// <summary>
/// Uninstall and Cleanup tab. The button list is generated from
/// <see cref="VerbRegistry"/>, so every ADR-0013 mechanism that belongs to this
/// tab has a button without any wiring here.
/// </summary>
public sealed partial class UninstallViewModel : TabViewModelBase
{
    public UninstallViewModel(ScriptService scripts) : base(scripts, VerbRegistry.Tabs.Uninstall) { }

    /// <summary>One-line description shown at the top of the tab.</summary>
    public string Description => "Remove the software and wipe what it left behind.";
}
