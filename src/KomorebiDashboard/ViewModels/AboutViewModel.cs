using System.Diagnostics;
using System.Reflection;
using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using KomorebiDashboard.Services;

namespace KomorebiDashboard.ViewModels;

/// <summary>
/// About tab: what this program is, which build is running, and where to find it
/// and its author.
///
/// Read-only by design. It has no RunRow and starts no script, so it is the only
/// tab with no console pane — everything it reports is discovered in-process
/// (assembly metadata, file paths) rather than by launching PowerShell.
/// </summary>
public sealed partial class AboutViewModel : ObservableObject
{
    /// <summary>Product name, as it appears in the header and in Windows' file properties.</summary>
    public string ProductName => "Komorebi Admin Dashboard";

    /// <summary>
    /// The running build's version.
    ///
    /// Informational version first: the csproj stamps it as
    /// <c>1.0.0+&lt;commit&gt;</c>, which is the only value that identifies the
    /// exact source a build came from. Falls back to the assembly version so a
    /// plain developer build prints something truthful instead of "unknown".
    /// </summary>
    public string Version
    {
        get
        {
            var assembly = Assembly.GetExecutingAssembly();

            var informational = assembly
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()
                ?.InformationalVersion;

            return string.IsNullOrWhiteSpace(informational)
                ? assembly.GetName().Version?.ToString(3) ?? "dev"
                : informational;
        }
    }

    /// <summary>
    /// Where the running executable lives.
    ///
    /// Reported rather than assumed: this is how a user (or a support request)
    /// finds out whether they launched the installed copy or a stray one from a
    /// download folder — the single most common cause of "the new version did not
    /// change anything".
    /// </summary>
    public string ExecutablePath
    {
        get
        {
            try
            {
                // MainModule's FileName is the real image path, whereas
                // Assembly.Location returns an empty string for a
                // single-file publish — which is exactly how this ships.
                return Process.GetCurrentProcess().MainModule?.FileName ?? "(unavailable)";
            }
            catch
            {
                return "(unavailable)";
            }
        }
    }

    /// <summary>The folder the scripts are being resolved from.</summary>
    public string ScriptsPath => ScriptsLocator.Resolve();

    /// <summary>Where settings.json is stored.</summary>
    public string SettingsPath => SettingsStore.FilePath;

    public string RuntimeDescription =>
        $".NET {Environment.Version} · {System.Runtime.InteropServices.RuntimeInformation.OSDescription}";

    /// <summary>What the Dashboard does, in one paragraph.</summary>
    public string Summary =>
        "An administration surface for the Komorebi, WHKD, YASB and AutoHotkey desktop stack: " +
        "each action in the GUI dispatches through the same registry and the same script runner " +
        "as the command line, so the two cannot behave differently.";

    public string Author => "Davood Yahay (DavoodSec)";

    public string AuthorUrl => "https://davoodya.ir";

    public string RepositoryUrl => "https://github.com/davoodya/komorebi-1click";

    public string WebsiteUrl => "https://davoodya.ir";

    [RelayCommand]
    private void OpenUrl(string? url)
    {
        if (string.IsNullOrWhiteSpace(url)) return;

        try
        {
            // UseShellExecute is required for a URL on .NET Core: without it,
            // Process.Start treats the string as an executable path and throws.
            Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true })?.Dispose();
        }
        catch
        {
            // Non-fatal: a missing browser association must not take the tab down.
        }
    }

    /// <summary>
    /// Reveal the folder holding the running executable, so the user can confirm
    /// which copy they launched and open the log or settings next to it.
    /// </summary>
    [RelayCommand]
    private void OpenExecutableFolder()
    {
        try
        {
            var dir = System.IO.Path.GetDirectoryName(ExecutablePath);
            if (string.IsNullOrWhiteSpace(dir) || !System.IO.Directory.Exists(dir)) return;

            Process.Start(new ProcessStartInfo { FileName = dir, UseShellExecute = true })?.Dispose();
        }
        catch
        {
            // Non-fatal, as above.
        }
    }

    [RelayCommand]
    private void CopyVersion()
    {
        try
        {
            Clipboard.SetText($"{ProductName} {Version}{Environment.NewLine}{ExecutablePath}");
        }
        catch
        {
            // The clipboard can be locked by another process; a failed copy is not
            // worth an error dialog.
        }
    }
}