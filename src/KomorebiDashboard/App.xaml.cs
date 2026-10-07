using System.IO;
using System.Windows;
using KomorebiDashboard.Services;

namespace KomorebiDashboard;

/// <summary>
/// Entry point for BOTH surfaces (ADR-0013). The GUI and the CLI twin are the
/// same executable: a verb on the command line dispatches through the same
/// registry and the same <see cref="ScriptService"/> the buttons use, so the two
/// cannot behave differently. Only the presentation differs.
///
/// NOTE ON ENTRY POINT: this class deliberately does NOT declare a Main. The
/// WPF SDK generates its own <c>App.g.cs</c> entry point for an ApplicationDefinition
/// (Application XAML + WinExe), and adding a second one fails the build with
/// CS0017. <see cref="OnStartup"/> is the supported hook instead; arguments are
/// read from <see cref="Environment.GetCommandLineArgs"/> rather than from
/// StartupEventArgs.Args, because the generated entry point takes none.
/// </summary>
public partial class App : Application
{
    /// <summary>Exit code for the whole process, set when running in CLI mode.</summary>
    private int _cliExitCode;

    /// <summary>
    /// Persisted user preferences, owned by <see cref="SettingsStore"/> so the
    /// seven tabs and the CLI twin all read the same instance rather than each
    /// keeping a copy that can drift.
    /// </summary>
    internal static DashboardSettings Settings => SettingsStore.Current;

    /// <summary>
    /// Process start time, used to report the real startup cost. ADR-0015 ranks
    /// "maximum speed" as priority 1 and this must be MEASURED, not assumed.
    ///
    /// <para>Deliberately seeded from <see cref="System.Diagnostics.Process"/>'s
    /// StartTime rather than from a stopwatch begun inside this class. A static
    /// field initializer runs on first touch of App, which is AFTER the CLR has
    /// already loaded WPF — so a stopwatch started there reports only the
    /// remainder and prints a confident, wrong "0 ms".</para>
    /// </summary>
    private static readonly DateTime ProcessStartUtc =
        System.Diagnostics.Process.GetCurrentProcess().StartTime.ToUniversalTime();

    /// <summary>
    /// async void is deliberate and required here. Blocking on
    /// RunCliAsync(...).GetAwaiter().GetResult() inside OnStartup starves the WPF
    /// dispatcher: the message loop has not started yet, so a Shutdown() issued
    /// from inside that block is never honoured and the process hangs forever
    /// after printing its output. Awaiting instead lets the dispatcher run, so
    /// Shutdown takes effect and the process actually exits.
    ///
    /// Note there is deliberately NO AttachConsole call here. A WinExe is a
    /// GUI-subsystem binary, but it still inherits the parent's stdout HANDLE, so
    /// Console.Out reaches a redirected pipe correctly. Calling AttachConsole
    /// rebinds stdout onto a freshly attached console and the output stops being
    /// captured entirely -- which is strictly worse than not calling it.
    /// </summary>
    protected override async void OnStartup(StartupEventArgs e)
    {
        // A crash log, installed before anything else can fail.
        //
        // A XAML error inside a template is NOT a build error: the template is
        // parsed when it is first instantiated, so a bad Setter inside a
        // ControlTemplate compiles cleanly and then kills the process on the
        // first render. Without this handler the only trace is a WER record with
        // no line number; with it, the exact XAML line is written to a file
        // beside the executable.
        InstallCrashLogging();

        var args = Environment.GetCommandLineArgs().Skip(1).ToArray();

        // CLI mode: a verb was supplied. Exit with the script's own exit code so
        // `dashboard status && dashboard restart-all` composes in a shell the way
        // any other tool would.
        if (args.Length > 0)
        {
            // Do not let WPF close the dispatcher as soon as the (never-shown)
            // main window is constructed; the explicit Shutdown below owns the
            // exit and carries the script's exit code.
            ShutdownMode = ShutdownMode.OnExplicitShutdown;

            _cliExitCode = await RunCliAsync(args);
            Shutdown(_cliExitCode);
            return;
        }

        base.OnStartup(e);

        // Load persisted settings BEFORE applying anything visual, so the first
        // frame the user sees is already their configuration rather than the
        // defaults repainting a moment later.
        SettingsStore.Load();

        // Theme, accent, typeface and scale FIRST, then show the window.
        // Applying them after Show() would make the user watch the default
        // palette repaint — a priority-2 (smoothness) regression caused by
        // priority-4 work.
        ThemeService.ApplyFromSettings(Settings);

        MainWindow = new MainWindow();
        MainWindow.Show();

        // Priority 1 is maximum speed, so the cost is reported rather than left
        // implicit — measured from process start, so the CLR/WPF load cost is
        // included rather than hidden.
        var startupMs = (int)(DateTime.UtcNow - ProcessStartUtc).TotalMilliseconds;
        Console.WriteLine($"[KomorebiDashboard] window ready in {startupMs} ms");
    }

    /// <summary>
    /// Write unhandled exceptions to a log beside the executable.
    ///
    /// WHY THIS EXISTS: a XAML fault inside a ControlTemplate is deferred to the
    /// moment the template is first applied, so it is invisible to the compiler.
    /// The process dies during the first layout pass and the only Windows-side
    /// evidence is a WER record that names no XAML line. The <see cref="Exception"/>
    /// raised by a <c>XamlParseException</c> carries the line and position, so
    /// catching it here turns an unattributable crash into a one-line diagnosis.
    /// </summary>
    private void InstallCrashLogging()
    {
        DispatcherUnhandledException += (_, args) =>
        {
            WriteCrashLog(args.Exception);

            // Handled = true keeps the process alive so the log is flushed and the
            // user sees a message instead of a silent disappearance.
            args.Handled = true;

            MessageBox.Show(
                "The Dashboard hit an unexpected error and could not continue." +
                Environment.NewLine + Environment.NewLine +
                args.Exception.Message + Environment.NewLine + Environment.NewLine +
                $"Details were written to:{Environment.NewLine}{CrashLogPath}",
                "Komorebi Dashboard",
                MessageBoxButton.OK,
                MessageBoxImage.Error);

            Current?.Shutdown(1);
        };

        // Failures on a worker thread do not reach DispatcherUnhandledException.
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
        {
            if (args.ExceptionObject is Exception ex) WriteCrashLog(ex);
        };
    }

    /// <summary>Where the crash log is written: beside the running executable.</summary>
    private static string CrashLogPath
    {
        get
        {
            try
            {
                var exe = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName;
                var dir = Path.GetDirectoryName(exe);
                if (!string.IsNullOrWhiteSpace(dir)) return Path.Combine(dir, "KomorebiDashboard.crash.log");
            }
            catch
            {
                // Falls through to the temp path below.
            }

            return Path.Combine(Path.GetTempPath(), "KomorebiDashboard.crash.log");
        }
    }

    private static void WriteCrashLog(Exception ex)
    {
        try
        {
            var sb = new System.Text.StringBuilder();

            sb.AppendLine($"--- {DateTime.Now:yyyy-MM-dd HH:mm:ss} ---");
            sb.AppendLine($"version: {typeof(App).Assembly.GetName().Version}");

            // Walk the whole InnerException chain. XamlParseException wraps the
            // useful XamlObjectWriterException, and it is the OUTER one that
            // carries LineNumber/LinePosition — so both halves are needed to
            // locate a fault: the line from here, the cause from the inner one.
            for (var e = ex; e is not null; e = e.InnerException)
            {
                sb.AppendLine($"{e.GetType().FullName}: {e.Message}");

                if (e is System.Windows.Markup.XamlParseException xaml)
                {
                    sb.AppendLine($"    XAML line {xaml.LineNumber}, position {xaml.LinePosition}");
                    if (xaml.BaseUri is not null) sb.AppendLine($"    base uri: {xaml.BaseUri}");
                }
            }

            sb.AppendLine(ex.ToString());

            File.AppendAllText(CrashLogPath, sb.ToString());
        }
        catch
        {
            // A failed crash log must never mask the original failure.
        }
    }

    private static async Task<int> RunCliAsync(string[] args)
    {
        // The CLI twin reads the same preferences (a verb is dispatched with the
        // same library the GUI uses), so the store is loaded here too.
        SettingsStore.Load();

        var parser = new CommandLineParser();
        var parsed = parser.Parse(args);

        if (parsed.Error is not null)
        {
            Console.Error.WriteLine(parsed.Error);
            return 2;
        }

        if (parsed.WantsHelp)
        {
            // Generated from the registry, so it can never drift from the verbs.
            Console.WriteLine(VerbRegistry.BuildHelp());
            return 0;
        }

        var service = new ScriptService(ScriptsLocator.Resolve());

        // Elevation gate for the CLI twin (ADR-0012). Checked BEFORE the script
        // is launched, and the refusal is loud: a non-zero exit plus a message
        // naming the verb. A silent no-op on an administrative verb would be a
        // data-loss-class surprise — the user would read "done" while nothing
        // happened.
        if (!ElevationService.CanRun(parsed.Verb!))
        {
            Console.Error.WriteLine(ElevationService.RefusalMessage(parsed.Verb!));
            return ElevationService.InsufficientPrivilegeExitCode;
        }

        // -TimeoutSeconds belongs to the CALLER, not to the script: it bounds
        // this invocation so a hung script cannot hang the shell that ran it.
        // Parsed here rather than forwarded, or the script would reject it.
        var timeout = ScriptService.DefaultTimeout;
        var forwarded = new List<string>(parsed.Arguments);
        for (var i = 0; i < forwarded.Count - 1; i++)
        {
            if (string.Equals(forwarded[i], "-TimeoutSeconds", StringComparison.OrdinalIgnoreCase))
            {
                if (int.TryParse(forwarded[i + 1], out var seconds) && seconds > 0)
                {
                    timeout = TimeSpan.FromSeconds(seconds);
                }
                forwarded.RemoveRange(i, 2);
                break;
            }
        }

        // Ctrl+C must cancel the child rather than leave it orphaned.
        using var cts = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };

        var result = await service.RunAsync(
            parsed.Verb!.Verb,
            forwarded,
            line => Console.Out.WriteLine(line),
            cts.Token,
            timeout);

        Console.Error.WriteLine(result.Summary);
        return result.ExitCode;
    }
}