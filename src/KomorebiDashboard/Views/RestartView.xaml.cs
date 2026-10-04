using System.Windows.Controls;
using KomorebiDashboard.ViewModels;

namespace KomorebiDashboard.Views;

/// <summary>
/// Code-behind for RestartView. Assigning the ViewModel is the entire permitted
/// responsibility of a View's code-behind (ADR-0009); no logic lives here.
/// </summary>
public partial class RestartView : UserControl
{
    public RestartView() => InitializeComponent();

    public RestartView(RestartViewModel viewModel) : this()
    {
        DataContext = viewModel;
    }
}
