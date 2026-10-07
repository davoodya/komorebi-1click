using System.Windows.Controls;
using KomorebiDashboard.Services;

namespace KomorebiDashboard.Views;

/// <summary>
/// Customization tab code-behind.
///
/// The only logic here is the one thing a binding cannot express: re-selecting the
/// previous typeface after the "all fonts" enumeration rebuilds the list. WPF
/// clears <c>SelectedItem</c> when its item leaves the collection, so without this
/// the combo would sit blank and the user's choice would appear to have been lost.
/// </summary>
public partial class CustomizationView : UserControl
{
    public CustomizationView()
    {
        InitializeComponent();
    }

    /// <summary>
    /// Drop the sentinel back out of the selection immediately.
    ///
    /// The sentinel is an action ("show me everything installed"), not a face, so
    /// it must never remain the selected item. The ViewModel's own
    /// <c>OnSelectedFontChanged</c> treats seeing it as the trigger to load the
    /// full list; restoring a real face here keeps the combo honest while that
    /// load runs, and the ViewModel re-selects the persisted face once it lands.
    /// </summary>
    private void OnFontSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (sender is not ComboBox combo) return;
        if (combo.SelectedItem as string != FontCatalog.AllFontsSentinel) return;

        foreach (var item in combo.Items)
        {
            if (item as string == FontCatalog.AllFontsSentinel) continue;
            combo.SelectedItem = item;
            return;
        }
    }
}
