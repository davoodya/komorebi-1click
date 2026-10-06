using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using KomorebiDashboard.Services;
using Wpf.Ui.Appearance;
using Wpf.Ui.Controls;

namespace KomorebiDashboard.ViewModels;

/// <summary>
/// Drives the Customization tab: theme toggle, colour scheme, backdrop
/// sub-theme, font size, font family, and UI scale. All changes are applied
/// immediately at runtime through ThemeService and WPF layout transforms.
///
/// NOTE (D21 fix): This ViewModel does NOT inherit TabViewModelBase because
/// the Customization tab has no script verbs — it is pure UI configuration.
/// TabViewModelBase requires a ScriptService + tab name for its verb registry
/// and output buffering, none of which apply here. Inheriting from it forced
/// a constructor signature mismatch (CS1729) and added dead weight.
/// </summary>
public partial class CustomizationViewModel : ObservableObject
{
    // Defaults
    private const double DefaultFontSize = 14;
    private const double DefaultScale = 100;
    private const string DefaultScheme = "Blue";
    private const string DefaultFont = "Segoe UI";
    private const string DefaultBackdrop = "Mica";

    [ObservableProperty] private double _fontSize = DefaultFontSize;
    [ObservableProperty] private double _uiScale = DefaultScale;
    [ObservableProperty] private string _selectedScheme = DefaultScheme;
    [ObservableProperty] private string _selectedFont = DefaultFont;
    [ObservableProperty] private string _selectedBackdrop = DefaultBackdrop;

    public ObservableCollection<string> AvailableSchemes { get; }
    public ObservableCollection<string> AvailableBackdrops { get; }
    public ObservableCollection<string> AvailableFonts { get; }

    public IRelayCommand ToggleThemeCommand { get; }
    public IRelayCommand ResetDefaultsCommand { get; }

    /// <summary>
    /// Constructor takes ScriptService for API compatibility with MainWindow's
    /// Attach() pattern, but does not use it — this tab has no scripts.
    /// </summary>
    public CustomizationViewModel(ScriptService service)
    {
        AvailableSchemes = new ObservableCollection<string>(ThemeService.ColorSchemes.Keys);
        AvailableBackdrops = new ObservableCollection<string> { "Mica", "Acrylic", "Tabbed", "None" };

        // Enumerate installed fonts (fast: only names, no glyph loading)
        var fonts = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var ff in Fonts.SystemFontFamilies)
            fonts.Add(ff.Source);
        AvailableFonts = new ObservableCollection<string>(fonts);

        ToggleThemeCommand = new RelayCommand(() => ThemeService.Toggle());
        ResetDefaultsCommand = new RelayCommand(ResetDefaults);
    }

    // --- Reactive property changes ---

    partial void OnFontSizeChanged(double value)
    {
        ApplyTypography(value, SelectedFont);
    }

    partial void OnSelectedFontChanged(string value)
    {
        ApplyTypography(FontSize, value);
    }

    partial void OnUiScaleChanged(double value)
    {
        ApplyScale(value);
    }

    partial void OnSelectedSchemeChanged(string value)
    {
        ThemeService.SetColorScheme(value);
    }

    partial void OnSelectedBackdropChanged(string value)
    {
        ApplyBackdrop(value);
    }

    // --- Implementation ---

    private static void ApplyTypography(double size, string fontFamily)
    {
        var app = Application.Current;
        if (app == null) return;

        // Override the root font size/style so every TextBlock inherits it.
        app.Resources["ControlContentThemeFontSize"] = size;

        try
        {
            var family = new FontFamily(fontFamily);
            app.Resources["ContentControlThemeFontFamily"] = family;

            // Also set on every open window for immediate effect
            foreach (Window w in app.Windows)
            {
                w.FontSize = size;
                w.FontFamily = family;
            }
        }
        catch { /* invalid font name — ignore */ }
    }

    private static void ApplyScale(double percent)
    {
        var app = Application.Current;
        if (app?.MainWindow == null) return;

        var scale = percent / 100.0;
        // Apply a LayoutTransform to the root visual of each window.
        foreach (Window w in app.Windows)
        {
            if (w.Content is FrameworkElement root)
            {
                root.LayoutTransform = new ScaleTransform(scale, scale);
            }
        }
    }

    private static void ApplyBackdrop(string name)
    {
        var app = Application.Current;
        if (app == null) return;

        WindowBackdropType type = name switch
        {
            "Acrylic" => WindowBackdropType.Acrylic,
            "Tabbed"  => WindowBackdropType.Tabbed,
            "None"    => WindowBackdropType.None,
            _         => WindowBackdropType.Mica,
        };

        foreach (Window w in app.Windows)
        {
            if (w is FluentWindow fw)
            {
                fw.WindowBackdropType = type;
                // Force WPF-UI to re-apply the backdrop
                WindowBackgroundManager.UpdateBackground(fw, ThemeService.CurrentTheme, type);
            }
        }
    }

    private void ResetDefaults()
    {
        FontSize = DefaultFontSize;
        UiScale = DefaultScale;
        SelectedScheme = DefaultScheme;
        SelectedFont = DefaultFont;
        SelectedBackdrop = DefaultBackdrop;

        // GetSystemTheme() returns SystemTheme, not ApplicationTheme.
        // Map explicitly to avoid CS1503.
        var system = ApplicationThemeManager.GetSystemTheme();
        var theme = system == SystemTheme.Dark
            ? ApplicationTheme.Dark
            : ApplicationTheme.Light;

        ThemeService.SetTheme(theme);
        ThemeService.SetColorScheme(DefaultScheme);
    }
}
