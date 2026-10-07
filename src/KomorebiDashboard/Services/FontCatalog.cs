using System.Windows.Media;

namespace KomorebiDashboard.Services;

/// <summary>
/// The Customization tab's font list, in two tiers.
///
/// WHY TIERS AT ALL
///   Enumerating <c>Fonts.SystemFontFamilies</c> is the single most expensive
///   call in this app: on a normal Windows install it is a few hundred families,
///   each of which WPF materializes lazily, and binding that list to a ComboBox
///   that is then opened or virtualized costs hundreds of milliseconds of UI
///   thread time. That is the "annoying lag when opening the Font Family list"
///   this design removes.
///
///   So the list opens with a fixed set of faces every Windows machine has, and
///   the full enumeration happens ONLY when the user explicitly asks for it by
///   picking the <see cref="AllFontsSentinel"/> entry — off the UI thread, once,
///   with the result cached for the rest of the session.
/// </summary>
public static class FontCatalog
{
    /// <summary>
    /// The "show every installed font" entry, always the LAST item in the list so
    /// its position is predictable.
    /// </summary>
    public const string AllFontsSentinel = "Custom (All Fonts)...";

    /// <summary>
    /// The monospaced subset of <see cref="Standard"/>, and the default source for
    /// the console pane. Defined BEFORE Standard and spliced into it, so the
    /// monospaced faces are listed exactly once and the two lists cannot drift
    /// apart.
    /// </summary>
    public static readonly IReadOnlyList<string> Monospaced =
    [
        "Cascadia Mono",
        "Cascadia Code",
        "Consolas",
        "Lucida Console",
        "Courier New",
    ];

    /// <summary>
    /// Tier 1. Faces shipped with every supported Windows version, grouped so the
    /// order is useful rather than alphabetical: the UI faces first (the ones a
    /// user actually wants for a dashboard), then the monospaced faces, then the
    /// document faces.
    /// </summary>
    public static readonly IReadOnlyList<string> Standard =
    [
        // Fluent / UI
        "Segoe UI",
        "Segoe UI Variable",
        "Calibri",
        "Tahoma",
        "Verdana",
        "Trebuchet MS",
        "Candara",
        "Corbel",

        // Monospaced — the console pane's fonts, from the single list above
        .. Monospaced,

        // Document
        "Georgia",
        "Times New Roman",
        "Palatino Linotype",
        "Book Antiqua",
        "Garamond",
        "Cambria",
        "Constantia",

        // Display
        "Comic Sans MS",
        "Impact",
        "Franklin Gothic Medium",
        "Arial",
    ];

    /// <summary>
    /// The tier-1 list followed by the sentinel for the CONSOLE pane: monospaced
    /// faces only, because a proportional face makes script output's columns
    /// drift.
    /// </summary>
    public static List<string> MonospacedWithSentinel()
    {
        var list = new List<string>(Monospaced) { AllFontsSentinel };
        return list;
    }

    private static List<string>? _allFonts;

    /// <summary>
    /// The tier-1 list followed by the sentinel. Cheap: no font enumeration.
    /// </summary>
    public static List<string> StandardWithSentinel()
    {
        var list = new List<string>(Standard) { AllFontsSentinel };
        return list;
    }

    /// <summary>
    /// Every installed family, sorted, computed once and cached.
    ///
    /// MUST be called off the UI thread — it is the expensive call. The result is
    /// cached on success only, so a failure does not permanently poison the cache
    /// with an incomplete list.
    /// </summary>
    public static List<string> AllInstalled()
    {
        if (_allFonts is not null) return _allFonts;

        var families = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var family in Fonts.SystemFontFamilies)
        {
            // A family's Source is its canonical name; a family can expose several
            // localized names, and Source is the one that resolves back to it.
            if (!string.IsNullOrWhiteSpace(family.Source)) families.Add(family.Source);
        }

        _allFonts = families.ToList();
        return _allFonts;
    }

    /// <summary>True when <paramref name="name"/> is a face WPF can resolve.</summary>
    public static bool IsInstalled(string name) =>
        !string.IsNullOrWhiteSpace(name) && AllInstalled().Contains(name, StringComparer.OrdinalIgnoreCase);
}