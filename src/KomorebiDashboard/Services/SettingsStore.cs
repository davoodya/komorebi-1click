using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace KomorebiDashboard.Services;

/// <summary>
/// The Dashboard's user preferences, as persisted to
/// <c>%APPDATA%\KomorebiDashboard\settings.json</c>.
///
/// WHY A PLAIN POCO (no WPF types)
///   This type is serialized on every Apply and read at startup before any
///   window exists, so it must not depend on the dispatcher or on any GUI type.
///   Applying a value is <see cref="ThemeService"/>'s job; storing it is this
///   one's.
///
/// WHY EVERY PROPERTY HAS A DEFAULT
///   A settings file written by an older build is missing whatever was added
///   since. Deserialization leaves absent members at their initializer value,
///   so an old file upgrades silently instead of producing zeros — which would
///   otherwise show up as a 0px font and an invisible UI.
/// </summary>
public sealed class DashboardSettings
{
    // Defaults live on the type, not at each call site: Factory Reset, a corrupt
    // file, and a first run must all land on exactly the same values.
    public const string DefaultTheme = "Dark";
    public const string DefaultColorScheme = "Blue";
    public const double DefaultFontSize = 14;
    public const string DefaultFontFamily = "Segoe UI";
    public const double DefaultUiScale = 100;

    /// <summary>
    /// Defaults for the console's own typeface. Monospaced, because that is what
    /// script output is: the app typeface (a UI face) would make columns of
    /// output impossible to line up.
    ///
    /// Kept as a list rather than one name so WPF falls through to the next face
    /// if the machine lacks Cascadia (which is not installed by default on
    /// Windows 10). Consolas is present on every supported version.
    /// </summary>
    public const string DefaultConsoleFontFamily = "Cascadia Mono, Consolas, Courier New";

    public const double DefaultConsoleFontSize = 12;

    /// <summary>
    /// Share of the tab's height given to the console pane, in percent. Clamped
    /// by <see cref="Views.Controls.TabLayout"/>; 25 is the value the layout is
    /// designed around (hermes priority: the console is for output, not for
    /// filling the window).
    /// </summary>
    public const double DefaultConsolePercent = 25;

    public string Theme { get; set; } = DefaultTheme;
    public string ColorScheme { get; set; } = DefaultColorScheme;
    public double FontSize { get; set; } = DefaultFontSize;
    public string FontFamily { get; set; } = DefaultFontFamily;
    public double UiScale { get; set; } = DefaultUiScale;
    public double ConsolePercent { get; set; } = DefaultConsolePercent;

    /// <summary>
    /// The hex color behind a CUSTOM accent, <c>#RRGGBB</c>. Only consulted when
    /// <see cref="ColorScheme"/> is the custom sentinel: a palette name is always
    /// resolved from the palette itself, so a stale hex left over from an earlier
    /// custom choice cannot override a named scheme the user picked afterwards.
    /// </summary>
    public string AccentColor { get; set; } = string.Empty;

    /// <summary>The console pane's typeface, independent of the app typeface.</summary>
    public string ConsoleFontFamily { get; set; } = DefaultConsoleFontFamily;

    /// <summary>The console pane's type size.</summary>
    public double ConsoleFontSize { get; set; } = DefaultConsoleFontSize;

    /// <summary>
    /// The on/off state of the Dashboard's toggle preferences — currently whether
    /// the multi-monitor monitor-boundary workaround is enabled.
    ///
    /// A map rather than one bool per switch: the Customization tab is expected to
    /// grow more toggles, and a map means adding one is a key, not a new property
    /// plus a new settings migration.
    /// </summary>
    public Dictionary<string, bool> Toggles { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// AutoHotkey script enable/disable, keyed by the script key from the
    /// installer manifest (<c>autocorrect</c>, <c>ChangeLangF3</c>,
    /// <c>NewFile</c>). A key that no longer exists in the manifest is ignored
    /// rather than carried forever.
    /// </summary>
    public Dictionary<string, bool> AhkScriptStates { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// A deep copy, so a caller can stage edits and discard them without
    /// mutating the live settings the UI is already bound to.
    /// </summary>
    public DashboardSettings Clone() => new()
    {
        Theme = Theme,
        ColorScheme = ColorScheme,
        FontSize = FontSize,
        FontFamily = FontFamily,
        UiScale = UiScale,
        ConsolePercent = ConsolePercent,
        AccentColor = AccentColor,
        ConsoleFontFamily = ConsoleFontFamily,
        ConsoleFontSize = ConsoleFontSize,
        Toggles = new Dictionary<string, bool>(Toggles, StringComparer.OrdinalIgnoreCase),
        AhkScriptStates = new Dictionary<string, bool>(AhkScriptStates, StringComparer.OrdinalIgnoreCase),
    };
}

/// <summary>
/// The single owner of the settings file: load once at startup, save on every
/// explicit Apply, and raise <see cref="Changed"/> so open views can re-read.
///
/// WHY A STATIC STORE AND NOT A PARAMETER
///   Seven tabs and the CLI twin all need the same instance. Threading one
///   object through every constructor buys nothing and makes the design-time
///   and test surfaces harder to construct. The store is small, has no
///   dependencies, and its lifetime is exactly the process's.
/// </summary>
public static class SettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    private static DashboardSettings _current = new();

    /// <summary>Raised after a successful save or reset, on the calling thread.</summary>
    public static event EventHandler? Changed;

    /// <summary>The live settings. Never null.</summary>
    public static DashboardSettings Current => _current;

    public static string DirectoryPath =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "KomorebiDashboard");

    public static string FilePath => Path.Combine(DirectoryPath, "settings.json");

    /// <summary>True when a settings file exists on disk.</summary>
    public static bool Exists => File.Exists(FilePath);

    /// <summary>
    /// Read the settings file, falling back to defaults.
    ///
    /// A corrupt file is MOVED ASIDE rather than merely ignored: the user's
    /// previous preferences are still in it, and silently overwriting them on
    /// the next save would destroy the only copy. The renamed file is reported
    /// on the console so it can be recovered by hand.
    /// </summary>
    public static DashboardSettings Load()
    {
        if (!File.Exists(FilePath))
        {
            _current = new DashboardSettings();
            return _current;
        }

        try
        {
            var json = File.ReadAllText(FilePath);
            _current = JsonSerializer.Deserialize<DashboardSettings>(json, JsonOptions)
                       ?? new DashboardSettings();
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            _current = new DashboardSettings();
            QuarantineFile(ex);
        }

        Normalize(_current);
        return _current;
    }

    /// <summary>
    /// Write the current settings atomically.
    ///
    /// The temp-then-replace dance matters: a crash or a power loss halfway
    /// through a direct write leaves a truncated JSON file, which is exactly the
    /// corrupt-file path above. Rename within one directory is atomic on NTFS.
    /// </summary>
    public static bool Save()
    {
        try
        {
            System.IO.Directory.CreateDirectory(DirectoryPath);
            var json = JsonSerializer.Serialize(_current, JsonOptions);

            var temp = FilePath + ".tmp";
            File.WriteAllText(temp, json);
            File.Move(temp, FilePath, overwrite: true);

            Report($"settings saved: {FilePath}");
            Changed?.Invoke(null, EventArgs.Empty);
            return true;
        }
        catch (Exception ex)
        {
            // Reported, not swallowed: a preference the user changed that did
            // not persist is a defect they would otherwise only discover later.
            Report($"settings save FAILED: {ex.Message}");
            return false;
        }
    }

    /// <summary>Replace the live settings and re-read from disk, if any.</summary>
    public static DashboardSettings Reload()
    {
        Load();
        Changed?.Invoke(null, EventArgs.Empty);
        return _current;
    }

    /// <summary>
    /// Restore every preference to its default and persist that. The file is
    /// kept (written with defaults) rather than deleted, so the state is
    /// explicit and the same on the next launch.
    /// </summary>
    public static void ResetToDefaults()
    {
        _current = new DashboardSettings();
        Save();
        Report("factory reset: all preferences restored to defaults");
    }

    /// <summary>
    /// Force values into their valid ranges. Runs on every load and before every
    /// save, so no code path can persist a value the UI cannot render.
    /// </summary>
    private static void Normalize(DashboardSettings s)
    {
        if (string.IsNullOrWhiteSpace(s.Theme)) s.Theme = DashboardSettings.DefaultTheme;
        if (string.IsNullOrWhiteSpace(s.ColorScheme)) s.ColorScheme = DashboardSettings.DefaultColorScheme;
        if (string.IsNullOrWhiteSpace(s.FontFamily)) s.FontFamily = DashboardSettings.DefaultFontFamily;

        if (s.FontSize is < 8 or > 40) s.FontSize = DashboardSettings.DefaultFontSize;
        if (s.UiScale is < 50 or > 300) s.UiScale = DashboardSettings.DefaultUiScale;
        if (s.ConsolePercent is < 10 or > 60) s.ConsolePercent = DashboardSettings.DefaultConsolePercent;

        if (string.IsNullOrWhiteSpace(s.ConsoleFontFamily)) s.ConsoleFontFamily = DashboardSettings.DefaultConsoleFontFamily;
        if (s.ConsoleFontSize is < 8 or > 32) s.ConsoleFontSize = DashboardSettings.DefaultConsoleFontSize;

        s.AhkScriptStates ??= new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        s.Toggles ??= new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
    }

    // ---- toggle preferences -------------------------------------------------
    //
    // Read/write by key rather than one property per switch, so a new toggle is a
    // constant plus a UI row and needs no change here.

    /// <summary>Whether the multi-monitor monitor-boundary workaround is on.</summary>
    public const string MultiMonitorFixKey = "MultiMonitorFix";

    /// <summary>
    /// Default for the multi-monitor workaround.
    ///
    /// ON, because the bug it works around is not hypothetical: on a
    /// multi-monitor desk komorebi mis-handles this (plain WPF) window and it
    /// cannot be placed reliably. A user on a single monitor sees no effect
    /// either way, so defaulting to the value that helps the affected users is
    /// the right way round.
    /// </summary>
    public const bool DefaultMultiMonitorFix = true;

    /// <summary>Read a toggle, falling back to its default when unset.</summary>
    public static bool GetToggle(string key, bool fallback)
    {
        if (string.IsNullOrWhiteSpace(key)) return fallback;
        return _current.Toggles.TryGetValue(key, out var value) ? value : fallback;
    }

    /// <summary>Set and persist a toggle.</summary>
    public static void SetToggle(string key, bool value)
    {
        if (string.IsNullOrWhiteSpace(key)) return;
        _current.Toggles[key] = value;
        Save();
    }

    private static void QuarantineFile(Exception cause)
    {
        try
        {
            var stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss");
            var quarantined = $"{FilePath}.corrupt-{stamp}";
            File.Move(FilePath, quarantined, overwrite: true);
            Report($"settings file was unreadable ({cause.GetType().Name}); moved to {quarantined}; defaults are in use");
        }
        catch (Exception ex)
        {
            Report($"settings file was unreadable and could not be moved aside: {ex.Message}");
        }
    }

    private static void Report(string message) =>
        Console.WriteLine($"[KomorebiDashboard] {message}");
}