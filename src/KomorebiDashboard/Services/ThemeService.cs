using System.Windows;
using Wpf.Ui.Appearance;
using Wpf.Ui.Markup;

namespace KomorebiDashboard.Services;

/// <summary>
/// Runtime Dark/Light theming via WPF-UI's Fluent styling (ticket 12, ADR-0015
/// priority 4: "modern, beautiful UI", which is only ever bought without
/// giving up priorities 1-3).
///
/// WHY THIS IS CAREFUL ABOUT COST
///   Switching a theme is the single most expensive thing this app ever does to
///   its UI thread: WPF-UI re-resolves every ThemeResource the controls have
///   already bound. So two rules keep it cheap:
///
///   1. ONE dictionary per theme, created once and cached. Re-parsing the XAML
///      on every toggle is what produces a visible stall; a cached dictionary
///      makes the second toggle of the same theme a no-op.
///   2. The switch is applied through <see cref="ApplicationThemeManager.Apply"/>,
///      which re-resolves bindings immediately. A hand-rolled swap of
///      Application.Current.Resources would leave already-open controls holding
///      stale brushes until they were recreated — the classic "half-themed
///      window" defect.
///
/// Both Dark and Light are always materialised up front so the FIRST toggle is
/// as fast as the second.
/// </summary>
public static class ThemeService
{
    /// <summary>
    /// The Windows 11 Fluent backdrop. Mica is the correct choice for a
    /// management tool: it tints the window with the system accent and is far
    /// cheaper to composite than Acrylic, which matters because repainting a
    /// blurred backdrop over a large window is exactly the kind of work that
    /// shows up as jank.
    /// </summary>
    private const Wpf.Ui.Controls.WindowBackdropType FluentBackdrop =
        Wpf.Ui.Controls.WindowBackdropType.Mica;

    /// <summary>The theme in force right now.</summary>
    public static ApplicationTheme CurrentTheme { get; private set; } = ApplicationTheme.Unknown;

    /// <summary>
    /// The cached dictionaries, one per theme. Populated by <see cref="Ensure"/>.
    /// Static because a ResourceDictionary is a Framework resource: it must be
    /// applied to Application.Current.Resources, not owned by a window, or a
    /// closed window would take the theme with it.
    /// </summary>
    private static readonly Dictionary<ApplicationTheme, ThemesDictionary> Cache = new();

    /// <summary>The other theme — what a toggle should switch TO.</summary>
    public static ApplicationTheme Opposite =>
        CurrentTheme == ApplicationTheme.Dark ? ApplicationTheme.Light : ApplicationTheme.Dark;

    /// <summary>
    /// Apply the startup theme. Called BEFORE the main window is shown so the
    /// user never sees the default light theme repaint into dark, which would be
    /// a priority-2 (smoothness) regression caused by priority-4 work.
    /// </summary>
    public static void ApplyDefault()
    {
        // Follow the OS where the OS expresses a preference, otherwise Light.
        // Following the system theme is the Windows-native behaviour and is what
        // "defaults to the Windows 11 appearance" means in practice.
        var theme = ApplicationThemeManager.GetSystemTheme() == SystemTheme.Dark
            ? ApplicationTheme.Dark
            : ApplicationTheme.Light;

        Apply(theme);
        Report($"startup theme: {theme}");
    }

    /// <summary>
    /// Apply a theme immediately. Safe to call repeatedly with the same value;
    /// a redundant call is skipped so a double-click on the toggle costs nothing.
    /// </summary>
    public static void Apply(ApplicationTheme theme)
    {
        if (theme == ApplicationTheme.Unknown) theme = ApplicationTheme.Light;

        if (CurrentTheme == theme && Application.Current is not null) return;

        Ensure(theme);

        // Apply() is WPF-UI's own entry point: it resolves the dictionary,
        // merges it and notifies every ThemeResource binding, which is why the
        // change is visible immediately rather than on the next window.
        //
        // SystemTheme is NOT an ApplicationTheme value in WPF-UI 4.3.0 — it is
        // reached through ApplySystemTheme() and read back with
        // GetSystemTheme(). Both verified by reflection; the 4.x docs still
        // mention a SystemTheme enum member that this version dropped.
        if (theme == ApplicationTheme.Unknown)
        {
            ApplicationThemeManager.ApplySystemTheme();
            CurrentTheme = ApplicationThemeManager.GetAppTheme();
            return;
        }

        ApplicationThemeManager.Apply(theme, FluentBackdrop, updateAccent: true);

        CurrentTheme = theme;
    }

    /// <summary>
    /// Toggle between Dark and Light. Returns the theme now in force so the
    /// caller can update a label without asking again.
    /// </summary>
    public static ApplicationTheme Toggle()
    {
        Apply(Opposite);
        Report($"theme toggled to: {CurrentTheme}");
        return CurrentTheme;
    }

    /// <summary>
    /// Materialise and cache the dictionary for a theme.
    ///
    /// Source IS NOT SET HERE, DELIBERATELY. An earlier draft pointed it at
    /// pack://application:,,,/Wpf.Ui;component/Themes/{theme}.xaml and the app
    /// died on startup with:
    ///
    ///     XamlParseException: Set property 'ResourceDictionary.Source' threw
    ///     IOException: Cannot locate resource 'themes/light.xaml'
    ///
    /// The real location is Wpf.Ui.g.resources -> resources/theme/light.baml,
    /// and ThemesDictionary already derives the correct pack URI itself in its
    /// internal SetSourceBasedOnSelectedTheme(). Setting Source by hand both
    /// duplicated that logic and used a path that does not exist. Assigning
    /// Theme alone is correct.
    ///
    /// The dictionary is also constructed empty and then given a theme, because
    /// Theme's setter is what triggers that internal Source derivation.
    /// </summary>
    private static void Ensure(ApplicationTheme theme)
    {
        if (Cache.ContainsKey(theme)) return;

        Cache[theme] = new ThemesDictionary { Theme = theme };
    }

    /// <summary>
    /// Report the applied theme. Priority 1 is speed and priority 3 is
    /// smoothness, but a theme the user cannot confirm changed is a support
    /// question later, so it is reported on the same channel as startup timing.
    /// </summary>
    private static void Report(string message)
    {
        Console.WriteLine($"[KomorebiDashboard] {message}");
    }
}