using System.IO;

namespace KomorebiDashboard.Services;

/// <summary>
/// Finds the <c>scripts/</c> directory the Dashboard drives.
/// </summary>
/// <remarks>
/// WHY THIS EXISTS AS ITS OWN TYPE (ticket 13, defect D21)
///
/// The scripts live at <c>&lt;repo&gt;\scripts</c> in development and beside the
/// executable in a shipped install. Two callers need that path — the GUI
/// (<c>MainWindow</c>) and the CLI twin (<c>App.OnStartup</c>) — and both used to
/// carry their own private copy of the probing logic.
///
/// Two copies of path logic is one too many, and it already cost a bug: ticket 13
/// added <c>RuntimeIdentifier=win-x64</c> to the csproj, which pushes
/// <c>dotnet build</c> output one directory deeper
/// (<c>bin\Release\net8.0-windows\win-x64\</c>). A probe written as a fixed
/// chain of <c>..\..\..\..\..\</c> segments was calibrated to the OLD depth, so
/// it overshot and every verb failed with exit 127 — the scripts directory
/// resolved, but to somewhere with no <c>kill-all.ps1</c> in it. Ticket 12's
/// suite caught it as "chatty verb exits 0" failing.
///
/// The fix is not to add one more <c>..\</c>. It is to walk UP until the marker
/// file is found, bounded, so the answer does not depend on how many
/// intermediate folders the SDK inserted this time.
///
/// The marker is <c>kill-all.ps1</c>: a file the registry already depends on, so
/// a directory that contains it is unambiguously the real scripts directory.
/// </remarks>
public static class ScriptsLocator
{
    /// <summary>The file that proves a directory really is the scripts directory.</summary>
    private const string Marker = "kill-all.ps1";

    /// <summary>How far up to walk. Generous, but bounded so a missing scripts
    /// directory cannot turn into an unbounded walk to the drive root.</summary>
    private const int MaxDepth = 10;

    /// <summary>
    /// Resolve the scripts directory, or return a best-effort path when none is
    /// found.
    /// </summary>
    /// <remarks>
    /// The fallback is deliberately a path that does NOT exist. ScriptService
    /// then reports "script not found" per verb with the offending path, which
    /// is diagnosable from the UI itself. Returning a plausible-but-wrong
    /// existing directory would instead produce a confusing "file not found"
    /// for every verb with no hint about where it looked.
    /// </remarks>
    public static string Resolve()
    {
        var baseDirectory = AppContext.BaseDirectory;

        // 1. Shipped layout: scripts\ beside the executable. Checked first
        //    because in a real install this is the only layout that exists.
        var beside = Path.Combine(baseDirectory, "scripts");
        if (IsScriptsDirectory(beside)) return Path.GetFullPath(beside);

        // 2. Development layout: walk up from the build output looking for the
        //    marker. Depth-independent by construction, so a RID folder, an
        //    extra configuration folder, or a future win-x86 matrix cannot
        //    break it the way a fixed ".." chain did.
        var directory = new DirectoryInfo(baseDirectory);
        for (var depth = 0; depth < MaxDepth && directory is not null; depth++, directory = directory.Parent)
        {
            var candidate = Path.Combine(directory.FullName, "scripts");
            if (IsScriptsDirectory(candidate)) return Path.GetFullPath(candidate);
        }

        return Path.GetFullPath(beside);
    }

    private static bool IsScriptsDirectory(string path) =>
        Directory.Exists(path) && File.Exists(Path.Combine(path, Marker));
}
