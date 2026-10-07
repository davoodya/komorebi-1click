using System.Windows.Controls;

namespace KomorebiDashboard.Views;

/// <summary>
/// The About tab's view. Code-behind is empty on purpose: every value it shows is
/// a plain property on <see cref="ViewModels.AboutViewModel"/> and every action is
/// a command, so there is nothing for this class to do.
/// </summary>
public partial class AboutView : UserControl
{
    public AboutView()
    {
        InitializeComponent();
    }
}