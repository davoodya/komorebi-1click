using System.Windows.Controls;
using KomorebiDashboard.ViewModels;

namespace KomorebiDashboard.Views;

/// <summary>
/// Code-behind for KillStartView. Assigning the ViewModel is the entire permitted
/// responsibility of a View's code-behind (ADR-0009); no logic lives here.
/// </summary>
public partial class KillStartView : UserControl
{
    public KillStartView() => InitializeComponent();

    public KillStartView(KillStartViewModel viewModel) : this()
    {
        DataContext = viewModel;
    }
}
