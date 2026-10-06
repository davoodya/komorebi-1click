using System.Windows;
using System.Windows.Media;
using Wpf.Ui.Appearance;
using Wpf.Ui.Controls;
using Wpf.Ui.Markup;

namespace KomorebiDashboard.Services;

/// <summary>
/// Runtime Dark/Light theming via WPF-UI's Fluent styling (ticket 12, ADR-0015
/// priority 4: "modern, beautiful UI", which is only ever bought without
/// giving up priorities 1-3).
///
/// SESSION 2026-10-06 FIX — D21:
///   The original implementation called ApplicationThemeManager.Apply() which
///   swaps resource dictionaries but does NOT repaint the DWM backdrop on an
///   already-open window. That is why only the title bar changed colour while
///   the body stayed white.
///
///   The fix has two parts:
///   1. MainWindow MUST derive from FluentWindow (not Window) so the DWM
///      backdrop material is active in the first place.
///   2. After every theme/accent change, we iterate all open windows and call
///      WindowBackgroundManager.UpdateBackground() to force the DWM attribute
///      to repaint on the live surface.
///
/// COLOUR SCHEMES:
///   8 accent presets are exposed through SetColorScheme(). Each one calls
///   ApplicationAccentColorManager.Apply(Color) which re-derives the full
///   palette (hover, pressed, disabled) from the seed colour.
/// </summary>
public static class ThemeService
{
    private const WindowBackdropType FluentBackdrop = WindowBackdropType.Mica;

    public static ApplicationTheme CurrentTheme { get; private set; } = ApplicationTheme.Unknown;

    private static readonly Dictionary<ApplicationTheme, ThemesDictionary> Cache = new();

    // --- Colour scheme presets ---
    public static readonly Dictionary<string, Color> ColorSchemes = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Blue"]    = Color.FromRgb(0x00, 0x78, 0xD4),
        ["Indigo"]  = Color.FromRgb(0x4F, 0x46, 0xE5),
        ["Violet"]  = Color.FromRgb(0x7C, 0x3A, 0xED),
        ["Rose"]    = Color.FromRgb(0xE1, 0x1D, 0x48),
        ["Amber"]   = Color.FromRgb(0xF5, 0x9E, 0x0B),
        ["Emerald"] = Color.FromRgb(0x10, 0xB9, 0x81),
        ["Teal"]    = Color.FromRgb(0x0D, 0x94, 0x88),
        ["Slate"]   = Color.FromRgb(0x64, 0x74, 0x8B),
    };

    private static string _currentScheme = "Blue";
    public static string CurrentScheme => _currentScheme;

    public static ApplicationTheme Opposite =>
        CurrentTheme == ApplicationTheme.Dark ? ApplicationTheme.Light : ApplicationTheme.Dark;

    /// <summary>
    /// Apply the startup theme BEFORE the main window is shown.
    /// </summary>
    public static void ApplyDefault()
    {
        var theme = ApplicationThemeManager.GetSystemTheme() == SystemTheme.Dark
            ? ApplicationTheme.Dark
            : ApplicationTheme.Light;

        Apply(theme);
        ApplyAccent(ColorSchemes[_currentScheme]);
        Report($"startup theme: {theme}, scheme: {_currentScheme}");
    }

    /// <summary>
    /// Apply a theme immediately. Redundant calls are skipped.
    /// </summary>
    public static void Apply(ApplicationTheme theme)
    {
        if (theme == ApplicationTheme.Unknown) theme = ApplicationTheme.Light;
        if (CurrentTheme == theme && Application.Current is not null) return;

        Ensure(theme);

        // Use the 3-parameter overload verified to exist in WPF-UI 4.3.0.
        // This applies the theme AND sets the backdrop type for new windows.
        ApplicationThemeManager.Apply(theme, FluentBackdrop, updateAccent: true);
        CurrentTheme = theme;

        // D21 fix: force already-open windows to repaint their DWM backdrop.
        RepaintAllWindows();
    }

    /// <summary>
    /// Toggle between Dark and Light. Returns the theme now in force.
    /// </summary>
    public static ApplicationTheme Toggle()
    {
        Apply(Opposite);
        Report($"theme toggled to: {CurrentTheme}");
        return CurrentTheme;
    }

    /// <summary>Explicit theme setter for Customization tab.</summary>
    public static void SetTheme(ApplicationTheme theme) => Apply(theme);

    /// <summary>
    /// Changes the accent colour scheme at runtime.
    /// </summary>
    public static void SetColorScheme(string name)
    {
        if (!ColorSchemes.TryGetValue(name, out var color)) return;
        _currentScheme = name;
        ApplyAccent(color);
    }

    /// <summary>
    /// Changes the backdrop type on all open FluentWindows at runtime.
    /// </summary>
    public static void SetBackdrop(WindowBackdropType type)
    {
        var app = Application.Current;
        if (app?.Windows == null) return;

        foreach (Window w in app.Windows)
        {
            if (w is FluentWindow fw)
            {
                fw.WindowBackdropType = type;
                try { WindowBackgroundManager.UpdateBackground(fw, CurrentTheme, type); }
                catch { /* non-fatal: API may differ across minor versions */ }
            }
        }
    }

    // ---- internals ----

    private static void ApplyAccent(Color color)
    {
        ApplicationAccentColorManager.Apply(color);
        RepaintAllWindows();
    }

    private static void Ensure(ApplicationTheme theme)
    {
        if (Cache.ContainsKey(theme)) return;
        Cache[theme] = new ThemesDictionary { Theme = theme };
    }

    /// <summary>
    /// D21 fix: after any theme or accent change, iterate all open windows
    /// and force the background brush to re-resolve from the updated resource
    /// dictionary. For FluentWindows, also update the DWM backdrop.
    /// </summary>
    private static void RepaintAllWindows()
    {
        var app = Application.Current;
        if (app?.Windows == null) return;

        Window[] snapshot;
        try { snapshot = app.Windows.Cast<Window>().ToArray(); }
        catch { return; }

        foreach (var window in snapshot)
        {
            // Force FluentWindow DWM backdrop repaint
            if (window is FluentWindow fw)
            {
                try
                {
                    WindowBackgroundManager.UpdateBackground(fw, CurrentTheme, FluentBackdrop);
                }
                catch { /* fallback below handles it */ }
            }

            // Re-resolve background from the updated resource dictionary
            try
            {
                var brush = app.TryFindResource("ApplicationBackgroundBrush") as Brush;
                if (brush != null) window.Background = brush;
            }
            catch { /* non-fatal */ }
        }
    }

    private static void Report(string message)
    {
        Console.WriteLine($"[KomorebiDashboard] {message}");
    }
}
