using System.Windows;
using System.Windows.Media;
using KomorebiDashboard.Services;

namespace KomorebiDashboard.Views;

/// <summary>
/// The Customization tab's "custom accent" picker.
///
/// Mirrors <see cref="ConfirmDialog"/>: a static <c>Ask</c> that owns the
/// lifetime, reads a value out, and returns it — so the caller never handles a
/// window instance or wires up events.
///
/// The sliders and the hex box are two representations of one color and are kept
/// in sync in both directions. A <c>_syncing</c> flag breaks the feedback loop
/// that would otherwise run slider -> hex -> slider forever; it is the only state
/// this dialog keeps.
/// </summary>
public partial class ColorPickerDialog : Window
{
    /// <summary>Set while one control is writing the other, to stop the write echoing back.</summary>
    private bool _syncing;

    private ColorPickerDialog(Color initial)
    {
        InitializeComponent();

        // Assign the starting color through the channel values, then let
        // SyncFromChannels paint the preview and the hex box. Driving every
        // surface from the sliders means there is exactly one place that decides
        // what "the current color" is.
        RedSlider.Value = initial.R;
        GreenSlider.Value = initial.G;
        BlueSlider.Value = initial.B;

        SyncFromChannels();
    }

    /// <summary>The chosen color. Only meaningful when <c>Ask</c> returned true.</summary>
    public Color SelectedColor { get; private set; }

    /// <summary>
    /// Show the picker and return the user's choice.
    ///
    /// Returns false on Cancel or if the window is closed, so the caller can tell
    /// "picked a color" from "changed their mind" and leave the existing accent
    /// alone in the second case.
    /// </summary>
    public static bool Ask(Window? owner, Color initial, out Color chosen)
    {
        var dialog = new ColorPickerDialog(initial);
        if (owner is not null) dialog.Owner = owner;

        var accepted = dialog.ShowDialog() == true;
        chosen = dialog.SelectedColor;
        return accepted;
    }

    /// <summary>The color the sliders currently describe.</summary>
    private Color CurrentColor =>
        Color.FromRgb((byte)RedSlider.Value, (byte)GreenSlider.Value, (byte)BlueSlider.Value);

    /// <summary>Paint the preview, the channel readouts and the hex box from the sliders.</summary>
    private void SyncFromChannels()
    {
        if (_syncing) return;

        try
        {
            _syncing = true;

            var color = CurrentColor;

            RedValue.Text = color.R.ToString();
            GreenValue.Text = color.G.ToString();
            BlueValue.Text = color.B.ToString();

            var hex = ThemeService.ToHex(color);
            HexBox.Text = hex;

            PreviewBorder.Background = new SolidColorBrush(color);
            PreviewText.Text = hex;

            // The label sits on the color itself, so it needs a foreground that
            // stays readable on both a near-white and a near-black choice.
            // Rec. 601 luma is the cheap standard test for "is this light".
            var luma = (0.299 * color.R + 0.587 * color.G + 0.114 * color.B) / 255.0;
            PreviewText.Foreground = luma > 0.55 ? Brushes.Black : Brushes.White;
        }
        finally
        {
            _syncing = false;
        }
    }

    private void OnChannelChanged(object sender, RoutedPropertyChangedEventArgs<double> e) =>
        SyncFromChannels();

    /// <summary>
    /// Accept a typed hex value.
    ///
    /// Parsing is delegated to <see cref="ThemeService.TryParseHex"/> — the same
    /// parser used to restore a saved custom accent at startup — so a value that
    /// the picker accepts is a value that will survive a restart. Half-typed input
    /// ("#12") simply does not parse and is ignored, leaving the last valid color
    /// in place rather than throwing.
    /// </summary>
    private void OnHexChanged(object sender, System.Windows.Controls.TextChangedEventArgs e)
    {
        if (_syncing) return;
        if (!ThemeService.TryParseHex(HexBox.Text, out var parsed)) return;

        try
        {
            _syncing = true;
            RedSlider.Value = parsed.R;
            GreenSlider.Value = parsed.G;
            BlueSlider.Value = parsed.B;
        }
        finally
        {
            _syncing = false;
        }

        SyncFromChannels();
    }

    private void OnAccept(object sender, RoutedEventArgs e)
    {
        SelectedColor = CurrentColor;
        DialogResult = true;
    }

    private void OnCancel(object sender, RoutedEventArgs e) => DialogResult = false;
}