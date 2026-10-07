using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using KomorebiDashboard.Services;

namespace KomorebiDashboard.Views;

/// <summary>
/// The shared script-output pane (see ConsolePane.xaml). Hosted by every tab so
/// the console looks and behaves identically everywhere.
///
/// Two behaviours live in code-behind: auto-scroll, and the drag-to-resize
/// grip. Both need logic a trigger cannot express — auto-scroll has to test the
/// current scroll offset, and the grip has to write a new share back to settings.
/// </summary>
public partial class ConsolePane : UserControl
{
    /// <summary>
    /// Distance from the end, in device-independent pixels, still treated as
    /// "at the end". One line of the 12px console is ~16px, so this keeps one
    /// line of slack — enough that the user does not have to hit the exact
    /// bottom to keep following the output.
    /// </summary>
    private const double AtEndThreshold = 18;

    /// <summary>
    /// Bounds for the console share, matching the slider in the Customization and
    /// Settings tabs and <c>SettingsStore.Normalize</c>. Enforced here too,
    /// because the grip is a second way to set the value and it must not be able
    /// to persist something the sliders would refuse.
    /// </summary>
    private const double MinPercent = 10;
    private const double MaxPercent = 60;

    /// <summary>
    /// Set while a drag is writing the share, so the resulting layout change does
    /// not feed back into the drag's own reference measurement.
    /// </summary>
    private bool _resizing;

    public ConsolePane()
    {
        InitializeComponent();
    }

    /// <summary>
    /// Follow the output only when the reader has not scrolled back.
    ///
    /// Unconditional ScrollToEnd would make it impossible to read a line from the
    /// middle of a running script: every batch would yank the view to the bottom.
    /// Reading the scroll offset first is what makes "follow unless the user is
    /// reading history" work.
    /// </summary>
    private void OnTextChanged(object sender, TextChangedEventArgs e)
    {
        if (sender is not TextBox box) return;

        var scroller = box.Template?.FindName("PART_ContentHost", box) as ScrollViewer;
        if (scroller is null)
        {
            // The template has not been applied yet (first render pass). Nothing
            // to preserve, and the next change will scroll anyway.
            box.ScrollToEnd();
            return;
        }

        var atEnd = scroller.VerticalOffset >= scroller.ScrollableHeight - AtEndThreshold;
        if (atEnd) box.ScrollToEnd();
    }

    // ---------------------------------------------------------------------
    // Drag to resize
    // ---------------------------------------------------------------------

    /// <summary>
    /// Begin a resize drag and capture the measurements it is relative to.
    ///
    /// The starting share is read from the ViewModel's own
    /// <c>ConsoleInfo</c>-consistent source (<see cref="SettingsStore"/>) rather
    /// than from the star weight: a star value is relative to the whole grid, so
    /// converting it back to a percentage would drift as the window is resized.
    /// </summary>
    private void OnResizeStart(object sender, MouseButtonEventArgs e)
    {
        if (DataContext is not ViewModels.TabViewModelBase) return;

        _resizing = true;
        ResizeGrip.CaptureMouse();
        e.Handled = true;
    }

    /// <summary>
    /// Track the pointer and write the new share as a percentage of the tab.
    ///
    /// The percentage is measured against the CONSOLE PANE's own height, which is
    /// what the grip is directly changing, so the drag feels 1:1 with the pointer
    /// instead of accelerating away from it.
    /// </summary>
    private void OnResizeMove(object sender, MouseEventArgs e)
    {
        if (!_resizing) return;
        if (DataContext is not ViewModels.TabViewModelBase) return;

        var panel = ResizeGrip.Parent as FrameworkElement;
        if (panel is null || panel.ActualHeight <= 0) return;

        // How far the pointer has moved UP from the grip's starting position,
        // as a share of the panel: dragging up grows the console.
        var current = e.GetPosition(panel).Y;
        var share = (panel.ActualHeight - current) / panel.ActualHeight * 100.0;

        share = Math.Clamp(share, MinPercent, MaxPercent);

        SettingsStore.Current.ConsolePercent = share;
        SettingsStore.Save();

        // Reported through the ViewModel so the status line and every open tab
        // agree on the new value; writing the setting alone would leave the
        // on-screen percentages stale until the next rebuild.
        ViewModels.TabViewModelBase.RefreshConsoleShare(share);
    }

    private void OnResizeEnd(object sender, MouseButtonEventArgs e)
    {
        if (!_resizing) return;

        _resizing = false;
        ResizeGrip.ReleaseMouseCapture();
        ViewModels.TabViewModelBase.PersistConsoleShare(SettingsStore.Current.ConsolePercent);
        e.Handled = true;
    }
}