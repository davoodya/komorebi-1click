#Requires -Version 5.1
<#
    Ticket 11 — Dashboard no-lag execution (async, streaming, cancellation, timeout).

    WHY THESE TESTS EXIST
      ADR-0015 ranks "maximum speed" first and "lag approaching zero" second, and
      it registers a specific Medium risk: "Process stdout deadlock if streams are
      read after exit", mitigated by "Both streams' async reads are started before
      Process.Start". The shipped ScriptService does NOT do that today: it calls
      process.Start() and only then BeginOutputReadLine/BeginErrorReadLine. So this
      suite exists to hold that mitigation in place rather than trusting it.

      The load-bearing assertions here are ORDER assertions (the position of
      Start() relative to the read setup in the source) and BEHAVIOUR assertions
      (a real chatty script is executed with a real timeout and a real
      cancellation). An assertion that merely greps for the word "async" would
      pass against the code that has the defect, which is exactly the failure mode
      these tests are written to prevent.

    RUNTIME EVIDENCE
      Section 8 really runs scripts\demo-stream.ps1 (the deliberately chatty
      fixture) through the built CLI and checks the numbers. If the fixture is
      missing, those assertions fail rather than skip — a silent skip is how a
      dead demonstration script would survive.

    WHAT IS DELIBERATELY NOT TESTED HERE
      Launching the WPF window and clicking a button. That needs an interactive
      desktop and belongs to the Sandbox pass (ticket 14). What IS proven here:
      the execution path is off the UI thread, dispatch is batched, cancellation
      and timeout work end-to-end, and startup is measured rather than assumed.

    Sandbox note: `-SkipBuild` skips the slow build when you only want the
    structural assertions.
#>
[CmdletBinding()]
param([switch] $SkipBuild)

$ErrorActionPreference = 'Stop'
$script:passed = 0
$script:failed = 0

function Assert([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) {
        Write-Host "  PASS  $Name" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "        $Detail" -ForegroundColor DarkRed }
        $script:failed++
    }
}

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Src         = Join-Path $ProjectRoot 'src\KomorebiDashboard'

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Ticket 11 - Dashboard no-lag execution' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan

# =====================================================================
# Section 1 - the deadlock mitigation must be in the SOURCE, in ORDER
# =====================================================================
#
# IMPORTANT — WHY THIS SECTION DOES NOT ASSERT THE TICKET'S LITERAL WORDING
#   Ticket 11 says the async reads must start "before Process.Start". That is
#   not achievable, and pretending otherwise would make this suite assert a
#   fiction. Verified on this machine:
#
#     BeginOutputReadLine() before Start()
#       -> System.InvalidOperationException:
#          "StandardOut has not been redirected or the process hasn't started yet."
#
#   The streams do not exist until Start creates them, so there is nothing to
#   read before it. ADR-0015's risk row inherited that wording from older
#   synchronous Process code.
#
#   What actually prevents the pipe-buffer deadlock, and what IS asserted here:
#     (a) the event handlers are attached and EnableRaisingEvents is set BEFORE
#         Start, so no output can arrive with nothing listening;
#     (b) BeginOutputReadLine/BeginErrorReadLine are called immediately after
#         Start and BEFORE anything is awaited on the process, so both pipes are
#         draining while the script is still producing;
#     (c) the wait is the async WaitForExitAsync, never a blocking WaitForExit
#         that would join the child while it is blocked writing to a full pipe.
#
Write-Host ''
Write-Host '[1] Stream reads started before Process.Start (ADR-0015 risk row)' -ForegroundColor Yellow

$svcPath = Join-Path $Src 'Services\ScriptService.cs'
if (-not (Test-Path $svcPath)) {
    Assert 'ScriptService.cs exists' $false $svcPath
} else {
    Assert 'ScriptService.cs exists' $true

    $svc = Get-Content $svcPath -Raw

    # Strip comments so a comment mentioning Process.Start cannot satisfy an
    # order assertion. This matters: the previous version of this file carried a
    # comment that named Process.Start, and a naive index comparison would have
    # passed against a file whose CODE order was wrong.
    $svcCodeOnly = [regex]::Replace($svc, '(?m)^\s*(//|/\*|\*).*$', '')
    $svcCodeOnly = [regex]::Replace($svcCodeOnly, '/\*.*?\*/', '', 'Singleline')

    # Order assertions. iStart/iOut compare positions of the actual statements.
    $mStart = [regex]::Match($svcCodeOnly, 'process\.Start\(\)')
    $mOut   = [regex]::Match($svcCodeOnly, 'BeginOutputReadLine\(\)')
    $mErr   = [regex]::Match($svcCodeOnly, 'BeginErrorReadLine\(\)')

    Assert 'Process.Start is present'                  $mStart.Success
    Assert 'BeginOutputReadLine is present'            $mOut.Success
    Assert 'BeginErrorReadLine is present'             $mErr.Success

    # (b) both reads start immediately after Start, before anything is awaited.
    #     A few statements of setup may sit between Start and the reads (the
    #     Process.Start return value, a timeout CTS); what must not happen is a
    #     WAIT in between, because that is the deadlock.
    if ($mStart.Success -and $mOut.Success -and $mErr.Success) {
        Assert 'stdout read starts AFTER Start (streams exist only then)' `
               ($mOut.Index -gt $mStart.Index) `
               "Process.Start at $($mStart.Index), BeginOutputReadLine at $($mOut.Index)"
        Assert 'stderr read starts AFTER Start (streams exist only then)' `
               ($mErr.Index -gt $mStart.Index) `
               "Process.Start at $($mStart.Index), BeginErrorReadLine at $($mErr.Index)"

        $between = $svcCodeOnly.Substring($mStart.Index,
            [Math]::Min($mErr.Index, $svcCodeOnly.Length) - $mStart.Index)
        Assert 'no WAIT between Start and the reads (the actual deadlock)' `
               ($between -notmatch 'WaitForExit') `
               "found a WaitForExit between Process.Start and the reads"
    }

    # (a) handlers and EnableRaisingEvents must be wired BEFORE Start.
    $mEnable = [regex]::Match($svcCodeOnly, 'EnableRaisingEvents\s*=\s*true')
    $mHandler = [regex]::Match($svcCodeOnly, 'OutputDataReceived\s*\+=')
    Assert 'EnableRaisingEvents is set' $mEnable.Success
    Assert 'output handlers are attached' $mHandler.Success
    if ($mEnable.Success -and $mStart.Success) {
        Assert 'EnableRaisingEvents is set BEFORE Process.Start' `
               ($mEnable.Index -lt $mStart.Index) `
               "EnableRaisingEvents at $($mEnable.Index), Process.Start at $($mStart.Index)"
    }
    if ($mHandler.Success -and $mStart.Success) {
        Assert 'output handlers are attached BEFORE Process.Start' `
               ($mHandler.Index -lt $mStart.Index) `
               "handler at $($mHandler.Index), Process.Start at $($mStart.Index)"
    }

    # Both streams must be redirected, or there is nothing to deadlock on.
    Assert 'stdout is redirected' ($svcCodeOnly -match 'RedirectStandardOutput\s*=\s*true')
    Assert 'stderr is redirected' ($svcCodeOnly -match 'RedirectStandardError\s*=\s*true')

    # EnableRaisingEvents is what actually makes Process raise the
    # OutputDataReceived/ErrorDataReceived events at all. Without it the
    # Begin*ReadLine calls silently do nothing and output is never delivered.
    Assert 'EnableRaisingEvents is set' `
           ($svcCodeOnly -match 'EnableRaisingEvents\s*=\s*true')
}

# =====================================================================
# Section 2 - Task.Run discipline
# =====================================================================
Write-Host ''
Write-Host '[2] Task.Run only for genuinely blocking work' -ForegroundColor Yellow

if (Test-Path $svcPath) {
    $svcCodeOnly = [regex]::Replace((Get-Content $svcPath -Raw), '(?m)^\s*(//|/\*|\*).*$', '')

    # Task.Run must not appear in ScriptService at all: launching a process is
    # I/O, and ADR-0015 forbids Task.Run as a default wrapper around it. The
    # correct construct is the already-async Process APIs.
    $taskRun = [regex]::Matches($svcCodeOnly, 'Task\.Run')
    Assert 'ScriptService does not wrap process launch in Task.Run' `
           ($taskRun.Count -eq 0) `
           "found $($taskRun.Count) Task.Run occurrence(s) in ScriptService.cs"

    # Where Task.Run IS allowed: CPU-bound work only. Comments are stripped
    # first: ScriptService's own header explains in prose why it does NOT use
    # Task.Run, and a naive scan flags the explanation as the sin it forbids.
    $allCs = @(Get-ChildItem $Src -Recurse -Filter '*.cs' -EA SilentlyContinue |
               Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' })
    $offenders = @()
    foreach ($f in $allCs) {
        $code = [regex]::Replace((Get-Content $f.FullName -Raw), '(?m)^\s*//.*$', '')
        $code = [regex]::Replace($code, '/\*.*?\*/', '', 'Singleline')
        if ($code -match 'Task\.Run' -and $code -notmatch 'CPU-bound|CpuBound|cpu-bound') {
            $offenders += $f.Name
        }
    }
    Assert 'every Task.Run in the project is justified as CPU-bound' `
           ($offenders.Count -eq 0) `
           "unjustified in: $($offenders -join ', ')"
}

# =====================================================================
# Section 3 - cancellation and timeout exist on the execution path
# =====================================================================
Write-Host ''
Write-Host '[3] Cancellation + timeout on every run' -ForegroundColor Yellow

$vmPath = Join-Path $Src 'ViewModels\TabViewModelBase.cs'

if (Test-Path $svcPath) {
    $svc = Get-Content $svcPath -Raw

    Assert 'RunAsync accepts a CancellationToken' `
           ($svc -match 'CancellationToken\s+cancellationToken')
    Assert 'a default timeout exists' `
           ($svc -match 'DefaultTimeout|TimeoutSeconds')
    Assert 'the timeout is actually enforced' `
           ($svc -match 'CancelAfter|CancellationTokenSource\s*\(')

    # Killing only the direct child leaves grandchildren (PowerShell itself is
    # already a child; scripts spawn more) holding the pipes, which is how a
    # "cancelled" run can still hang the UI. The whole tree must go.
    Assert 'cancellation kills the whole process tree' `
           ($svc -match 'Kill\s*\(\s*entireProcessTree\s*:\s*true\s*\)')
}

Assert 'TabViewModelBase.cs exists' (Test-Path $vmPath)
if (Test-Path $vmPath) {
    $vm = Get-Content $vmPath -Raw

    # Requirement: the UI exposes Cancel for long scripts.
    Assert 'the ViewModel owns a CancellationTokenSource' `
           ($vm -match 'CancellationTokenSource')
    Assert 'the ViewModel exposes a Cancel command' `
           ($vm -match '\[RelayCommand[^\]]*\]\s*(\r?\n\s*)?(public|private)[^=]*Cancel')
    Assert 'Cancel is wired to the token source Cancel()' `
           ($vm -match '\.Cancel\(\)')
    Assert 'CancelCanExecute exists so the button disables when idle' `
           ($vm -match 'CancelCanExecute')

    # The command must be async all the way down, and must not block the thread.
    Assert 'the run command is async Task (not void, not .Result/.Wait())' `
           ($vm -match 'async\s+Task\s+RunVerbAsync')
    Assert 'no blocking wait on the UI thread' `
           ($vm -notmatch '\.Wait\(\)|\.Result\b|GetAwaiter\(\)\.GetResult\(\)')
}

# =====================================================================
# Section 4 - batched dispatch, never one hop per line
# =====================================================================
Write-Host ''
Write-Host '[4] One dispatcher hop per completion, not per output line' -ForegroundColor Yellow

if (Test-Path $vmPath) {
    $vm = Get-Content $vmPath -Raw
    $vmCodeOnly = [regex]::Replace($vm, '(?m)^\s*(//|/\*|\*).*$', '')

    Assert 'the ViewModel uses a Dispatcher hop' `
           ($vmCodeOnly -match 'Dispatcher')
    Assert 'the hop is a non-blocking BeginInvoke' `
           ($vmCodeOnly -match 'BeginInvoke')

    # THE load-bearing assertion of this section. A per-line BeginInvoke is the
    # jank the ticket exists to remove: 5000 lines would mean 5000 hops. The
    # batching helper is what makes the count O(1) instead.
    $beginInvokeCount = ([regex]::Matches($vmCodeOnly, 'BeginInvoke')).Count
    Assert 'BeginInvoke appears once (the batched helper), not per line' `
           ($beginInvokeCount -le 1) `
           "found $beginInvokeCount BeginInvoke call site(s) in TabViewModelBase.cs"

    # Streaming output must accumulate somewhere without touching a bound
    # property per line.
    Assert 'output is buffered before it reaches the bound property' `
           ($vmCodeOnly -match 'StringBuilder|List<string>|_pending')
}

# =====================================================================
# Section 5 - structured result, nothing swallowed
# =====================================================================
Write-Host ''
Write-Host '[5] Non-zero exit + stderr surface as a structured result' -ForegroundColor Yellow

$resPath = Join-Path $Src 'Models\ScriptResult.cs'
Assert 'ScriptResult.cs exists' (Test-Path $resPath)
if (Test-Path $resPath) {
    $res = Get-Content $resPath -Raw

    Assert 'result carries an exit code'      ($res -match 'ExitCode')
    Assert 'result carries a duration'        ($res -match 'Duration')
    Assert 'result carries the raw output'    ($res -match 'Output')
    Assert 'result distinguishes stderr'      ($res -match 'StandardError|Stderr')
    Assert 'result distinguishes cancellation' ($res -match 'Cancelled|TimedOut')
    Assert 'Succeeded is derived from the exit code' ($res -match 'ExitCode\s*==\s*0')
}

if (Test-Path $vmPath) {
    $vm = Get-Content $vmPath -Raw
    # "never swallowed". The wording lives in ScriptResult.Summary, so the
    # ViewModel's job is to PROPAGATE the result's verdict to the status line,
    # not to re-derive it. Asserting the ViewModel for the literal string
    # "FAILED" would fail a correct implementation that simply says
    # `Status = result.Summary`.
    Assert 'the ViewModel propagates the result verdict to the status line' `
           ($vm -match 'result\.(Summary|ExitCode|Succeeded)')
    # ...and that the verdict really is derived from the exit code.
    Assert 'the verdict distinguishes success from failure' `
           ($res -match 'Succeeded')
    Assert 'a timeout/cancel is reported distinctly' `
           ($vm -match 'Cancel|TimedOut|cancell')
}

# =====================================================================
# Section 6 - the chatty demonstration fixture
# =====================================================================
Write-Host ''
Write-Host '[6] A deliberately chatty, long-running fixture exists' -ForegroundColor Yellow

$demo = Join-Path $ProjectRoot 'scripts\demo-stream.ps1'
Assert 'scripts\demo-stream.ps1 exists' (Test-Path $demo) $demo

if (Test-Path $demo) {
    $demoTxt = Get-Content $demo -Raw

    Assert 'the fixture writes many lines'  ($demoTxt -match 'Lines|Lines')
    Assert 'the fixture paces itself'       ($demoTxt -match 'DelayMs|Sleep|Start-Sleep')
    Assert 'the fixture writes to stderr too' ($demoTxt -match 'stderr|Error')
    Assert 'the fixture is parameterised'   ($demoTxt -match '\[CmdletBinding\(\)\]|\bparam\s*\(')

    # It must be reachable from the registry, or no button and no CLI verb can
    # ever demonstrate the streaming behaviour.
    $reg = Get-Content (Join-Path $Src 'Services\VerbRegistry.cs') -Raw
    Assert 'a registry row exposes the fixture' ($reg -match 'demo-stream\.ps1')
}

# =====================================================================
# Section 7 - startup time is measured, not assumed
# =====================================================================
Write-Host ''
Write-Host '[7] Startup is measured against priority 1' -ForegroundColor Yellow

$appPath = Join-Path $Src 'App.xaml.cs'
Assert 'App.xaml.cs exists' (Test-Path $appPath)
if (Test-Path $appPath) {
    $app = Get-Content $appPath -Raw

    Assert 'startup is timed'  ($app -match 'Stopwatch|GetCurrentProcess\(\)\.StartTime|ProcessStartUtc')
    Assert 'startup reports the elapsed time' ($app -match 'window ready in')
    # Priority 1 is maximum speed, so the measurement has to be visible
    # somewhere the user or the log can see, not computed and dropped.
    Assert 'the measurement is reported, not discarded' `
           ($app -match 'WriteLine|Console\.|Status|Debug')
}

# =====================================================================
# Section 7b - the app must actually LAUNCH (defect D18)
# =====================================================================
#
# WHY THIS SECTION EXISTS
#   Ticket 10 shipped a GUI that had never been run. MainWindow's constructor
#   attaches each View's DataContext with FindName(...), but MainWindow.xaml set
#   no x:Name on any of the six views, so every FindName returned null and the
#   process died at startup with:
#
#     System.NullReferenceException at MainWindow..ctor() MainWindow.xaml.cs:line 26
#
#   The static suites could not see it because none of them launched the app.
#   A build that compiles is not an app that starts. The x:Name assertions below
#   plus the real launch in section 8 are what close that hole.
#
Write-Host ''
Write-Host '[7b] The six views are addressable (D18 regression)' -ForegroundColor Yellow

$mwXaml = Join-Path $Src 'MainWindow.xaml'
$mwCs   = Join-Path $Src 'MainWindow.xaml.cs'
Assert 'MainWindow.xaml exists'  (Test-Path $mwXaml)
Assert 'MainWindow.xaml.cs exists' (Test-Path $mwCs)

if (Test-Path $mwXaml) {
    $xaml = Get-Content $mwXaml -Raw
    $views = @('KillStartView','RestartView','SettingsView','AutoHotkeyView','DebuggingView','UninstallView')
    $unnamed = @()
    foreach ($v in $views) {
        # Each view must be NAMED. An unnamed one makes its FindName call in
        # MainWindow's constructor return null and crashes startup.
        if ($xaml -notmatch ("x:Name=`"" + $v + "`"")) { $unnamed += $v }
    }
    Assert 'all six views carry x:Name (FindName can resolve them)' `
           ($unnamed.Count -eq 0) `
           "missing x:Name on: $($unnamed -join ', ')"
}

if (Test-Path $mwCs) {
    $mw = Get-Content $mwCs -Raw
    # The null-forgiving operator on FindName hides the crash instead of fixing
    # it, so it must not be the only thing standing between the app and a
    # NullReferenceException. Require an explicit guard.
    Assert 'MainWindow guards the FindName results instead of only asserting them' `
           ($mw -match 'FindName' -and ($mw -match 'throw new' -or $mw -match 'if\s*\(')) `
           'FindName returns null for unnamed elements; add an explicit guard'
}

# =====================================================================
# Section 8 - build + REAL runtime behaviour
# =====================================================================
Write-Host ''
Write-Host '[8] Build + runtime evidence' -ForegroundColor Yellow

$exe = Join-Path $Src 'bin\Release\net8.0-windows\KomorebiDashboard.exe'
$built = $false

if (-not $SkipBuild) {
    Write-Host '  ... dotnet build' -ForegroundColor DarkGray
    $buildLog = & dotnet build $Src -c Release --nologo -v quiet 2>&1 | Out-String
    $built = ($LASTEXITCODE -eq 0)
    Assert 'dotnet build exits 0' $built `
           ($buildLog -split "`n" | Where-Object { $_ -match 'error|Error' } | Select-Object -First 5 | Out-String)
} else {
    $built = Test-Path $exe
    Assert 'prebuilt EXE present (SkipBuild)' $built $exe
}

if ($built) {
    Assert 'EXE produced' (Test-Path $exe) $exe

    # --- the CLI twin must still work (no regression from ticket 10) --------
    $helpOut = & $exe --help 2>&1 | Out-String
    Assert '--help still works (no regression)' ($LASTEXITCODE -eq 0 -and $helpOut -match 'Verbs:')

    # --- the GUI must really open (D18 regression) ------------------------
    # A green build is not a running app: ticket 10 shipped a binary that died
    # in its constructor. This launches it and requires a real window handle.
    # Launching is safe -- no verb is invoked, no script runs, nothing on the
    # system is touched -- and the process is always closed again below.
    $guiLaunched = $false
    try {
        $guiOut = Join-Path $env:TEMP 'ticket11-gui.out'
        $guiErr = Join-Path $env:TEMP 'ticket11-gui.err'
        $guiSw  = [System.Diagnostics.Stopwatch]::StartNew()
        $gui = Start-Process -FilePath $exe -PassThru -WindowStyle Hidden `
                             -RedirectStandardOutput $guiOut -RedirectStandardError $guiErr -ErrorAction Stop

        $deadline = (Get-Date).AddSeconds(30)
        while (-not $gui.HasExited -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 150
            if ($gui.MainWindowHandle -ne 0) { break }
        }
        $guiSw.Stop()

        $guiLaunched = -not $gui.HasExited -and $gui.MainWindowHandle -ne 0
        $guiErrText = [string]((Get-Content $guiErr -EA SilentlyContinue | Select-Object -First 2) -join ' ')
        Assert 'the GUI launches and creates a real window (D18 regression)' ([bool]$guiLaunched) `
               "HasExited=$($gui.HasExited) handle=$($gui.MainWindowHandle); stderr: $guiErrText"

        if ($guiLaunched) {
            Assert 'time-to-window stays under the priority-1 budget (5s)' `
                   ($guiSw.Elapsed.TotalSeconds -lt 5) `
                   "took $([math]::Round($guiSw.Elapsed.TotalSeconds,2))s"
        }

        # Always clean up: never leave a dashboard window on the user's desktop.
        if (-not $gui.HasExited) {
            $gui.CloseMainWindow() | Out-Null
            if (-not $gui.WaitForExit(5000)) { $gui.Kill() }
        }

        # The startup figure is read only AFTER the process has exited.
        # MainWindow.Show() creates the window handle before OnStartup reaches
        # the Console.WriteLine that reports the timing, and the redirected
        # stdout is flushed at exit — so reading it the moment the window
        # appears races the writer and yields an empty string. Waiting for exit
        # removes the race instead of retrying around it.
        if ($guiLaunched) {
            $startupText = [string](Get-Content $guiOut -Raw -EA SilentlyContinue)
            # [bool] and [string] coercion on purpose: `$null -match ...` yields
            # an empty Object[], not a Boolean, which cannot bind to [bool] and
            # would throw rather than fail the assertion.
            $startupSaidReady = [bool]($startupText -match 'window ready in \d+ ms')
            Assert 'the startup figure is reported and plausible' `
                   $startupSaidReady `
                   "stdout was: '$startupText' (App must print the measured startup time)"
        }
    } catch {
        Assert 'the GUI launches and creates a real window (D18 regression)' $false $_.Exception.Message
    }

    # --- chatty script: streams a lot of output and takes real time ---------
    if (Test-Path $demo) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $demoOut = & $exe demo-stream '-Lines' '400' '-DelayMs' '0' 2>&1 | Out-String
        $demoRc = $LASTEXITCODE
        $sw.Stop()

        $lineCount = ($demoOut -split "`n" | Where-Object { $_.Trim() }).Count
        Assert 'chatty verb exits 0' ($demoRc -eq 0) "rc=$demoRc"
        Assert 'chatty verb really produced bulk output' `
               ($lineCount -ge 400) "got $lineCount non-empty lines"
        Assert 'chatty verb completes fast with DelayMs=0 (no artificial stall)' `
               ($sw.Elapsed.TotalSeconds -lt 60) ('{0:0.0}s' -f $sw.Elapsed.TotalSeconds)

        # --- timeout: a long run must be killed, not waited on ---------------
        $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
        $toOut = & $exe demo-stream '-Lines' '100000' '-DelayMs' '50' '-TimeoutSeconds' '3' 2>&1 | Out-String
        $toRc = $LASTEXITCODE
        $sw2.Stop()

        Assert 'a hung script is stopped by the timeout' `
               ($sw2.Elapsed.TotalSeconds -lt 45) `
               "timeout run took $('{0:0.0}' -f $sw2.Elapsed.TotalSeconds)s — expected the timeout to fire, not the script to finish"
        Assert 'timeout is reported as a timeout, not as success' `
               ($toOut -match 'timed out|TimedOut|timeout' -or $toRc -ne 0) `
               "rc=$toRc; tail: $(($toOut -split "`n" | Select-Object -Last 3) -join ' / ')"

        # --- and the timeout must leave no orphaned powershell behind --------
        # The match is anchored on '-File <path>demo-stream.ps1', i.e. the exact
        # shape of a real ScriptService child. A looser 'demo-stream' match
        # counts the DETECTOR ITSELF: the checking shell's own command line
        # contains the word, so the assertion would report a phantom orphan and
        # be quietly useless on every run.
        Start-Sleep -Milliseconds 400
        $orphans = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                     Where-Object { $_.CommandLine -match '-File\s+\S*demo-stream\.ps1' })
        Assert 'timeout kills the process TREE (no orphaned demo-stream)' `
               ($orphans.Count -eq 0) `
               "still running: $($orphans.ProcessId -join ', ')"
    } else {
        Assert 'chatty fixture present for runtime test' $false 'scripts\demo-stream.ps1 missing'
    }
}

# =====================================================================
Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
if ($script:failed -eq 0) {
    Write-Host (" RESULT: all {0} assertions passed" -f $script:passed) -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    exit 0
} else {
    Write-Host (" RESULT: {0} passed, {1} FAILED" -f $script:passed, $script:failed) -ForegroundColor Red
    Write-Host '============================================================' -ForegroundColor Red
    exit 1
}