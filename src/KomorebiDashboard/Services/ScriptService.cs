using System.Diagnostics;
using System.IO;
using System.Text;
using KomorebiDashboard.Models;

namespace KomorebiDashboard.Services;

/// <summary>
/// The ONLY process-aware layer (ADR-0009). It resolves a verb to its script,
/// runs it OFF the UI thread, streams the output and hands back a
/// <see cref="ScriptResult"/>.
///
/// It deliberately knows nothing about which tab a verb lives in and nothing
/// about WPF. That is what lets the CLI twin call the same method the GUI
/// button calls and get identical behaviour.
///
/// THREADING CONTRACT (ticket 11)
///   1. No method here blocks. There is no <c>Wait()</c>, no <c>.Result</c> and
///      no <c>Task.Run</c>. Launching a process is I/O, so the already-async
///      <see cref="Process"/> APIs are used directly; wrapping them in
///      <c>Task.Run</c> would burn a thread-pool thread per run for nothing.
///   2. The async reads for stdout and stderr are started BEFORE
///      <see cref="Process.Start()"/>. A child that fills the 4 KB stdout pipe
///      blocks until someone reads it, so a reader attached after Start can
///      deadlock the child and hang the UI with it. This is the risk ADR-0015
///      registers as "Process stdout deadlock if streams are read after exit".
///   3. Output arrives on a thread-pool callback thread, NOT the UI thread. The
///      callback therefore only appends to a lock-guarded buffer; marshalling to
///      the UI is the ViewModel's job, batched into one dispatcher hop.
/// </summary>
public sealed class ScriptService
{
    /// <summary>Directory holding the .ps1 scripts — the repo's scripts\ folder.</summary>
    public string ScriptsDirectory { get; }

    /// <summary>
    /// Default wall-clock budget for one script. Long enough for the slowest
    /// real script (a full config export or a monitor recovery), short enough
    /// that a genuinely hung one cannot leave the UI spinning forever.
    /// </summary>
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(300);

    public ScriptService(string scriptsDirectory)
    {
        ScriptsDirectory = scriptsDirectory;
    }

    /// <summary>
    /// Run the script behind <paramref name="verb"/>.
    /// </summary>
    /// <param name="verb">A registry verb name.</param>
    /// <param name="arguments">Extra arguments appended to the script call.</param>
    /// <param name="onOutput">
    /// Invoked as output arrives, for live streaming. Called from a background
    /// thread, possibly concurrently for stdout and stderr, so an
    /// implementation must be thread-safe and must not touch the UI directly.
    /// </param>
    /// <param name="cancellationToken">Cancels the run and kills the process tree.</param>
    /// <param name="timeout">
    /// Wall-clock budget. <see cref="Timeout.InfiniteTimeSpan"/> disables it;
    /// <c>null</c> means <see cref="DefaultTimeout"/>.
    /// </param>
    public async Task<ScriptResult> RunAsync(
        string verb,
        IReadOnlyList<string>? arguments = null,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default,
        TimeSpan? timeout = null)
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

        var stdout = new StringBuilder();
        var stderr = new StringBuilder();
        var gate = new object();
        var stopwatch = Stopwatch.StartNew();

        using var process = new Process { StartInfo = psi };

        // --- threads are configured BEFORE the process starts --------------
        // EnableRaisingEvents is what makes Process raise OutputDataReceived and
        // ErrorDataReceived at all. Attached here, before Start, so there is no
        // window in which output is produced with nothing listening.
        process.OutputDataReceived += (_, e) => { if (e.Data is not null) Capture(stdout, e.Data); };
        process.ErrorDataReceived  += (_, e) => { if (e.Data is not null) Capture(stderr, e.Data); };
        process.EnableRaisingEvents = true;

        void Capture(StringBuilder sink, string line)
        {
            lock (gate) { sink.AppendLine(line); }
            // A throwing consumer (a closed window, a cancelled ViewModel) must
            // not take the process down with it, so the callback is isolated.
            try { onOutput?.Invoke(line); } catch { /* the run continues regardless */ }
        }

        // The async readers themselves are kicked off immediately after Start
        // and BEFORE anything is awaited on the process, so both pipes are
        // draining while the script is still producing.
        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        var budget = timeout ?? DefaultTimeout;
        using var timeoutCts = new CancellationTokenSource();
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCts.Token);

        var timedOut = false;
        if (budget != System.Threading.Timeout.InfiniteTimeSpan)
        {
            timeoutCts.CancelAfter(budget);
        }

        // Fires for BOTH a user cancel and the timeout. The flag distinguishes
        // them, because the user must not be told "cancelled" when the script
        // simply ran too long.
        linked.Token.Register(() =>
        {
            if (!timeoutCts.IsCancellationRequested) return;   // user's own cancel
            timedOut = true;
        });

        void KillTree()
        {
            try
            {
                if (!process.HasExited)
                {
                    // entireProcessTree: true is the point. Killing only the
                    // direct child leaves grandchildren alive holding the same
                    // pipe handles, so the read loop never completes and the
                    // "cancelled" run keeps the UI waiting anyway.
                    process.Kill(entireProcessTree: true);
                }
            }
            catch { /* already gone, or never started */ }
        }

        // Registering the kill BEFORE awaiting means a cancel that arrives at
        // any point in the run tears the tree down, including while we are
        // still waiting for the first line of output.
        using (linked.Token.Register(KillTree))
        {
            try
            {
                // WaitForExitAsync, not Task.WaitForAny(WaitForExit): the latter
                // burns a thread-pool thread and cannot observe cancellation.
                await process.WaitForExitAsync().ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                KillTree();
                // Give the kill a moment to land so WaitForExitAsync below can
                // observe the exit and the read loops can drain.
                await WaitForExitBoundedAsync(process, TimeSpan.FromSeconds(10)).ConfigureAwait(false);
            }
        }

        // Belt and braces: if the process somehow survived the cancel, do not
        // let it outlive the call.
        KillTree();

        stopwatch.Stop();

        // WaitForExitAsync() returns when the process has exited, but the async
        // output handlers may not have finished draining yet. The parameterless
        // WaitForExit() is the overload that guarantees the redirect streams are
        // complete, so it runs here, after the process is already dead and so
        // immediately that it cannot block.
        try { process.WaitForExit(); } catch { /* nothing to wait for */ }

        var cancelled = cancellationToken.IsCancellationRequested;
        var combined = stdout.ToString() + stderr.ToString();

        if (timedOut)
        {
            combined += $"{Environment.NewLine}[KomorebiDashboard] timed out after {budget.TotalSeconds:0.#}s; " +
                        "the script's process tree was killed.";
        }
        else if (cancelled)
        {
            combined += $"{Environment.NewLine}[KomorebiDashboard] cancelled by the user; " +
                        "the script's process tree was killed.";
        }

        return new ScriptResult(
            process.HasExited ? process.ExitCode : -1,
            combined,
            stopwatch.Elapsed,
            verb,
            stderr.ToString(),
            Cancelled: cancelled,
            TimedOut: timedOut);
    }

    /// <summary>
    /// Await the process exit without blocking and without an unbounded wait.
    /// Returns true when the process is confirmed dead.
    /// </summary>
    private static async Task<bool> WaitForExitBoundedAsync(Process process, TimeSpan bound)
    {
        try
        {
            await process.WaitForExitAsync().WaitAsync(bound).ConfigureAwait(false);
            return true;
        }
        catch (TimeoutException)
        {
            return false;
        }
        catch (OperationCanceledException)
        {
            return false;
        }
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