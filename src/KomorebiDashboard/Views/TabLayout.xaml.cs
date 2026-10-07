using System.Windows;
using System.Windows.Controls;

namespace KomorebiDashboard.Views;

/// <summary>
/// The standard tab body: a heading, a slot for the tab's rows, and the shared
/// console pane below.
///
/// WHY A ContentControl AND NOT A UserControl
///   A UserControl's content is its own markup, so a consumer supplying child
///   content would replace the whole body and the console pane would disappear.
///   As a ContentControl the consumer's rows land in the template's
///   ContentPresenter and everything else is fixed — which is what makes all
///   seven tabs share one layout.
///
/// The row heights are bound inside the template to <c>ContentRowHeight</c> and
/// <c>ConsoleRowHeight</c> on the tab's ViewModel (TabViewModelBase), so the
/// console's share of the tab comes from persisted settings rather than from a
/// fixed pixel count that is wrong at any other window size.
///
/// ShowConsole="False" is the way a tab that runs nothing opts out of the
/// console. It is handled here, on the control, rather than by a binding on the
/// tab's ViewModel, because the two tabs that need it (Customization and About)
/// are plain ObservableObjects and have no ConsoleRowHeight to bind: the binding
/// would fail silently and leave the row at its default 1*, which renders as an
/// empty console panel.
/// </summary>
public partial class TabLayout : ContentControl
{
    public TabLayout()
    {
        InitializeComponent();
    }

    /// <summary>Heading text, one per tab.</summary>
    public static readonly DependencyProperty PageTitleProperty =
        DependencyProperty.Register(
            nameof(PageTitle), typeof(string), typeof(TabLayout),
            new PropertyMetadata(string.Empty));

    /// <summary>One-sentence explanation under the heading.</summary>
    public static readonly DependencyProperty PageSubtitleProperty =
        DependencyProperty.Register(
            nameof(PageSubtitle), typeof(string), typeof(TabLayout),
            new PropertyMetadata(string.Empty));

    public string PageTitle
    {
        get => (string)GetValue(PageTitleProperty);
        set => SetValue(PageTitleProperty, value);
    }

    public string PageSubtitle
    {
        get => (string)GetValue(PageSubtitleProperty);
        set => SetValue(PageSubtitleProperty, value);
    }

    /// <summary>
    /// False removes the console pane and hands its share of the tab to the
    /// content row.
    ///
    /// Default true: a tab exists to run things, so the console is the normal
    /// case and opting out is the exception.
    /// </summary>
    public static readonly DependencyProperty ShowConsoleProperty =
        DependencyProperty.Register(
            nameof(ShowConsole), typeof(bool), typeof(TabLayout),
            new PropertyMetadata(true, OnShowConsoleChanged));

    public bool ShowConsole
    {
        get => (bool)GetValue(ShowConsoleProperty);
        set => SetValue(ShowConsoleProperty, value);
    }

    /// <summary>
    /// The template's parts do not exist until it is applied, so the property can
    /// be set before they do. ApplyTemplate covers both orders: it is a no-op when
    /// the template is already applied, and forces it when it is not.
    /// </summary>
    private static void OnShowConsoleChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var layout = (TabLayout)d;
        layout.ApplyTemplate();
        layout.ApplyConsoleVisibility();
    }

    /// <summary>
    /// Hide or restore the console row.
    ///
    /// The row height is pinned to zero as well as collapsing the pane: a star
    /// row with no content still claims its share of the grid, so collapsing the
    /// pane alone would leave a blank band exactly where the console used to be.
    ///
    /// The content row is set explicitly rather than left to the ViewModel
    /// binding, because a tab without a console has no ConsoleRowHeight to bind
    /// to. ClearValue removes the local value so the binding resumes — which is
    /// what lets a tab that gains the console back keep its configured share.
    /// </summary>
    private void ApplyConsoleVisibility()
    {
        if (Template?.FindName("PART_ConsoleRow", this) is not RowDefinition consoleRow) return;
        if (Template.FindName("PART_ContentRow", this) is not RowDefinition contentRow) return;
        if (Template.FindName("PART_Console", this) is not UIElement console) return;

        if (ShowConsole)
        {
            console.Visibility = Visibility.Visible;
            consoleRow.ClearValue(RowDefinition.HeightProperty);
            contentRow.ClearValue(RowDefinition.HeightProperty);
        }
        else
        {
            console.Visibility = Visibility.Collapsed;
            consoleRow.Height = new GridLength(0);
            contentRow.Height = new GridLength(1, GridUnitType.Star);
        }
    }
}