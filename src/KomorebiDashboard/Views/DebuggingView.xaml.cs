using System.Windows.Controls;
using KomorebiDashboard.ViewModels;

namespace KomorebiDashboard.Views;

/// <summary>
/// Code-behind for DebuggingView. Assigning the ViewModel is the entire permitted
/// responsibility of a View's code-behind (ADR-0009); no logic lives here.
/// </summary>
public partial class DebuggingView : UserControl
{
    public DebuggingView() => InitializeComponent();

    public DebuggingView(DebuggingViewModel viewModel) : this()
    {
        DataContext = viewModel;
    }
}
