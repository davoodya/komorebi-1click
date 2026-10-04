using System.Collections.ObjectModel;
using System.Text;
using System.Windows.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using KomorebiDashboard.Models;
using KomorebiDashboard.Services;
using KomorebiDashboard.Views;

namespace KomorebiDashboard.ViewModels;

/// <summary>
/// Base for the six tab ViewModels (ADR-0009 middle tier).
///
/// Holds no business logic: every button resolves its verb through
/// <see cref="VerbRegistry"/> and asks <see cref="ScriptService"/> to run it.
/// The Views bind to <see cref="Commands"/> and <see cref="Output"/> and hold no
/// logic of their own.
///
/// NO-LAG CONTRACT (ticket 11, priority 2 in ADR-0015: lag approaching zero)
///   Script output arrives on thread-pool callback threads, one call per line.
///   Appending each line straight to a bound property would mean one
///   PropertyChanged notification AND one layout pass per line: at a few
///   thousand lines the window stops responding, which is precisely the jank
///   this ticket exists to remove.
///
///   So lines are appended to <see cref="_pending"/> under a lock and flushed to
///   the UI by <see cref="FlushOutput"/>, which posts ONE dispatcher operation
///   for whatever accumulated since the last flush. The hop count is bounded by
///   the flush interval, not by the number of output lines, so a script printing
///   10,000 lines costs the UI the same handful of updates as one printing 10.
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
    /// The buttons for this tab, generated from the registry. There is exactly
    /// one constructor because Commands is derived from the tab name: a second
    /// constructor taking only the service would have to leave Commands unset.
    /// </summary>
    public ObservableCollection<VerbDefinition> Commands { get; }

    /// <summary>Live script output, bound to the output pane.</summary>
    [ObservableProperty]
    private string _output = "Ready.";

    /// <summary>One-line summary of the last run.</summary>
    [ObservableProperty]
    private string _status = "No command run yet.";

    /// <summary>True while a script is running, so buttons can be disabled.</summary>
    [ObservableProperty]
    // Names the generated COMMAND property, not the method: [RelayCommand]
    // produces RunVerbCommand, and the attribute is validated against the
    // members of this type rather than against the source-generation output.
    [NotifyCanExecuteChangedFor(nameof(RunVerbCommand))]
    [NotifyCanExecuteChangedFor(nameof(CancelCommand))]
    private bool _isBusy;

    /// <summary>Argument entered for verbs that take one, e.g. a transparency value.</summary>
    [ObservableProperty]
    private string _argument = string.Empty;

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
    }

    /// <summary>
    /// The single execution path. The GUI button and the CLI verb both end up
    /// here, which is what keeps them behaving identically.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanRun))]
    private async Task RunVerbAsync(string verb)
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
        Output = $"$ {def.Script}{(string.IsNullOrWhiteSpace(Argument) ? "" : " " + Argument.Trim())}";

        try
        {
            var args = SplitArguments(Argument);

            // onOutput is called from thread-pool threads, so it only buffers.
            var result = await Scripts.RunAsync(verb, args, BufferLine, token);

            FlushOutput(force: true);
            Status = result.Summary;
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

    private bool CanRun() => !IsBusy;

    /// <summary>Cancel is only meaningful mid-run.</summary>
    private bool CancelCanExecute() => IsBusy && _cts is not null;

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
    /// THE single dispatcher hop. One <see cref="Dispatcher.BeginInvoke(DispatcherPriority, Delegate)"/>
    /// per flush, carrying every line that accumulated since the last one — never
    /// one hop per line. That single call site is why the UI cannot be flooded
    /// no matter how chatty the script is.
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

    /// <summary>Runs on the UI thread. Appends and trims so a long run cannot
    /// grow the pane without bound.</summary>
    private void ApplyBatch(string batch)
    {
        const int MaxChars = 200_000;
        var combined = Output + batch;
        Output = combined.Length > MaxChars ? combined[^MaxChars..] : combined;
    }

    /// <summary>
    /// Split the argument box on whitespace, honouring simple double quotes so a
    /// path with spaces survives.
    /// </summary>
    private static IReadOnlyList<string> SplitArguments(string input)
    {
        if (string.IsNullOrWhiteSpace(input)) return Array.Empty<string>();

        var parts = new List<string>();
        var current = new System.Text.StringBuilder();
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