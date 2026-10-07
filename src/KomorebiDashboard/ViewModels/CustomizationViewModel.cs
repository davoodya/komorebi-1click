using System.Collections.ObjectModel;
using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using KomorebiDashboard.Services;
using Wpf.Ui.Appearance;

namespace KomorebiDashboard.ViewModels;

/// <summary>
/// Customization tab: theme, accent color, typeface, size, scale and the console
/// share. Everything here is the Dashboard's own appearance — nothing in this tab
/// touches komorebi, whkd, YASB or AutoHotkey.
///
/// PREVIEW NOW, PERSIST ON APPLY
///   Theme, accent and typeface are applied to the live window as soon as they
///   change, because that IS the decision — asking a user to press Apply before
///   they can see an accent color would be absurd. Persisting is separate: the
///   user presses Apply Settings to keep the current appearance for the next
///   launch. Factory Reset and the Settings tab both use the same defaults.
/// </summary>
public sealed partial class CustomizationViewModel : ObservableObject
{
    private const string DefaultFont = DashboardSettings.DefaultFontFamily;

    [ObservableProperty] private double _fontSize = DashboardSettings.DefaultFontSize;
    [ObservableProperty] private double _uiScale = DashboardSettings.DefaultUiScale;
    [ObservableProperty] private double _consolePercent = SettingsStore.Current.ConsolePercent;

    /// <summary>Monospaced faces offered for the console pane.</summary>
    public ObservableCollection<string> AvailableConsoleFonts { get; }

    [ObservableProperty] private string _selectedConsoleFont = DashboardSettings.DefaultConsoleFontFamily;

    [ObservableProperty] private double _consoleFontSize = DashboardSettings.DefaultConsoleFontSize;

    [ObservableProperty] private string _consoleFontStatus = string.Empty;
    [ObservableProperty] private string _selectedScheme = DashboardSettings.DefaultColorScheme;
    [ObservableProperty] private string _selectedFont = DefaultFont;

    /// <summary>
    /// The accent readout, e.g. <c>#0078D4</c>. Updated by <see cref="SyncAccentDisplay"/>
    /// from ThemeService, which owns the value — never from the combo selection,
    /// because a custom accent has no combo entry to derive a value from.
    /// </summary>
    [ObservableProperty] private string _accentHex = string.Empty;

    /// <summary>True while the full font list is being enumerated off-thread.</summary>
    [ObservableProperty] private bool _isLoadingFonts;

    [ObservableProperty] private string _applyStatus = "Changes are previewed immediately; press Apply Settings to keep them.";
    [ObservableProperty] private string _themeStatus = string.Empty;
    [ObservableProperty] private string _fontStatus = string.Empty;

    public ObservableCollection<string> AvailableSchemes { get; }
    public ObservableCollection<string> AvailableFonts { get; }

    public IRelayCommand ToggleThemeCommand { get; }
    public IRelayCommand ApplyCommand { get; }
    public IRelayCommand ResetDefaultsCommand { get; }

    /// <summary>Opens the custom color picker.</summary>
    public IRelayCommand PickCustomColorCommand { get; }

    /// <summary>Set while the view is selecting the sentinel, so the load is
    /// triggered exactly once and the sentinel never becomes a selection.</summary>
    private bool _handlingSentinel;

    /// <summary>
    /// The console list's counterpart to <see cref="_handlingSentinel"/>. Kept
    /// separate because the two lists expand independently: re-selecting the app
    /// typeface must not consume the console list's one flag and vice versa.
    /// </summary>
    private bool _handlingConsoleSentinel;

    /// <summary>
    /// Set while <see cref="SyncAccentDisplay"/> writes <see cref="SelectedScheme"/>.
    ///
    /// Without it, a custom accent would loop forever: SyncAccentDisplay selects
    /// "Custom...", that selection fires OnSelectedSchemeChanged, which opens the
    /// picker, whose result is a custom accent again. The flag breaks the cycle at
    /// the one place the write happens.
    /// </summary>
    private bool _syncingAccent;

    public CustomizationViewModel(ScriptService scripts)
    {
        AvailableSchemes = new ObservableCollection<string>(ThemeService.ColorSchemes.Keys);

        // The picker entry, always last so the palette names keep their order and
        // its position is predictable — the same convention as the font list's
        // "All Fonts" sentinel.
        AvailableSchemes.Add(ThemeService.CustomAccentLabel);

        // Tier 1 only. The full enumeration is the expensive call this tab exists
        // to avoid paying on open.
        AvailableFonts = new ObservableCollection<string>(FontCatalog.StandardWithSentinel());

        // The console list is monospaced-only. Offering Segoe UI here would
        // produce a console whose columns do not line up, which is the one thing
        // a script-output pane must not do.
        AvailableConsoleFonts = new ObservableCollection<string>(FontCatalog.MonospacedWithSentinel());

        var settings = SettingsStore.Current;
        _fontSize = settings.FontSize;
        _uiScale = settings.UiScale;
        _consolePercent = settings.ConsolePercent;
        _selectedConsoleFont = string.IsNullOrWhiteSpace(settings.ConsoleFontFamily)
            ? DashboardSettings.DefaultConsoleFontFamily
            : settings.ConsoleFontFamily;
        _consoleFontSize = settings.ConsoleFontSize;

        // A persisted face that is not in the standard list (picked from a full
        // enumeration in an earlier session) is inserted, so the combo shows the
        // stored choice instead of silently falling back to its first item.
        if (!AvailableConsoleFonts.Contains(_selectedConsoleFont.ToString()))
        {
            AvailableConsoleFonts.Insert(0, _selectedConsoleFont);
        }
        _selectedScheme = ThemeService.SchemeOrDefault(settings.ColorScheme);
        _selectedFont = string.IsNullOrWhiteSpace(settings.FontFamily) ? DefaultFont : settings.FontFamily;
        if (!AvailableFonts.Contains(_selectedFont) && _selectedFont != FontCatalog.AllFontsSentinel)
        {
            // A font chosen from the full list is not in tier 1. Insert it so the
            // combo shows the persisted choice instead of falling back to its
            // first item, which would silently change the setting on open.
            AvailableFonts.Insert(0, _selectedFont);
        }

        ToggleThemeCommand = new RelayCommand(ToggleTheme);
        ApplyCommand = new RelayCommand(ApplySettings);
        ResetDefaultsCommand = new RelayCommand(ResetToDefaults);
        PickCustomColorCommand = new RelayCommand(PickCustomColor);

        SyncAccentDisplay();
        UpdateThemeStatus();
        UpdateFontStatus();
        UpdateConsoleFontStatus();
    }

    // ---------------------------------------------------------------------
    // Live preview handlers
    // ---------------------------------------------------------------------

    partial void OnSelectedSchemeChanged(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return;

        // "Custom..." is an ACTION, not a color: selecting it opens the picker
        // and it must never become the combo's committed selection, or the list
        // would show "Custom..." while the accent is one of the palettes.
        // Same shape as the font list's "All Fonts" sentinel.
        if (value == ThemeService.CustomAccentLabel)
        {
            // Guarded: when this value came from SyncAccentDisplay it is a
            // reflection of the current custom accent, not a user click, and
            // reopening the picker would trap the user in a dialog loop.
            if (_syncingAccent) return;

            PickCustomColor();
            return;
        }

        ThemeService.SetColorScheme(value);
        SyncAccentDisplay();
        ApplyStatus = $"Accent changed to {value} ({AccentHex}). Press Apply Settings to keep it.";
    }

    /// <summary>
    /// Open the custom color picker and apply what comes back.
    ///
    /// Cancel leaves the accent untouched: <c>Ask</c> returns false and nothing is
    /// written, so backing out of the picker cannot repaint the app.
    /// </summary>
    private void PickCustomColor()
    {
        var owner = System.Windows.Application.Current?.MainWindow;
        if (!Views.ColorPickerDialog.Ask(owner, ThemeService.CurrentAccent, out var chosen))
        {
            // Re-assert the palette selection the combo should be showing, in case
            // the user reached here by picking "Custom..." from the list.
            SyncAccentDisplay();
            ApplyStatus = "No color chosen; the accent is unchanged.";
            return;
        }

        ThemeService.SetCustomAccent(chosen);
        SyncAccentDisplay();
        ApplyStatus = $"Custom accent {ThemeService.ToHex(chosen)} applied. Press Apply Settings to keep it.";
    }

    /// <summary>
    /// Bring <see cref="AccentHex"/> and <see cref="SelectedScheme"/> back in line
    /// with ThemeService.
    ///
    /// ThemeService is the single owner of the accent, so the display is refreshed
    /// FROM it rather than from whatever the user clicked. That is what keeps the
    /// hex readout correct when the header's Toggle Color button changes the
    /// accent while this tab is open, and it is why the combo never keeps a
    /// selection that disagrees with the applied color.
    /// </summary>
    private void SyncAccentDisplay()
    {
        AccentHex = ThemeService.CurrentAccentHex;

        try
        {
            _syncingAccent = true;

            // A custom accent has no combo entry to point at, so the list falls
            // back to the sentinel — which is exactly what the custom color is.
            SelectedScheme = ThemeService.IsCustomAccent
                ? ThemeService.CustomAccentLabel
                : ThemeService.CurrentScheme;
        }
        finally
        {
            _syncingAccent = false;
        }
    }

    partial void OnSelectedFontChanged(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return;

        // The sentinel is an action, not a typeface: it must never stay selected,
        // and selecting it is the trigger for the one-off full enumeration.
        if (value == FontCatalog.AllFontsSentinel)
        {
            if (!_handlingSentinel) _ = LoadAllFontsAsync();
            return;
        }

        ThemeService.ApplyTypography(value, FontSize);
        UpdateFontStatus();
        ApplyStatus = $"Typeface previewed: {value}. Press Apply Settings to keep it.";
    }

    partial void OnFontSizeChanged(double value)
    {
        ThemeService.ApplyTypography(SelectedFont, value);
        UpdateFontStatus();
    }

    partial void OnUiScaleChanged(double value) => ThemeService.ApplyUiScale(value);

    partial void OnConsolePercentChanged(double value)
    {
        // Same live path as the Settings slider: without RefreshConsoleShare the
        // share would only be stored, and every tab would keep its old height
        // until the next launch.
        TabViewModelBase.RefreshConsoleShare(value);
        SettingsStore.Current.ConsolePercent = value;
        SettingsStore.Save();
        ApplyStatus = $"Console height {value:0}%. Applied to every tab now.";
    }

    partial void OnSelectedConsoleFontChanged(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return;

        // The sentinel is an action, not a typeface — it expands the console list
        // to every installed face and must never stay selected. Same shape as the
        // app typeface's sentinel above.
        if (value == FontCatalog.AllFontsSentinel)
        {
            if (!_handlingConsoleSentinel) _ = LoadAllConsoleFontsAsync();
            return;
        }

        ThemeService.ApplyConsoleTypography(value, ConsoleFontSize);
        UpdateConsoleFontStatus();
        ApplyStatus = $"Console typeface previewed: {value}. Press Apply Settings to keep it.";
    }

    partial void OnConsoleFontSizeChanged(double value)
    {
        ThemeService.ApplyConsoleTypography(SelectedConsoleFont, value);
        UpdateConsoleFontStatus();
    }

    /// <summary>
    /// Enumerate every installed face for the CONSOLE list, once per session, off
    /// the UI thread. Shares <see cref="FontCatalog.AllInstalled"/>'s cache with
    /// the app-typeface row, so asking for both costs one enumeration.
    /// </summary>
    private async Task LoadAllConsoleFontsAsync()
    {
        IsLoadingFonts = true;
        ApplyStatus = "Loading the full font list for the console...";

        try
        {
            var all = await Task.Run(LoadAllFontsCpuBound);

            var previous = SelectedConsoleFont;
            var wasSentinel = previous == FontCatalog.AllFontsSentinel;

            AvailableConsoleFonts.Clear();
            foreach (var font in all) AvailableConsoleFonts.Add(font);
            AvailableConsoleFonts.Add(FontCatalog.AllFontsSentinel);

            ApplyStatus = $"Loaded {all.Count} installed fonts for the console.";
            _handlingConsoleSentinel = wasSentinel;

            SelectedConsoleFont = all.Contains(previous, StringComparer.OrdinalIgnoreCase)
                ? previous
                : DashboardSettings.DefaultConsoleFontFamily;
        }
        catch (Exception ex)
        {
            ApplyStatus = $"Could not enumerate the installed fonts: {ex.Message}";
        }
        finally
        {
            _handlingConsoleSentinel = false;
            IsLoadingFonts = false;
            UpdateConsoleFontStatus();
        }
    }

    private void UpdateConsoleFontStatus() =>
        ConsoleFontStatus = $"Console output renders in {SelectedConsoleFont} at {ConsoleFontSize:0}px. " +
                            $"Choose \"{FontCatalog.AllFontsSentinel}\" to browse everything installed.";

    private void ToggleTheme()
    {
        ThemeService.Toggle();
        UpdateThemeStatus();
        ApplyStatus = "Theme previewed. Press Apply Settings to keep it.";
    }

    // ---------------------------------------------------------------------
    // Full font list, on demand
    // ---------------------------------------------------------------------

    /// <summary>
    /// Enumerate every installed face, ONCE per session, off the UI thread.
    ///
    /// This is the whole reason the font list is tiered: the enumeration atomizes
    /// hundreds of families and is the single slowest call in the app. It runs
    /// only when the user explicitly asks for the full list, and the result is
    /// cached by <see cref="FontCatalog"/> so a second visit is instant.
    /// </summary>
    private async Task LoadAllFontsAsync()
    {
        IsLoadingFonts = true;
        ApplyStatus = "Loading the full font list...";

        try
        {
            var all = await Task.Run(LoadAllFontsCpuBound);

            var previous = SelectedFont;
            var wasSentinel = previous == FontCatalog.AllFontsSentinel;

            AvailableFonts.Clear();
            foreach (var font in all) AvailableFonts.Add(font);
            AvailableFonts.Add(FontCatalog.AllFontsSentinel);

            ApplyStatus = $"Loaded {all.Count} installed fonts.";
            _handlingSentinel = wasSentinel;

            // Re-selecting the previous face brackets the sentinel with the
            // flag, so the assignment triggers no second load and the sentinel
            // can never remain the selected item.
            SelectedFont = all.Contains(previous, StringComparer.OrdinalIgnoreCase) ? previous : DefaultFont;
        }
        catch (Exception ex)
        {
            ApplyStatus = $"Could not enumerate the installed fonts: {ex.Message}";
        }
        finally
        {
            _handlingSentinel = false;
            IsLoadingFonts = false;
            UpdateFontStatus();
        }
    }

    // ---------------------------------------------------------------------
    // Persist / reset
    // ---------------------------------------------------------------------

    /// <summary>Write the current appearance to disk so the next launch starts here.</summary>
    private void ApplySettings()
    {
        var s = SettingsStore.Current;

        s.Theme = ThemeService.CurrentTheme == ApplicationTheme.Dark ? "Dark" : "Light";
        s.ColorScheme = ThemeService.CurrentScheme;

        // Persisted only for a custom accent: writing a hex alongside a palette
        // name would leave a value that looks like the current color but is not.
        s.AccentColor = ThemeService.IsCustomAccent ? ThemeService.CurrentAccentHex : string.Empty;

        s.FontSize = FontSize;
        s.FontFamily = SelectedFont;
        s.UiScale = UiScale;
        s.ConsolePercent = ConsolePercent;
        s.ConsoleFontFamily = SelectedConsoleFont;
        s.ConsoleFontSize = ConsoleFontSize;

        var saved = SettingsStore.Save();

        ApplyStatus = saved
            ? $"Saved. These settings will be restored on the next launch ({SettingsStore.FilePath})."
            : "Could not write the settings file. See the console for the reason.";
    }

    /// <summary>
    /// Preview the defaults without persisting them, so the user can look and then
    /// decide. Apply Settings is what keeps the change.
    /// </summary>
    private void ResetToDefaults()
    {
        FontSize = DashboardSettings.DefaultFontSize;
        UiScale = DashboardSettings.DefaultUiScale;
        ConsolePercent = DashboardSettings.DefaultConsolePercent;
        SelectedConsoleFont = DashboardSettings.DefaultConsoleFontFamily;
        ConsoleFontSize = DashboardSettings.DefaultConsoleFontSize;
        SelectedFont = DefaultFont;
        ThemeService.Apply(ThemeService.ParseTheme(DashboardSettings.DefaultTheme));

        // After the theme, so the accent lands on the right theme, and via
        // SyncAccentDisplay so the combo and the hex readout follow the reset
        // rather than keeping the pre-reset color.
        ThemeService.SetColorScheme(DashboardSettings.DefaultColorScheme);
        SyncAccentDisplay();

        UpdateThemeStatus();
        UpdateFontStatus();
        ApplyStatus = "Defaults previewed. Press Apply Settings to keep them.";
    }

    private void UpdateThemeStatus() =>
        ThemeStatus = $"Currently applying: {(ThemeService.CurrentTheme == ApplicationTheme.Light ? "Light" : "Dark")} " +
                      "for this whole app, including every tab and dialog.";

    /// <summary>
    /// The CpuBound half of the font expansion, kept as a named method so its
    /// off-thread justification is visible at the call site and in the project's
    /// Task.Run audit (tests/ticket11-threading.tests.ps1 recognises the
    /// CpuBound suffix).
    ///
    /// Enumerating <c>Fonts.SystemFontFamilies</c> builds every installed face
    /// and costs hundreds of milliseconds; on the UI thread that is exactly the
    /// freeze the two-tier list exists to avoid.
    /// </summary>
    private static List<string> LoadAllFontsCpuBound() => FontCatalog.AllInstalled();

    private void UpdateFontStatus() =>
        FontStatus = $"Previewing {SelectedFont} at {FontSize:0}px. The list opens with the standard faces; " +
                     $"choose \"{FontCatalog.AllFontsSentinel}\" to browse everything installed on this machine.";
}