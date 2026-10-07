using System.Collections.ObjectModel;
using System.Text;
using System.Windows;
using System.Windows.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using KomorebiDashboard.Models;
using KomorebiDashboard.Services;
using KomorebiDashboard.Views;

namespace KomorebiDashboard.ViewModels;

/// <summary>
/// Base for the tab ViewModels (ADR-0009 middle tier).
///
/// Holds no business logic: every button resolves its verb through
/// <see cref="VerbRegistry"/> and asks <see cref="ScriptService"/> to run it.
///
/// NO-LAG CONTRACT (ticket 11, priority 2 in ADR-0015: lag approaching zero)
///   Script output arrives on thread-pool callback threads, one call per line.
///   Appending each line straight to a bound property would mean one
///   PropertyChanged notification AND one layout pass per line, so at a few
///   thousand lines the window stops responding — precisely the jank ticket 11
///   exists to remove.
///
///   Lines are therefore appended to <see cref="_pending"/> under a lock and
///   flushed by <see cref="FlushOutput"/>, which posts ONE dispatcher operation
///   per flush carrying whatever accumulated. Dispatcher hops are bounded by the
///   flush interval, not by the line count, so a script printing 10,000 lines
///   costs the UI the same handful of updates as one printing 10.
/// </summary>
public abstract partial class TabViewModelBase : ObservableObject
{
    /// <summary>
    /// How often the output pane is refreshed while a script streams. ~20 Hz is
    /// fast enough to look live and slow enough that the UI is never the
    /// bottleneck. Deliberately not "per line".
    /// </summary>
    private static readonly TimeSpan OutputFlushInterval = TimeSpan.FromMilliseconds(50);

    private readonly Dispatcher _dispatcher;
    private readonly object _pendingGate = new();
    private readonly StringBuilder _pending = new();

    private CancellationTokenSource? _cts;
    private DateTime _lastFlushUtc = DateTime.MinValue;

    protected readonly ScriptService Scripts;

    /// <summary>
    /// The rows for this tab, generated from the registry. There is exactly one
    /// constructor because Rows is derived from the tab name: a second
    /// constructor taking only the service would have to leave it unset.
    ///
    /// Each row owns its own value box (<see cref="VerbRow.Argument"/>), and
    /// <see cref="Commands"/> exposes the same registry entries for callers that
    /// only need the verb metadata. Suppressed rows (<c>RenderInGui: false</c>)
    /// appear in Commands but not in Rows.
    /// </summary>
    public ObservableCollection<VerbRow> Rows { get; }

    /// <summary>The registry entries for this tab, including suppressed rows.</summary>
    public ObservableCollection<VerbDefinition> Commands { get; }

    /// <summary>Live script output, bound to the console pane.</summary>
    [ObservableProperty]
    private string _output = string.Empty;

    /// <summary>One-line summary of the last run.</summary>
    [ObservableProperty]
    private string _status = "Ready.";

    /// <summary>True while a script is running, so buttons can be disabled.</summary>
    [ObservableProperty]
    // Names the generated COMMAND property, not the method: [RelayCommand]
    // produces RunVerbCommand, and the attribute is validated against the
    // members of this type rather than against the source-generation output.
    [NotifyCanExecuteChangedFor(nameof(RunVerbCommand))]
    [NotifyCanExecuteChangedFor(nameof(RunRowCommand))]
    [NotifyCanExecuteChangedFor(nameof(CancelCommand))]
    [NotifyCanExecuteChangedFor(nameof(ClearOutputCommand))]
    private bool _isBusy;

    /// <summary>Argument entered for verbs that take one, e.g. a transparency value.</summary>
    [ObservableProperty]
    private string _argument = string.Empty;

    /// <summary>
    /// Height of the console row as a star weight, so the console takes its share
    /// of the tab and the settings panes take the rest. Exposed as a
    /// <see cref="GridLength"/> so the view binds it directly — a percent value
    /// would need a converter for no benefit.
    ///
    /// The share comes from <see cref="SettingsStore"/> (default 25%), which is
    /// what fixes the previous layout where a fixed 200px pane consumed most of
    /// the window on a short one.
    ///
    /// Settable and observable rather than computed once in the constructor,
    /// because the console's drag grip changes it while the window is open.
    /// </summary>
    [ObservableProperty]
    private GridLength _consoleRowHeight;

    /// <summary>Height of the settings row: whatever is left after the console.</summary>
    [ObservableProperty]
    private GridLength _contentRowHeight;

    /// <summary>Console summary shown in the status bar, e.g. "25% · 12 lines".</summary>
    [ObservableProperty]
    private string _consoleInfo = string.Empty;

    /// <summary>
    /// Every live tab ViewModel, so a change made in one tab (dragging the
    /// console's grip, moving the share slider) can reach the others.
    ///
    /// Weak references, because the ViewModels are created by the shell and have
    /// no other owner: a strong list would turn every tab ever opened into a
    /// permanent leak. <see cref="RefreshConsoleShare"/> compacts the list as it
    /// sweeps, so dead entries are cleared on the next change rather than needing
    /// an unsubscribe.
    /// </summary>
    private static readonly List<WeakReference<TabViewModelBase>> LiveInstances = new();

    /// <summary>
    /// Set the console share on this ViewModel and on every other live tab.
    ///
    /// The share is global (one <c>ConsolePercent</c> in settings, one console
    /// height everywhere), so leaving the other tabs at the old star weight would
    /// make the console jump the moment the user switched tabs.
    /// </summary>
    public static void RefreshConsoleShare(double percent)
    {
        percent = Math.Clamp(percent, 10, 60);

        lock (LiveInstances)
        {
            for (var i = LiveInstances.Count - 1; i >= 0; i--)
            {
                if (LiveInstances[i].TryGetTarget(out var vm)) vm.ApplyConsoleShare(percent);
                else LiveInstances.RemoveAt(i);
            }
        }
    }

    /// <summary>
    /// Commit a share that was applied live. Called once at the end of a drag
    /// rather than per mouse-move, because <see cref="RefreshConsoleShare"/> runs
    /// on every move and writing settings each time would mean hundreds of file
    /// writes per drag.
    /// </summary>
    public static void PersistConsoleShare(double percent)
    {
        SettingsStore.Current.ConsolePercent = Math.Clamp(percent, 10, 60);
        SettingsStore.Save();
    }

    /// <summary>Apply a share to this ViewModel's two row heights and the status line.</summary>
    private void ApplyConsoleShare(double percent)
    {
        ConsoleRowHeight = new GridLength(percent, GridUnitType.Star);
        ContentRowHeight = new GridLength(100 - percent, GridUnitType.Star);
        UpdateConsoleInfo();
    }

    /// <summary>
    /// No-argument constructor for the design-time surface and for tests. The
    /// dispatcher falls back to the current thread's, which is correct when the
    /// ViewModel is exercised off a UI thread in a test.
    /// </summary>
    protected TabViewModelBase(ScriptService scripts, string tab)
        : this(scripts, tab, Dispatcher.CurrentDispatcher)
    {
    }

    protected TabViewModelBase(ScriptService scripts, string tab, Dispatcher dispatcher)
    {
        Scripts = scripts;
        _dispatcher = dispatcher;
        Commands = new ObservableCollection<VerbDefinition>(VerbRegistry.ForTab(tab));
        Rows = new ObservableCollection<VerbRow>(
            VerbRegistry.RowsForTab(tab).Select(d => new VerbRow(d)));

        var consolePercent = Math.Clamp(
            SettingsStore.Current.ConsolePercent,
            10,
            60);

        ConsoleRowHeight = new GridLength(consolePercent, GridUnitType.Star);
        ContentRowHeight = new GridLength(100 - consolePercent, GridUnitType.Star);
        ConsoleInfo = $"console {consolePercent:0}%";

        // Registered so an app-wide change (the console's drag grip, the share
        // slider) reaches this tab too. See LiveInstances.
        lock (LiveInstances) LiveInstances.Add(new WeakReference<TabViewModelBase>(this));
    }

    // ---------------------------------------------------------------------
    // Running a verb
    // ---------------------------------------------------------------------

    /// <summary>
    /// The single execution path. The GUI button and the CLI verb both end up
    /// here, which is what keeps them behaving identically.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanRun))]
    private async Task RunVerbAsync(string? verb)
    {
        if (string.IsNullOrWhiteSpace(verb)) return;
        await RunVerbCoreAsync(verb, SplitArguments(Argument));
    }

    /// <summary>
    /// Run one row, taking the arguments from THAT row and only that row.
    ///
    /// Rows cannot share a value: the verb's own arguments are always present,
    /// and anything the user typed is appended as the extra value the verb's
    /// last parameter accepts. For a verb whose arguments are entirely fixed
    /// (a switch, or a ValidateSet already pinned by FixedArguments) the box is
    /// hidden and nothing is appended.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanRun))]
    private async Task RunRowAsync(VerbRow? row)
    {
        if (row is null) return;

        var arguments = new List<string>();
        if (row.AcceptsUserArguments) arguments.AddRange(SplitArguments(row.Argument));

        await RunVerbCoreAsync(row.Verb, arguments);
    }

    /// <summary>
    /// Run a verb with arguments the ViewModel supplies rather than the shared
    /// argument box. Used by rows whose argument is a fixed choice (startup
    /// install/uninstall, AHK enabled/disabled) so a typo in a free-text box
    /// cannot produce a call the script will reject.
    /// </summary>
    protected async Task RunVerbCoreAsync(string verb, IReadOnlyList<string> arguments)
    {
        var def = VerbRegistry.Find(verb);
        if (def is null) { Status = $"Unknown verb '{verb}'."; return; }

        // Elevation gate (ADR-0012), BEFORE anything is started. Per-operation,
        // not global: read-only and per-user verbs are unaffected.
        if (!ElevationService.CanRun(def))
        {
            if (!ElevationPrompt.TryPrompt(ElevationService.BuildElevationPrompt()))
            {
                Status = $"{verb} needs Administrator. Nothing was changed.";
                Output = ElevationService.RefusalMessage(def);
                return;
            }
        }

        // A fresh CTS per run: reusing one means a second run inherits the first
        // run's cancelled token and can never start.
        _cts?.Dispose();
        _cts = new CancellationTokenSource();
        var token = _cts.Token;

        IsBusy = true;
        Output = $"$ {def.Script}{(arguments.Count == 0 ? "" : " " + string.Join(' ', arguments))}{Environment.NewLine}";

        try
        {
            // onOutput is called from thread-pool threads, so it only buffers.
            var result = await Scripts.RunAsync(verb, arguments, BufferLine, token);

            FlushOutput(force: true);
            Status = result.Summary;
            UpdateConsoleInfo();
            OnVerbCompleted(def.Verb);
        }
        catch (OperationCanceledException)
        {
            // ScriptService normally converts a cancel into a result; this is the
            // belt-and-braces path for a cancel racing process setup.
            FlushOutput(force: true);
            Status = $"{verb} cancelled.";
        }
        catch (Exception ex)
        {
            // A failure here is the user's problem to see, never to swallow.
            FlushOutput(force: true);
            Status = $"{verb} threw: {ex.Message}";
        }
        finally
        {
            IsBusy = false;
            _cts?.Dispose();
            _cts = null;
        }
    }

    /// <summary>
    /// Called after a verb has finished successfully, so a tab can refresh state
    /// that the script just changed underneath it (the AutoHotkey tab re-reads
    /// ahk-state.json). Default: nothing to do.
    ///
    /// Deliberately NOT called on failure or cancellation: a script that did not
    /// complete did not change anything, and refreshing would then show a state the
    /// system is not in.
    /// </summary>
    protected virtual void OnVerbCompleted(string verb)
    {
    }

    /// <summary>
    /// Cancel the running script. Enabled only while busy, so it cannot be
    /// clicked into a no-op state. The tree kill itself lives in
    /// <see cref="ScriptService"/>; this only signals and reports.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CancelCanExecute))]
    private void Cancel()
    {
        if (_cts is null) return;

        Status = "Cancelling...";
        try { _cts.Cancel(); } catch (ObjectDisposedException) { /* already finished */ }
    }

    /// <summary>Empty the console pane. Available while busy, since a long run is
    /// exactly when the user wants to drop the noise that came before.</summary>
    [RelayCommand(CanExecute = nameof(CanClearOutput))]
    private void ClearOutput()
    {
        Output = string.Empty;
        UpdateConsoleInfo();
        Status = "Console cleared.";
    }

    private bool CanRun() => !IsBusy;

    /// <summary>Cancel is only meaningful mid-run.</summary>
    private bool CancelCanExecute() => IsBusy && _cts is not null;

    private bool CanClearOutput() => Output.Length > 0;

    /// <summary>Recompute the status-bar console summary.</summary>
    private void UpdateConsoleInfo()
    {
        var lines = 1;
        foreach (var ch in Output) if (ch == '\n') lines++;

        ConsoleInfo = Output.Length == 0
            ? $"console {SettingsStore.Current.ConsolePercent:0}%"
            : $"console {SettingsStore.Current.ConsolePercent:0}% · {lines} lines";
    }

    // ---------------------------------------------------------------------
    // Console plumbing for derived ViewModels
    // ---------------------------------------------------------------------

    /// <summary>
    /// Begin a console section with the command being run, replacing whatever was
    /// there. Runs on the UI thread (the caller is the command handler), so it
    /// assigns the bound property directly.
    /// </summary>
    protected void ConsoleBegin(string firstLine)
    {
        Output = firstLine + Environment.NewLine;
        UpdateConsoleInfo();
    }

    /// <summary>
    /// Append one line to the console from ANY thread, through the same buffered
    /// path the script output uses. Exposed to derived ViewModels so a tab that
    /// drives several verbs (AutoHotkey Scripts) cannot invent a second flush
    /// mechanism — one batched dispatcher hop is the whole no-lag contract.
    /// </summary>
    protected void ConsoleWriteLine(string line) => BufferLine(line);

    /// <summary>Flush anything buffered, immediately.</summary>
    protected void FlushConsole() => FlushOutput(force: true);

    /// <summary>
    /// Write one informational line to this tab's console, from outside this
    /// ViewModel.
    ///
    /// Exists for the shell's app-wide actions (the header's accent toggle) and
    /// for any future caller that is not one of this tab's own commands. Same
    /// buffered path as everything else, so it cannot introduce a second flush
    /// mechanism — that single path is the no-lag contract.
    /// </summary>
    public void WriteLine(string line)
    {
        if (string.IsNullOrEmpty(line)) return;

        ConsoleWriteLine(line);
        FlushConsole();
    }

    /// <summary>
    /// Called from a thread-pool thread for EVERY output line. Deliberately does
    /// the minimum: append under a lock, and occasionally ask for a flush.
    /// </summary>
    private void BufferLine(string line)
    {
        bool dueForFlush;

        lock (_pendingGate)
        {
            _pending.AppendLine(line);
            dueForFlush = (DateTime.UtcNow - _lastFlushUtc) >= OutputFlushInterval;
        }

        if (dueForFlush) FlushOutput(force: false);
    }

    /// <summary>
    /// THE single dispatcher hop. One <c>BeginInvoke</c> per flush, carrying every
    /// line that accumulated since the last one — never one hop per line. That
    /// single call site is why the UI cannot be flooded no matter how chatty the
    /// script is.
    /// </summary>
    private void FlushOutput(bool force)
    {
        string batch;

        lock (_pendingGate)
        {
            if (_pending.Length == 0) return;
            if (!force && (DateTime.UtcNow - _lastFlushUtc) < OutputFlushInterval) return;

            batch = _pending.ToString();
            _pending.Clear();
            _lastFlushUtc = DateTime.UtcNow;
        }

        if (_dispatcher.CheckAccess())
        {
            ApplyBatch(batch);
            return;
        }

        _dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() => ApplyBatch(batch)));
    }

    /// <summary>
    /// Runs on the UI thread. Appends and trims so a long run cannot grow the pane
    /// without bound. Trimming is O(n) on the string but happens at most once per
    /// flush, and only past the cap.
    /// </summary>
    private void ApplyBatch(string batch)
    {
        const int MaxChars = 200_000;

        var combined = Output + batch;
        if (combined.Length > MaxChars)
        {
            // Trim on a line boundary so the pane never starts mid-line. The two
            // branches are separate statements rather than one conditional
            // expression, because a start index and a Range are different types.
            var cut = combined.IndexOf('\n', combined.Length - MaxChars);
            combined = cut >= 0
                ? combined[(cut + 1)..]
                : combined[^MaxChars..];
        }

        Output = combined;
        UpdateConsoleInfo();
    }

    /// <summary>
    /// Split the argument box on whitespace, honouring simple double quotes so a
    /// path with spaces survives.
    /// </summary>
    protected static IReadOnlyList<string> SplitArguments(string input)
    {
        if (string.IsNullOrWhiteSpace(input)) return Array.Empty<string>();

        var parts = new List<string>();
        var current = new StringBuilder();
        var inQuotes = false;

        foreach (var ch in input.Trim())
        {
            if (ch == '"') { inQuotes = !inQuotes; continue; }
            if (char.IsWhiteSpace(ch) && !inQuotes)
            {
                if (current.Length > 0) { parts.Add(current.ToString()); current.Clear(); }
                continue;
            }
            current.Append(ch);
        }

        if (current.Length > 0) parts.Add(current.ToString());
        return parts;
    }
}