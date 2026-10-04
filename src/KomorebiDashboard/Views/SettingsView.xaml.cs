using System.Windows.Controls;
using KomorebiDashboard.ViewModels;

namespace KomorebiDashboard.Views;

/// <summary>
/// Code-behind for SettingsView. Assigning the ViewModel is the entire permitted
/// responsibility of a View's code-behind (ADR-0009); no logic lives here.
/// </summary>
public partial class SettingsView : UserControl
{
    public SettingsView() => InitializeComponent();

    public SettingsView(SettingsViewModel viewModel) : this()
    {
        DataContext = viewModel;
    }
}
