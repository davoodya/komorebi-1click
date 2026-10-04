using System.Windows.Controls;
using KomorebiDashboard.ViewModels;

namespace KomorebiDashboard.Views;

/// <summary>
/// Code-behind for AutoHotkeyView. Assigning the ViewModel is the entire permitted
/// responsibility of a View's code-behind (ADR-0009); no logic lives here.
/// </summary>
public partial class AutoHotkeyView : UserControl
{
    public AutoHotkeyView() => InitializeComponent();

    public AutoHotkeyView(AutoHotkeyViewModel viewModel) : this()
    {
        DataContext = viewModel;
    }
}
