using KomorebiDashboard.Services;

namespace KomorebiDashboard.ViewModels;

/// <summary>
/// Debugging tab. The button list is generated from
/// <see cref="VerbRegistry"/>, so every ADR-0013 mechanism that belongs to this
/// tab has a button without any wiring here.
/// </summary>
public sealed partial class DebuggingViewModel : TabViewModelBase
{
    public DebuggingViewModel(ScriptService scripts) : base(scripts, VerbRegistry.Tabs.Debugging) { }

    /// <summary>One-line description shown at the top of the tab.</summary>
    public string Description => "Read-only diagnostics and configuration repair.";
}
