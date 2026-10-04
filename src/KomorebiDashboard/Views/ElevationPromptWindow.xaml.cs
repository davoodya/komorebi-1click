using System.Windows;
using KomorebiDashboard.Services;

namespace KomorebiDashboard.Views;

/// <summary>
/// The "Rerun as Administrator" dialog (ADR-0012, Davood's Round-2 answer).
///
/// WHY A CUSTOM WINDOW AND NOT MessageBox
///   ADR-0012 requires exactly three buttons: OK, Rerun as Administrator,
///   Cancel. WPF's <see cref="MessageBox"/> offers at most OK/Cancel (and
///   Yes/No/Cancel, whose labels cannot be changed). The middle button has to
///   read "Rerun as Administrator", so a dedicated window is the only option
///   that satisfies the requirement literally.
///
/// The dialog is shown with ShowDialog() so the caller gets a definite answer:
/// it returns only once the user has actually chosen. There is no timeout and
/// no default action, because either would mean acting on the user's behalf
/// without their consent — and elevation is exactly the decision that must
/// never be taken for someone.
/// </summary>
public partial class ElevationPromptWindow : Window
{
    private ElevationPromptWindow(string message)
    {
        InitializeComponent();
        MessageText.Text = message;
    }

    /// <summary>The buttons, in ADR-0012's order.</summary>
    public enum Choice
    {
        /// <summary>Dismissed without elevating.</summary>
        Cancelled,

        /// <summary>Elevate now.</summary>
        RerunAsAdministrator,
    }

    /// <summary>The user's decision.</summary>
    public Choice Result { get; private set; } = Choice.Cancelled;

    private void OnRerun(object sender, RoutedEventArgs e)
    {
        Result = Choice.RerunAsAdministrator;
        DialogResult = true;
    }

    private void OnDismiss(object sender, RoutedEventArgs e)
    {
        Result = Choice.Cancelled;
        DialogResult = false;
    }

    /// <summary>
    /// Show the dialog over <paramref name="owner"/> and return true when the
    /// user chose to elevate.
    /// </summary>
    public static bool Ask(Window? owner, string message)
    {
        var dialog = new ElevationPromptWindow(message)
        {
            Owner = owner,
            WindowStartupLocation = owner is null
                ? WindowStartupLocation.CenterScreen
                : WindowStartupLocation.CenterOwner,
        };

        return dialog.ShowDialog() == true && dialog.Result == Choice.RerunAsAdministrator;
    }
}

/// <summary>
/// The single entry point the ViewModel calls, so the UI concern (showing a
/// window) stays out of the ViewModel and out of <see cref="ElevationService"/>
/// (which stays testable without a desktop).
///
/// On Rerun as Administrator it relaunches the app elevated and then shuts the
/// current instance down, because ADR-0012 requires the unelevated instance to
/// exit — otherwise two instances race over the same scheduled tasks.
/// </summary>
public static class ElevationPrompt
{
    /// <summary>
    /// Prompt, and if the user agrees, relaunch elevated and exit.
    ///
    /// Returns true when the operation may now proceed, which only happens when
    /// the user DECLINED to elevate but is already able to — a state this
    /// method never produces, so in practice a true return means "stop here".
    /// The return value exists so the caller's control flow is explicit rather
    /// than relying on the process vanishing underneath it.
    /// </summary>
    public static bool TryPrompt(string message)
    {
        var owner = Application.Current?.MainWindow;
        var wantsElevation = ElevationPromptWindow.Ask(owner, message);

        if (!wantsElevation) return false;

        if (ElevationService.RelaunchElevated())
        {
            // Exit AFTER the elevated instance has been spawned. Doing it in the
            // other order would leave the user with neither window.
            Application.Current?.Shutdown();
            return false;
        }

        // The relaunch did not happen (declined UAC, or the launch failed).
        // Say so rather than continuing unelevated into an operation that
        // cannot succeed.
        return false;
    }
}