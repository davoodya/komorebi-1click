using System.IO;
using System.Windows;
using KomorebiDashboard.Services;

namespace KomorebiDashboard;

/// <summary>
/// Entry point for BOTH surfaces (ADR-0013). The GUI and the CLI twin are the
/// same executable: a verb on the command line dispatches through the same
/// registry and the same <c>ScriptService</c> the buttons use, so the two cannot
/// behave differently. Only the presentation differs.
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
        MainWindow = new MainWindow();
        MainWindow.Show();
    }

    private static async Task<int> RunCliAsync(string[] args)
    {
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

        var service = new ScriptService(ResolveScriptsDirectory());
        var result = await service.RunAsync(
            parsed.Verb!.Verb,
            parsed.Arguments,
            line => Console.Out.WriteLine(line));

        Console.Error.WriteLine(result.Summary);
        return result.ExitCode;
    }

    /// <summary>
    /// Mirrors MainWindow's probing so the CLI twin finds the scripts in both the
    /// development and the shipped layout.
    /// </summary>
    private static string ResolveScriptsDirectory()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "scripts"),
            Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "scripts"),
            Path.Combine(AppContext.BaseDirectory, "..", "scripts"),
        };

        foreach (var candidate in candidates)
        {
            var full = Path.GetFullPath(candidate);
            if (Directory.Exists(full) && File.Exists(Path.Combine(full, "kill-all.ps1")))
            {
                return full;
            }
        }

        return Path.Combine(AppContext.BaseDirectory, "scripts");
    }
}