using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace KomorebiDashboard.Converters;

/// <summary>
/// True to Visible, false to Collapsed.
///
/// WHY Collapsed AND NOT Hidden: a Hidden row still occupies its place in the
/// StackPanel, so a tab whose value boxes are hidden would keep an empty gap the
/// height of a text box next to every button. Collapsed is what makes the layout
/// collapse onto the controls that are actually there.
/// </summary>
[ValueConversion(typeof(bool), typeof(Visibility))]
public sealed class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is true ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is Visibility.Visible;
}

/// <summary>
/// True to Collapsed, false to Visible — for a control that must be hidden while
/// something else is shown.
/// </summary>
[ValueConversion(typeof(bool), typeof(Visibility))]
public sealed class InverseBoolToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is true ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is not Visibility.Visible;
}

/// <summary>
/// Non-empty string to Visible. An empty string is the natural "nothing to say"
/// value for a status or an error, and every such field must disappear rather
/// than render as a blank line.
/// </summary>
[ValueConversion(typeof(string), typeof(Visibility))]
public sealed class StringToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        string.IsNullOrWhiteSpace(value as string) ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}