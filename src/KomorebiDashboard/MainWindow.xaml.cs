using System.IO;
using System.Windows;
using KomorebiDashboard.Services;
using KomorebiDashboard.ViewModels;
using KomorebiDashboard.Views;

namespace KomorebiDashboard;

public partial class MainWindow : Window
{
    /// <summary>
    /// The one place the six ViewModels are constructed. Everything downstream —
    /// which buttons exist, what they run, what help says — comes from the
    /// registry, so this file wires services to tabs and adds no per-verb
    /// knowledge of its own (ADR-0009).
    /// </summary>
    public MainWindow()
    {
        InitializeComponent();

        // The scripts live in <repo>\scripts during development and beside the
        // executable in a shipped install. Probe both so the app works from
        // either layout instead of assuming one.
        var service = new ScriptService(ScriptsLocator.Resolve());

        Attach(nameof(KillStartView),  new KillStartViewModel(service));
        Attach(nameof(RestartView),    new RestartViewModel(service));
        Attach(nameof(SettingsView),   new SettingsViewModel(service));
        Attach(nameof(AutoHotkeyView), new AutoHotkeyViewModel(service));
        Attach(nameof(DebuggingView),  new DebuggingViewModel(service));
        Attach(nameof(UninstallView),  new UninstallViewModel(service));
    }

    /// <summary>
    /// Attach a ViewModel to its named View.
    ///
    /// FindName returns null for any element without an x:Name, and the
    /// null-forgiving operator would turn that into a NullReferenceException
    /// thrown from the constructor — which is exactly how defect D18 killed the
    /// app on startup. Failing loudly with a message naming the missing x:Name
    /// turns an opaque crash into an actionable one, so a View renamed without
    /// its name updated says so instead of dying silently.
    /// </summary>
    /// <param name="name">The View's x:Name, which is what FindName resolves.</param>
    /// <param name="viewModel">The ViewModel to attach to that View.</param>
    private void Attach(string name, object viewModel)
    {
        if (FindName(name) is not FrameworkElement view)
        {
            throw new InvalidOperationException(
                $"View '{name}' was not found. MainWindow.xaml must declare " +
                $"x:Name=\"{name}\" on that element, or FindName cannot resolve it.");
        }

        view.DataContext = viewModel;
    }

    /// <summary>
    /// Switch between the Dark and Light Fluent themes (ticket 12).
    ///
    /// The switch goes through <see cref="ThemeService"/>, which applies it
    /// immediately to the live window — there is no restart and no flicker,
    /// because the theme resources are merged at Application scope.
    /// </summary>
    private void OnToggleTheme(object sender, RoutedEventArgs e)
    {
        var applied = ThemeService.Toggle();

        // The label reports what is now in force, so the user never has to
        // guess which way a toggle went.
        if (ThemeToggle is { } button)
        {
            button.Content = applied == Wpf.Ui.Appearance.ApplicationTheme.Dark
                ? "Light theme"
                : "Dark theme";
            button.ToolTip = $"Switch to the {(applied == Wpf.Ui.Appearance.ApplicationTheme.Dark ? "Light" : "Dark")} Fluent theme";
        }
    }
}
