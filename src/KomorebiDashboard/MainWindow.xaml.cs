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
        var service = new ScriptService(ResolveScriptsDirectory());

        ((KillStartView)  FindName(nameof(KillStartView))!).DataContext  = new KillStartViewModel(service);
        ((RestartView)    FindName(nameof(RestartView))!).DataContext    = new RestartViewModel(service);
        ((SettingsView)   FindName(nameof(SettingsView))!).DataContext   = new SettingsViewModel(service);
        ((AutoHotkeyView) FindName(nameof(AutoHotkeyView))!).DataContext = new AutoHotkeyViewModel(service);
        ((DebuggingView)  FindName(nameof(DebuggingView))!).DataContext  = new DebuggingViewModel(service);
        ((UninstallView)  FindName(nameof(UninstallView))!).DataContext  = new UninstallViewModel(service);
    }

    private static string ResolveScriptsDirectory()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "scripts"),
            Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "scripts"),
            Path.Combine(AppContext.BaseDirectory, "..", "scripts"),
        };

        foreach (var candidate in candidates)
        {
            var full = Path.GetFullPath(candidate);
            if (Directory.Exists(full) && File.Exists(Path.Combine(full, "kill-all.ps1")))
            {
                return full;
            }
        }

        // Nothing found. ScriptService reports a missing script per verb with a
        // clear message rather than the app refusing to start, so a misplaced
        // install stays diagnosable from the UI itself.
        return Path.Combine(AppContext.BaseDirectory, "scripts");
    }
}