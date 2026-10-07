using System.Windows;

namespace KomorebiDashboard.Views;

/// <summary>
/// Themed confirmation dialog for irreversible actions.
///
/// WHY NOT MessageBox
///   <see cref="MessageBox"/> is Win32 chrome: it ignores the Fluent theme, so in
///   Dark mode it renders as a light panel in the middle of a dark app. Every
///   destructive action in this Dashboard (factory reset, uninstall, cleanup)
///   asks first, so that panel would be a routine sight rather than an edge case.
///
/// The dialog never decides anything by itself: <see cref="Ask"/> returns the
/// user's answer and the caller acts on it. No default action and no timeout,
/// because both would mean acting on the user's behalf.
/// </summary>
public partial class ConfirmDialog : Window
{
    private bool _confirmed;

    private ConfirmDialog(string heading, string message, string confirmLabel)
    {
        InitializeComponent();
        HeadingText.Text = heading;
        MessageText.Text = message;
        ConfirmButton.Content = confirmLabel;
        Title = heading;
    }

    /// <summary>
    /// Ask a yes/no question over <paramref name="owner"/>. Returns true only when
    /// the user chose the confirming button.
    /// </summary>
    /// <param name="owner">Window to centre on; the modal owner.</param>
    /// <param name="heading">Short question, also used as the window title.</param>
    /// <param name="message">What will happen, and what will not.</param>
    /// <param name="confirmLabel">
    /// The verb for the confirming button. A specific label ("Reset", "Uninstall")
    /// is harder to click by reflex than "OK", which is the point.
    /// </param>
    public static bool Ask(Window? owner, string heading, string message, string confirmLabel = "Confirm")
    {
        var dialog = new ConfirmDialog(heading, message, confirmLabel)
        {
            Owner = owner,
            WindowStartupLocation = owner is null
                ? WindowStartupLocation.CenterScreen
                : WindowStartupLocation.CenterOwner,
        };

        dialog.ShowDialog();
        return dialog._confirmed;
    }

    private void OnConfirm(object sender, RoutedEventArgs e)
    {
        _confirmed = true;
        DialogResult = true;
    }

    private void OnCancel(object sender, RoutedEventArgs e)
    {
        _confirmed = false;
        DialogResult = false;
    }
}