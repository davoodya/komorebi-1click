using System.Windows.Controls;
using KomorebiDashboard.ViewModels;

namespace KomorebiDashboard.Views;

/// <summary>
/// Code-behind for UninstallView. Assigning the ViewModel is the entire permitted
/// responsibility of a View's code-behind (ADR-0009); no logic lives here.
/// </summary>
public partial class UninstallView : UserControl
{
    public UninstallView() => InitializeComponent();

    public UninstallView(UninstallViewModel viewModel) : this()
    {
        DataContext = viewModel;
    }
}
