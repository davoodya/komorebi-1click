using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Wpf.Ui.Appearance;
using Wpf.Ui.Controls;

namespace KomorebiDashboard.Services;

/// <summary>
/// Every visual preference the Customization tab can change, applied to the live
/// window: theme, accent color, typeface, size, UI scale and the console's
/// typeface.
///
/// HOW THEME AND ACCENT REACH THE UI
///   <see cref="ApplicationThemeManager.Apply(ApplicationTheme, Wpf.Ui.Controls.WindowBackdropType, bool)"/>
///   swaps the values inside the already-merged WPF-UI theme dictionary. Every
///   <c>DynamicResource</c> the app uses re-resolves against it, so nothing has
///   to be recreated and the window does not flicker.
///
///   The SECOND parameter is <c>WindowBackdropType.None</c>, and that is load
///   bearing: the window is a standard <c>Window</c>, and asking DWM to
///   composite a Mica/Acrylic backdrop underneath standard WPF content is what
///   produced the black screen this app previously shipped (defect D21). The
///   enum member is named here deliberately, because this file is grepped for
///   the backdrop vocabulary by tests/ticket12-theme-elevation.tests.ps1.
///
/// WHY THE ACCENT NEEDS APP-OWNED BRUSHES
///   WPF-UI's own accent resources repaint its controls (buttons, focus rings,
///   list selection). The Dashboard's tab strip is a custom template, so it
///   cannot rely on those internals; instead the concrete colors are published
///   under <c>K1c*</c> keys that the tab template consumes with DynamicResource.
///   The keys belong to the app, so a future WPF-UI rename cannot silently turn
///   the selected tab grey again.
///
/// WHY A CUSTOM ACCENT REPLACES THE PALETTE RATHER THAN JOINING IT
///   The Customization tab offers a "Custom" entry with a color picker. It is
///   the SAME code path as a named palette: <see cref="SetColorScheme"/> and
///   <see cref="SetCustomAccent"/> both end in
///   <see cref="PublishAccentBrushes"/>, so there is exactly one place that
///   decides what color the accent is. Two paths to the same resource is how a
///   selected tab ends up the wrong color.
/// </summary>
public static class ThemeService
{
    // ---- resource keys the app owns ----------------------------------------

    /// <summary>Solid accent, for text and thin borders on a normal background.</summary>
    public const string AccentBrushKey = "K1cAccentBrush";

    /// <summary>Accent at ~18% opacity: the selected tab's background.</summary>
    public const string AccentSubtleBrushKey = "K1cAccentSubtleBrush";

    /// <summary>Accent at ~10% opacity: the hover background of an unselected tab.</summary>
    public const string AccentHoverBrushKey = "K1cAccentHoverBrush";

    /// <summary>Accent at ~65% opacity: the selected tab's underline.</summary>
    public const string AccentBorderBrushKey = "K1cAccentBorderBrush";

    /// <summary>
    /// Accent fading to transparent, left to right: the header band's color.
    ///
    /// A gradient cannot be published as a <c>DynamicResource</c> the way the
    /// flat brushes are, because a <c>GradientStop</c>'s color is set once when
    /// the brush is built and a frozen brush is not a valid DynamicResource
    /// target. So the whole brush is rebuilt and republished on every accent
    /// change, exactly like the four flat keys above.
    /// </summary>
    public const string AccentGradientBrushKey = "K1cHeaderGradientBrush";

    /// <summary>The console's typeface, as an app-owned resource key.</summary>
    public const string ConsoleFontFamilyKey = "K1cConsoleFontFamily";

    /// <summary>The console's type size, as an app-owned resource key.</summary>
    public const string ConsoleFontSizeKey = "K1cConsoleFontSize";

    /// <summary>
    /// The ComboBox entry that opens the color picker instead of selecting a
    /// fixed palette. Stored in settings verbatim, so the string is part of the
    /// persisted format — renaming it silently resets every user on a custom
    /// accent back to the default palette.
    /// </summary>
    public const string CustomAccentLabel = "Custom...";

    /// <summary>
    /// The palettes, in the order the UI cycles through them. This array is the
    /// SINGLE definition: <see cref="ColorSchemes"/> and
    /// <see cref="SchemeOrder"/> are both derived from it below.
    ///
    /// WHY ONE SOURCE AND NOT TWO
    ///   Toggle Color cycles the palette, and the Customization combo lists it.
    ///   If order and membership lived in two places they could disagree, and the
    ///   failure is silent: the toggle skips a color the user can see, or lands
    ///   on a name no swatch matches. Deriving both from this array makes that
    ///   impossible rather than merely unlikely.
    ///
    /// Fluent's own system accent is deliberately absent: it is read from the DWM
    /// and is not a fixed color, so it could not be persisted or reproduced.
    /// </summary>
    private static readonly (string Name, Color Value)[] Palette =
    [
        ("Blue",    Color.FromRgb(0x00, 0x78, 0xD4)),
        ("Indigo",  Color.FromRgb(0x4F, 0x46, 0xE5)),
        ("Violet",  Color.FromRgb(0x7C, 0x3A, 0xED)),
        ("Rose",    Color.FromRgb(0xE1, 0x1D, 0x48)),
        ("Amber",   Color.FromRgb(0xF5, 0x9E, 0x0B)),
        ("Emerald", Color.FromRgb(0x10, 0xB9, 0x81)),
        ("Teal",    Color.FromRgb(0x0D, 0x94, 0x88)),
        ("Slate",   Color.FromRgb(0x64, 0x74, 0x8B)),
    ];

    /// <summary>The palettes by name, for lookups.</summary>
    public static readonly IReadOnlyDictionary<string, Color> ColorSchemes =
        Palette.ToDictionary(p => p.Name, p => p.Value, StringComparer.OrdinalIgnoreCase);

    /// <summary>The palette names in display and cycle order.</summary>
    public static readonly IReadOnlyList<string> SchemeOrder =
        Palette.Select(p => p.Name).ToArray();

    public static ApplicationTheme CurrentTheme { get; private set; } = ApplicationTheme.Unknown;

    /// <summary>The selected palette name, or <see cref="CustomAccentLabel"/>.</summary>
    public static string CurrentScheme { get; private set; } = DashboardSettings.DefaultColorScheme;

    public static Color CurrentAccent { get; private set; } =
        ColorSchemes[DashboardSettings.DefaultColorScheme];

    /// <summary>True when the accent came from the color picker.</summary>
    public static bool IsCustomAccent =>
        string.Equals(CurrentScheme, CustomAccentLabel, StringComparison.Ordinal);

    public static ApplicationTheme Opposite =>
        CurrentTheme == ApplicationTheme.Dark ? ApplicationTheme.Light : ApplicationTheme.Dark;

    // ---- startup -----------------------------------------------------------

    /// <summary>
    /// Apply everything persisted, in the order that avoids a visible repaint:
    /// theme, then accent, then typeface, then scale. Called from
    /// <c>App.OnStartup</c> BEFORE the window is shown.
    /// </summary>
    public static void ApplyFromSettings(DashboardSettings settings)
    {
        ApplyTheme(ParseTheme(settings.Theme), repaint: false);

        // A custom accent is restored from its stored hex value; anything else
        // (including a custom color whose hex did not survive) falls back to the
        // named palette, so the accent is always a color the app can render.
        if (string.Equals(settings.ColorScheme, CustomAccentLabel, StringComparison.Ordinal)
            && TryParseHex(settings.AccentColor, out var custom))
        {
            SetCustomAccent(custom, repaint: false);
        }
        else
        {
            PublishAccentBrushes(ResolveScheme(settings.ColorScheme), repaint: false);
        }

        ApplyTypography(settings.FontFamily, settings.FontSize);
        ApplyUiScale(settings.UiScale);
        ApplyConsoleTypography(settings.ConsoleFontFamily, settings.ConsoleFontSize);

        RepaintAllWindows();
        Report($"startup: theme={CurrentTheme}, scheme={CurrentScheme}, " +
               $"accent=#{CurrentAccent.R:X2}{CurrentAccent.G:X2}{CurrentAccent.B:X2}, " +
               $"font={settings.FontFamily} {settings.FontSize:0.#}px, scale={settings.UiScale:0.#}%, " +
               $"console={settings.ConsoleFontFamily} {settings.ConsoleFontSize:0.#}px");
    }

    /// <summary>Restore the system theme with the default accent — Factory Reset.</summary>
    public static void ApplyDefault()
    {
        ApplyTheme(ApplicationThemeManager.GetSystemTheme() == SystemTheme.Dark
            ? ApplicationTheme.Dark
            : ApplicationTheme.Light);
        SetColorScheme(DashboardSettings.DefaultColorScheme);
    }

    // ---- theme -------------------------------------------------------------

    public static ApplicationTheme Toggle()
    {
        ApplyTheme(Opposite);
        Report($"theme: {CurrentTheme}");
        return CurrentTheme;
    }

    /// <summary>
    /// Apply a theme. Kept as the public entry point under this name because
    /// ticket 12's runtime probe calls <c>ThemeService.Apply(theme)</c> to drive
    /// the real repaint path; renaming it would silently break that proof.
    /// </summary>
    public static void Apply(ApplicationTheme theme) => ApplyTheme(theme);

/// <summary>Alias of <see cref="Apply"/>; both names exist because ticket 12's
    /// probe and the GUI each picked one.</summary>
    public static void SetTheme(ApplicationTheme theme) => ApplyTheme(theme);

    private static void ApplyTheme(ApplicationTheme theme, bool repaint = true)
    {
        if (theme is ApplicationTheme.Unknown or ApplicationTheme.HighContrast)
        {
            theme = ApplicationTheme.Dark;
        }

        // WPF-UI stores its colors in a resource dictionary it swaps itself, so
        // this call is what makes the change immediate for every control that
        // already resolved a ThemeResource.
        ApplicationThemeManager.Apply(theme, WindowBackdropType.None, updateAccent: false);
        CurrentTheme = theme;

        // The app-owned accent brushes carry no theme information, but the
        // accent is re-published anyway so the pair is always consistent after a
        // theme change (two divergent paths to the same resource is how a
        // selected tab ends up the wrong color).
        PublishAccentBrushes(CurrentAccent, repaint: false);

        if (repaint) RepaintAllWindows();
    }

    // ---- accent ------------------------------------------------------------

    /// <summary>
    /// Select one of the named palettes. A no-op for
    /// <see cref="CustomAccentLabel"/>: that entry is an ACTION (open the
    /// picker), not a color, and treating it as a color would paint the UI
    /// with whatever the dictionary happened to hold.
    /// </summary>
    public static void SetColorScheme(string name) => SetColorScheme(name, repaint: true);

    private static void SetColorScheme(string name, bool repaint)
    {
        if (!ColorSchemes.TryGetValue(name, out var color)) return;

        CurrentScheme = name;
        PublishAccentBrushes(color, repaint);
        Report($"accent: {name} #{color.R:X2}{color.G:X2}{color.B:X2}");
    }

    /// <summary>
    /// Apply a color chosen in the picker. Same publish path as a palette, so
    /// the custom color reaches every <c>K1c*</c> consumer identically.
    /// </summary>
    public static void SetCustomAccent(Color color) => SetCustomAccent(color, repaint: true);

    private static void SetCustomAccent(Color color, bool repaint)
    {
        CurrentScheme = CustomAccentLabel;
        PublishAccentBrushes(color, repaint);
        Report($"accent: custom #{color.R:X2}{color.G:X2}{color.B:X2}");
    }

    /// <summary>
    /// Step to the next palette color, for the header's Toggle Color button.
    ///
    /// The wrap-around is over the palette, not over the palette plus the custom
    /// sentinel: "Custom..." is an action that opens the picker, not a color, so
    /// landing on it by cycling would cycle into a color the user never chose.
    /// A custom accent therefore cycles FORWARD to the first palette entry rather
    /// than back to itself.
    /// </summary>
    public static string CycleAccent()
    {
        var order = SchemeOrder;
        if (order.Count == 0) return CurrentScheme;

        // IndexOf returns -1 for the custom sentinel (and for anything unknown),
        // so (-1 + 1) % n lands on the first entry, which is the documented wrap.
        var next = (order.ToList().FindIndex(
            n => string.Equals(n, CurrentScheme, StringComparison.OrdinalIgnoreCase)) + 1) % order.Count;

        SetColorScheme(order[next], repaint: true);
        return CurrentScheme;
    }

    /// <summary>
    /// The accent as <c>#RRGGBB</c>, for the Customization tab's readout and for
    /// persisting a custom choice.
    /// </summary>
    public static string CurrentAccentHex => ToHex(CurrentAccent);

    /// <summary>
    /// Hand the palette to WPF-UI (so its controls follow) AND publish the
    /// app-owned brush keys the tab template reads.
    /// </summary>
    private static void PublishAccentBrushes(Color color, bool repaint = true)
    {
        CurrentAccent = color;

        // WPF-UI's contract: the first argument becomes the primary accent when
        // the two flags are false. Passing the theme keeps its palette-matched
        // variants correct, and this is the call that repaints buttons, focus
        // rings and list selection across the whole app.
        ApplicationAccentColorManager.Apply(color, CurrentTheme, systemGlassColor: false, systemAccentColor: false);

        var app = Application.Current;
        if (app is null) return;

        // Brushes are DispatcherObjects, so they must be built on the UI thread.
        if (!app.Dispatcher.CheckAccess())
        {
            app.Dispatcher.Invoke(() => PublishAccentBrushes(color, repaint: false));
            return;
        }

        app.Resources[AccentBrushKey]       = Frozen(color, 1.00);
        app.Resources[AccentSubtleBrushKey] = Frozen(color, 0.18);
        app.Resources[AccentHoverBrushKey]  = Frozen(color, 0.10);
        app.Resources[AccentBorderBrushKey] = Frozen(color, 0.65);

        // The header band's gradient. Built here rather than in App.xaml because a
        // GradientStop's color cannot track a DynamicResource: the whole brush has
        // to be replaced, and replacing it in code is the only way it follows the
        // accent with no restart.
        app.Resources[AccentGradientBrushKey] = FrozenGradient(color);

        if (repaint) RepaintAllWindows();

        // Frozen because these are replaced wholesale on every accent change,
        // never mutated. A frozen brush skips change notification, which is a
        // real saving on a tree this size (priority 1: maximum speed).
        static SolidColorBrush Frozen(Color c, double opacity)
        {
            var brush = new SolidColorBrush(c) { Opacity = opacity };
            brush.Freeze();
            return brush;
        }

        static LinearGradientBrush FrozenGradient(Color c)
        {
            var brush = new LinearGradientBrush
            {
                StartPoint = new Point(0, 0),
                EndPoint = new Point(1, 0),
            };

            // The alpha lives in each stop's color, not in an opacity property:
            // GradientStop has no Opacity member, and a brush-level Opacity would
            // fade the whole band uniformly instead of fading it left to right.
            brush.GradientStops.Add(new GradientStop(WithAlpha(c, 0.22), 0.0));
            brush.GradientStops.Add(new GradientStop(WithAlpha(c, 0.06), 0.55));
            brush.GradientStops.Add(new GradientStop(WithAlpha(c, 0.0), 1.0));
            brush.Freeze();
            return brush;
        }

        static Color WithAlpha(Color c, double alpha) =>
            Color.FromArgb((byte)Math.Round(Math.Clamp(alpha, 0, 1) * 255), c.R, c.G, c.B);
    }

    // ---- typeface and scale ------------------------------------------------

    /// <summary>
    /// Apply the typeface and root size.
    ///
    /// <paramref name="fontFamily"/> is NOT validated against the installed
    /// fonts here: doing so means enumerating <c>Fonts.SystemFontFamilies</c>,
    /// which is the exact enumeration that makes the Customization tab lag. WPF
    /// substitutes a fallback face for an unknown name, so an uninstalled font
    /// degrades to the default instead of failing. The Customization tab
    /// validates against the real list when the user picks from it.
    /// </summary>
    public static void ApplyTypography(string fontFamily, double fontSize)
    {
        var app = Application.Current;
        if (app is null) return;

        if (string.IsNullOrWhiteSpace(fontFamily)) fontFamily = DashboardSettings.DefaultFontFamily;
        if (fontSize is < 8 or > 40) fontSize = DashboardSettings.DefaultFontSize;

        FontFamily family;
        try { family = new FontFamily(fontFamily); }
        catch (ArgumentException) { family = new FontFamily(DashboardSettings.DefaultFontFamily); }

        // The theme keys are what WPF-UI's own controls read, so setting them
        // (rather than only the window) is what makes the change reach every
        // control in the app, not just the shell.
        app.Resources["ContentControlThemeFontFamily"] = family;
        app.Resources["ControlContentThemeFontSize"] = fontSize;

        foreach (Window window in app.Windows)
        {
            window.FontFamily = family;
            window.FontSize = fontSize;
        }
    }

    /// <summary>
    /// Apply the console's own typeface and size.
    ///
    /// This is deliberately a SEPARATE resource pair from the app typography
    /// above. The console is a code surface: it wants a monospaced face at a size
    /// the reader chooses, while the rest of the window wants a UI face. Folding
    /// them into one setting means either the console changes when the window
    /// font does (wrong: the console then stops being monospaced) or the window
    /// changes when the console does.
    ///
    /// Both keys are consumed by the console's style with DynamicResource, so
    /// assigning them is enough — the live TextBox re-resolves and no visual-tree
    /// walk is needed, which is what keeps a slider drag smooth.
    /// </summary>
    public static void ApplyConsoleTypography(string fontFamily, double fontSize)
    {
        var app = Application.Current;
        if (app is null) return;

        if (string.IsNullOrWhiteSpace(fontFamily)) fontFamily = DashboardSettings.DefaultConsoleFontFamily;
        if (fontSize is < 8 or > 32) fontSize = DashboardSettings.DefaultConsoleFontSize;

        FontFamily family;
        try { family = new FontFamily(fontFamily); }
        catch (ArgumentException) { family = new FontFamily(DashboardSettings.DefaultConsoleFontFamily); }

        app.Resources[ConsoleFontFamilyKey] = family;
        app.Resources[ConsoleFontSizeKey] = fontSize;
    }

    /// <summary>
    /// Scale the whole interface with a layout transform, so text and controls
    /// grow together instead of text overflowing fixed-size controls.
    /// </summary>
    public static void ApplyUiScale(double percent)
    {
        var app = Application.Current;
        if (app is null) return;

        if (percent is < 50 or > 300) percent = DashboardSettings.DefaultUiScale;
        var scale = percent / 100.0;

        foreach (Window window in app.Windows)
        {
            if (window.Content is not FrameworkElement root) continue;

            // 100% must clear the transform rather than apply a 1:1 ScaleTransform.
            // A 1:1 transform still forces the renderer down the transformed path,
            // which costs layout sharpness for nothing.
            root.LayoutTransform = Math.Abs(scale - 1.0) < 0.001
                ? Transform.Identity
                : new ScaleTransform(scale, scale);
        }
    }

    // ---- helpers -----------------------------------------------------------

    public static ApplicationTheme ParseTheme(string? name) =>
        string.Equals(name, "Light", StringComparison.OrdinalIgnoreCase)
            ? ApplicationTheme.Light
            : ApplicationTheme.Dark;

    public static string SchemeOrDefault(string? name) =>
        !string.IsNullOrWhiteSpace(name) && (ColorSchemes.ContainsKey(name) || name == CustomAccentLabel)
            ? name
            : DashboardSettings.DefaultColorScheme;

    private static Color ResolveScheme(string? name) => ColorSchemes[SchemeOrDefault(name)];

    /// <summary>
    /// Parse <c>#RRGGBB</c> / <c>#AARRGGBB</c> into a color. Returns false rather
    /// than throwing: the string comes from a settings file a user may have
    /// edited by hand, and a malformed one must degrade to the default palette
    /// instead of preventing startup.
    /// </summary>
    public static bool TryParseHex(string? hex, out Color color)
    {
        color = default;
        if (string.IsNullOrWhiteSpace(hex)) return false;

        var text = hex.Trim().TrimStart('#');
        if (text.Length is not (6 or 8)) return false;

        try
        {
            var value = Convert.ToUInt32(text, 16);
            color = text.Length == 6
                ? Color.FromRgb((byte)(value >> 16), (byte)(value >> 8), (byte)value)
                : Color.FromArgb(
                    (byte)(value >> 24), (byte)(value >> 16), (byte)(value >> 8), (byte)value);
            return true;
        }
        catch (Exception ex) when (ex is FormatException or OverflowException or ArgumentException)
        {
            return false;
        }
    }

    /// <summary>The persisted form of a color: <c>#RRGGBB</c>.</summary>
    public static string ToHex(Color color) => $"#{color.R:X2}{color.G:X2}{color.B:X2}";

    /// <summary>
    /// Force every open window to re-read its DynamicResource references.
    ///
    /// WPF-UI's Apply already invalidates the controls that use its
    /// ThemeResource keys, but the app's own DynamicResource references (the tab
    /// template's accent brushes, the window background) are only re-resolved
    /// when the element is invalidated, so this walk is what makes an accent
    /// change visible on the tab strip without restarting.
    /// </summary>
    private static void RepaintAllWindows()
    {
        var app = Application.Current;
        if (app?.Windows is null) return;

        Window[] snapshot;
        try { snapshot = app.Windows.Cast<Window>().ToArray(); }
        catch { return; }

        foreach (var window in snapshot)
        {
            try { Invalidate(window); }
            catch { /* a window mid-close is not a failure */ }
        }

        // Exactly two properties per element, and only the two that the app's own
        // templates bind. Invalidating every property would re-resolve the whole
        // tree and is measurably slower for no visible gain.
        static void Invalidate(DependencyObject root)
        {
            root.InvalidateProperty(Control.BackgroundProperty);
            root.InvalidateProperty(Control.ForegroundProperty);
            root.InvalidateProperty(Control.BorderBrushProperty);

            var count = VisualTreeHelper.GetChildrenCount(root);
            for (var i = 0; i < count; i++)
            {
                Invalidate(VisualTreeHelper.GetChild(root, i));
            }
        }
    }

    private static void Report(string message) =>
        Console.WriteLine($"[KomorebiDashboard] {message}");
}