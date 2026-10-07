using System.Collections.ObjectModel;
using System.Diagnostics;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using KomorebiDashboard.Models;
using KomorebiDashboard.Services;

namespace KomorebiDashboard.ViewModels;

/// <summary>
/// Settings tab: startup tasks, configuration export/import, transparency, and
/// the Dashboard's own preferences.
///
/// The rows are sliced out of the single registry rather than listed here, so a
/// verb added to the registry appears in this tab with no change to this file —
/// which is the whole point of the registry (ADR-0013).
/// </summary>
public sealed partial class SettingsViewModel : TabViewModelBase
{
    /// <summary>Startup task rows: add and remove, each with its own row.</summary>
    public ObservableCollection<VerbRow> StartupRows { get; }

    /// <summary>Config export/import rows.</summary>
    public ObservableCollection<VerbRow> ConfigRows { get; }

    /// <summary>Appearance rows (window transparency).</summary>
    public ObservableCollection<VerbRow> AppearanceRows { get; }

    /// <summary>
    /// The single "Ignore KomorebiDashboard" row, handed to a hand-written row in
    /// SettingsView.xaml (its explanation is too long for the generic template's
    /// one-line help, and the row needs a full-width paragraph).
    ///
    /// It is taken from the registry rather than described in the XAML, so the
    /// command, the script and the help text all have exactly one definition —
    /// the property the view binds to is the same object the generic rows use.
    /// </summary>
    public VerbRow? IgnoreDashboardRow { get; }

    /// <summary>
    /// Where settings.json lives, shown so it can be found by hand.
    /// </summary>
    public string SettingsPath => SettingsStore.FilePath;

    public SettingsViewModel(ScriptService scripts) : base(scripts, VerbRegistry.Tabs.Settings)
    {
        StartupRows = Slice("startup-install", "startup-remove");
        ConfigRows = Slice("export", "import");
        AppearanceRows = Slice("set-transparency");

        // FirstOrDefault, not Single: a duplicated registry entry must not throw
        // during window construction and take the whole UI down with it.
        IgnoreDashboardRow = Rows.FirstOrDefault(
            r => string.Equals(r.Verb, "ignore-dashboard", StringComparison.OrdinalIgnoreCase));
    }

    private ObservableCollection<VerbRow> Slice(params string[] verbs)
    {
        var wanted = new HashSet<string>(verbs, StringComparer.OrdinalIgnoreCase);
        return new ObservableCollection<VerbRow>(Rows.Where(r => wanted.Contains(r.Verb)));
    }

    /// <summary>
    /// Restore every Dashboard preference to its default, after confirmation.
    ///
    /// This is the Dashboard's own reset, not the machine's: it deliberately does
    /// not call Delete() on the settings file (the state is written explicitly so
    /// the next launch is deterministic) and it never touches the scheduled tasks
    /// or any component's configuration — those have their own rows above.
    /// </summary>
    [RelayCommand]
    private void FactoryReset()
    {
        var current = System.Windows.Application.Current?.MainWindow;
        var message =
            "Restore every Dashboard preference to its default value?\n\n" +
            "This affects the Dashboard's own appearance and stored preferences only. " +
            "It does not touch komorebi, whkd, YASB, AutoHotkey, their configuration " +
            "files, or any scheduled task.";

        if (!Views.ConfirmDialog.Ask(current, "Factory Reset", message, "Reset")) return;

        SettingsStore.ResetToDefaults();
        ThemeService.ApplyDefault();
        ThemeService.ApplyTypography(
            DashboardSettings.DefaultFontFamily,
            DashboardSettings.DefaultFontSize);
        ThemeService.ApplyConsoleTypography(
            DashboardSettings.DefaultConsoleFontFamily,
            DashboardSettings.DefaultConsoleFontSize);
        ThemeService.ApplyUiScale(DashboardSettings.DefaultUiScale);

        // Reflect the restored defaults in the controls this tab owns.
        OnPropertyChanged(nameof(SettingsPath));

        Status = "Factory reset complete. Every Dashboard preference is back at its default.";
        ConsoleBegin("[settings] factory reset applied");
        ConsoleWriteLine("  theme, accent, typeface, size, console font and console height restored to defaults");
        ConsoleWriteLine($"  settings file: {SettingsStore.FilePath}");
        FlushConsole();
    }

    /// <summary>
    /// Open the folder holding settings.json in Explorer.
    ///
    /// The folder, not the file: opening a .json hands it to whatever the user has
    /// associated with JSON, which may be an editor, a browser, or nothing.
    /// </summary>
    [RelayCommand]
    private void OpenSettingsFolder()
    {
        try
        {
            System.IO.Directory.CreateDirectory(SettingsStore.DirectoryPath);
            Process.Start(new ProcessStartInfo
            {
                FileName = SettingsStore.DirectoryPath,
                UseShellExecute = true,
            })?.Dispose();

            Status = $"Opened {SettingsStore.DirectoryPath}";
        }
        catch (Exception ex)
        {
            // Reported in the UI rather than thrown: a failed Explorer launch is
            // cosmetic, and an exception here would take the tab down with it.
            Status = $"Could not open the settings folder: {ex.Message}";
        }
    }
}