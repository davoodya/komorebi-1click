using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using KomorebiDashboard.Services;
using KomorebiDashboard.Views;

namespace KomorebiDashboard;

/// <summary>
/// The application shell: every tab is hosted here at once, and the two
/// app-wide actions (theme, factory reset) live in the header.
///
/// WHY EVERY TAB IS CONSTRUCTED EAGERLY
///   Each tab's ViewModel resolves its verb list from the registry and its
///   console row height from persisted settings — all of that is a handful of
///   allocations, and doing it here (before the window is shown) is why switching
///   tabs costs nothing measurable later. The scripts themselves are never run
///   until a button is pressed, so eagerness costs no I/O.
/// </summary>
public partial class MainWindow : Window
{
    private readonly ScriptService _scripts;

    public MainWindow()
    {
        InitializeComponent();

        _scripts = new ScriptService(ScriptsLocator.Resolve());
        VersionText.Text = BuildVersionText();

        AttachTabViewModels();

        // Rounded corners on Windows 11, without accepting a DWM backdrop. The
        // two are independent: this asks the compositor to round the frame, while
        // WindowBackdropType stays None (see MainWindow.xaml).
        SourceInitialized += (_, _) => ApplyWindowCornerPreference();
    }

    /// <summary>
    /// Build each tab's ViewModel from the single shared
    /// <see cref="ScriptService"/>, so every tab and the CLI twin dispatch
    /// through the same code path.
    /// </summary>
    private void AttachTabViewModels()
    {
        KillStartView.DataContext = new ViewModels.KillStartViewModel(_scripts);
        RestartView.DataContext = new ViewModels.RestartViewModel(_scripts);
        SettingsView.DataContext = new ViewModels.SettingsViewModel(_scripts);
        CustomizationView.DataContext = new ViewModels.CustomizationViewModel(_scripts);
        AutoHotkeyView.DataContext = new ViewModels.AutoHotkeyViewModel(_scripts);
        DebuggingView.DataContext = new ViewModels.DebuggingViewModel(_scripts);
        UninstallView.DataContext = new ViewModels.UninstallViewModel(_scripts);
        AboutView.DataContext = new ViewModels.AboutViewModel();
    }

    private static string BuildVersionText()
    {
        // Informational version first: it is the one the csproj can set to a
        // product version (e.g. 1.0.0+abc123). Falls back to the assembly version
        // so a plain build still shows something truthful.
        var assembly = typeof(MainWindow).Assembly;

        var informational = assembly
            .GetCustomAttributes(typeof(System.Reflection.AssemblyInformationalVersionAttribute), false)
            .OfType<System.Reflection.AssemblyInformationalVersionAttribute>()
            .FirstOrDefault()?.InformationalVersion;

        var version = string.IsNullOrWhiteSpace(informational)
            ? assembly.GetName().Version?.ToString(3) ?? "dev"
            : informational;

        return $"Komorebi · WHKD · YASB · AutoHotkey      v{version}";
    }

    // ---------------------------------------------------------------------
    // App-wide actions
    // ---------------------------------------------------------------------

    private void OnToggleTheme(object sender, RoutedEventArgs e)
    {
        ThemeService.Toggle();
        PersistAppearance();
    }

    /// <summary>
    /// Step to the next accent color from the window chrome.
    ///
    /// Persisted immediately, exactly like the theme toggle: both are one-click
    /// changes with no preview step, and a header button that forgets its effect
    /// on the next launch would be a bug the user cannot explain.
    /// </summary>
    private void OnToggleColor(object sender, RoutedEventArgs e)
    {
        var scheme = ThemeService.CycleAccent();

        // Reported to the console so the current color is discoverable without
        // opening Customization — the button itself only shows the change.
        ConsoleWrite($"accent color: {scheme}");
        PersistAppearance();
    }

    /// <summary>
    /// Read the live theme and accent back into settings and save.
    ///
    /// Read from <see cref="ThemeService"/> rather than from the click's
    /// arguments: ThemeService is the single owner of both values, so this cannot
    /// persist something different from what is on screen.
    /// </summary>
    private void PersistAppearance()
    {
        var settings = SettingsStore.Current;

        settings.Theme = ThemeService.CurrentTheme == Wpf.Ui.Appearance.ApplicationTheme.Dark
            ? "Dark"
            : "Light";
        settings.ColorScheme = ThemeService.CurrentScheme;

        // The hex is only meaningful for a custom accent, and storing it always
        // means switching back to a palette later leaves a stale value behind that
        // a future reader could mistake for the current color.
        settings.AccentColor = ThemeService.IsCustomAccent ? ThemeService.CurrentAccentHex : string.Empty;

        SettingsStore.Save();
    }

    /// <summary>
    /// Write one line to the active tab's console.
    ///
    /// The header acts on the whole app, but the console is per tab, so the
    /// message goes to whichever tab is on screen rather than to all of them.
    /// </summary>
    private void ConsoleWrite(string message)
    {
        if (Tabs.SelectedItem is not TabItem { Content: FrameworkElement view }) return;
        if (view.DataContext is not ViewModels.TabViewModelBase vm) return;
        vm.WriteLine(message);
    }

    // ---------------------------------------------------------------------
    // Window chrome
    // ---------------------------------------------------------------------

    private enum DwmWindowCornerPreference
    {
        Default = 0,
        DoNotRound = 1,
        Round = 2,
        RoundSmall = 3,
    }

    [DllImport("dwmapi.dll", PreserveSig = true)]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    /// <summary>
    /// Ask DWM for rounded corners. Windows 10 and older do not implement the
    /// attribute and return a failure code, which is why the result is ignored
    /// rather than treated as an error.
    /// </summary>
    private void ApplyWindowCornerPreference()
    {
        try
        {
            var handle = new WindowInteropHelper(this).Handle;
            if (handle == IntPtr.Zero) return;

            const int DwmwaWindowCornerPreference = 33;
            var preference = (int)DwmWindowCornerPreference.Round;
            DwmSetWindowAttribute(handle, DwmwaWindowCornerPreference, ref preference, sizeof(int));
        }
        catch
        {
            // Non-fatal by design: the window is fully usable with square corners.
        }
    }
}