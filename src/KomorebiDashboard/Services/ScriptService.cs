using System.Diagnostics;
using System.IO;
using System.Text;
using KomorebiDashboard.Models;

namespace KomorebiDashboard.Services;

/// <summary>
/// The ONLY process-aware layer (ADR-0009). It resolves a verb to its script,
/// runs it, streams the output and hands back a <see cref="ScriptResult"/>.
///
/// It deliberately knows nothing about which tab a verb lives in and nothing
/// about the UI. That is what lets the CLI twin call the same method the GUI
/// button calls and get identical behaviour.
/// </summary>
public sealed class ScriptService
{
    /// <summary>Directory holding the .ps1 scripts — the repo's scripts\ folder.</summary>
    public string ScriptsDirectory { get; }

    public ScriptService(string scriptsDirectory)
    {
        ScriptsDirectory = scriptsDirectory;
    }

    /// <summary>
    /// Run the script behind <paramref name="verb"/>.
    /// </summary>
    /// <param name="verb">A registry verb name.</param>
    /// <param name="arguments">Extra arguments appended to the script call.</param>
    /// <param name="onOutput">Invoked as output arrives, for live streaming.</param>
    public async Task<ScriptResult> RunAsync(
        string verb,
        IReadOnlyList<string>? arguments = null,
        Action<string>? onOutput = null)
    {
        var def = VerbRegistry.Find(verb)
            ?? throw new ArgumentException($"Unknown verb '{verb}'.", nameof(verb));

        var scriptPath = Path.Combine(ScriptsDirectory, def.Script);
        if (!File.Exists(scriptPath))
        {
            // Returned rather than thrown: a missing script is a result the user
            // needs to SEE, not an exception the GUI should swallow silently.
            return new ScriptResult(
                ExitCode: 127,
                Output: $"Script not found: {scriptPath}",
                Duration: TimeSpan.Zero,
                Verb: verb);
        }

        var psi = new ProcessStartInfo
        {
            FileName = ResolvePowerShell(),
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = ScriptsDirectory,
        };

        // -NoProfile so a user's profile cannot change the outcome, and
        // -ExecutionPolicy Bypass so the machine's default policy does not
        // silently block the very scripts this app exists to run.
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");
        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(scriptPath);

        // Fixed arguments first (e.g. -Components yasb), then whatever the user
        // typed. Order matters: a script takes the last occurrence of a
        // parameter, so the user's value would win over the registry's.
        if (def.FixedArguments.Length > 0)
        {
            foreach (var fixedArg in def.FixedArguments.Split(' ', StringSplitOptions.RemoveEmptyEntries))
            {
                psi.ArgumentList.Add(fixedArg);
            }
        }

        foreach (var arg in arguments ?? Array.Empty<string>())
        {
            psi.ArgumentList.Add(arg);
        }

        var output = new StringBuilder();
        var gate = new object();
        var stopwatch = Stopwatch.StartNew();

        using var process = new Process { StartInfo = psi };

        void Capture(string line)
        {
            lock (gate) { output.AppendLine(line); }
            onOutput?.Invoke(line);
        }

        process.OutputDataReceived += (_, e) => { if (e.Data is not null) Capture(e.Data); };
        process.ErrorDataReceived  += (_, e) => { if (e.Data is not null) Capture(e.Data); };

        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        // WaitForExit() (no timeout) rather than WaitForExit(ms): the parameterless
        // overload is the one that guarantees the async output handlers have
        // flushed. With a timeout, output can be truncated.
        await process.WaitForExitAsync();
        stopwatch.Stop();

        return new ScriptResult(process.ExitCode, output.ToString(), stopwatch.Elapsed, verb);
    }

    /// <summary>
    /// Prefer PowerShell 7 and fall back to the in-box 5.1. A target machine
    /// that has never had PowerShell 7 installed still has 5.1, and the scripts
    /// are written to run on either.
    /// </summary>
    private static string ResolvePowerShell()
    {
        foreach (var candidate in new[] { "pwsh.exe", "powershell.exe" })
        {
            var path = Environment.GetEnvironmentVariable("PATH")!
                .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries)
                .Select(dir => Path.Combine(dir.Trim(), candidate))
                .FirstOrDefault(File.Exists);

            if (path is not null) return path;
        }

        // Last resort: the well-known system locations.
        var system = Environment.GetFolderPath(Environment.SpecialFolder.System);
        var fallback = Path.Combine(system, "WindowsPowerShell", "v1.0", "powershell.exe");
        if (File.Exists(fallback)) return fallback;

        throw new FileNotFoundException("Neither pwsh.exe nor powershell.exe could be located.");
    }
}