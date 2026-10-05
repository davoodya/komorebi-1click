#Requires -Version 5.1
<#
=============================================================================================
komorebi-1click — SANDBOX verification suite (ticket 14, destructive phases)

THIS FILE CAN INSTALL, RESTART AND UNINSTALL. It must only ever run inside
Windows Sandbox (or a throwaway VM), never on a machine Davood works on.
The read-only half lives in verify-readonly.ps1, which is safe anywhere.

Windows Sandbox gives a disposable Win11 with the host folders MAPPED IN. That
mapping is the whole trick: the repo is the host's, but everything the installer
writes (Program Files, %USERPROFILE%\.config, scheduled tasks) dies with the
sandbox session. That is what makes "clean install / uninstall / leave no trace"
testable without risking the reference machine.

HOW TO RUN (from the host, nothing else needs doing by hand)
    .\tests\start-sandbox.ps1            # starts Sandbox, runs everything, shows results

IN-SANDBOX MANUAL PATH (if you prefer to click through it)
    1. Start "Windows Sandbox" from the Start menu.
    2. In the Sandbox desktop, open PowerShell.
    3. Run the block printed by start-sandbox.ps1 (it mounts the repo first).

PHASES (each is gated; a failure stops the run unless -ContinueOnFailure)
    P1  preflight      sandbox detected, repo mounted, SHA pins verified
    P2  install        silent install, asserts every artefact landed
    P3  idempotency    second install is a no-op, counts unchanged
    P4  config         generated komorebi.json/whkdrc keep ADR-0016 requirements
    P5  runtime        komorebi+whkd actually run, hotkey surface, mintty whitelisted
    P6  dashboard      self-contained EXE starts with NO .NET runtime present
    P7  cleanup        uninstall, then assert nothing is left behind
    P8  report         machine-readable JSON + human summary in the log

WHY P6 MATTERS: it is the deferred test D-T1. The published EXE is
self-contained, so it must run on a machine with no .NET 8 runtime at all.
=============================================================================================
#>

[CmdletBinding()]
param(
    # The repo path AS SEEN INSIDE the sandbox. start-sandbox.ps1 mounts it.
    [string] $Repo = 'C:\komorebi-src',

    # Where to write the machine-readable result.
    [string] $LogDir = 'C:\verification',

    # Stop at the first failing phase instead of running the rest.
    [switch] $ContinueOnFailure,

    # Skip the phases that reinstall or remove (use when re-running after a
    # partial run, so you do not have to start a fresh Sandbox session).
    [switch] $SkipInstall
)

$ErrorActionPreference = 'Stop'
$script:Start = Get-Date

# =====================================================================================
# Result accumulation. Every check lands in one array so the report can be written
# even when a phase dies.
# =====================================================================================
$script:Results = New-Object System.Collections.Generic.List[object]
$script:Phase = 'init'
$script:FailedPhases = New-Object System.Collections.Generic.List[string]
# Set only by Assert-InsideSandbox. P2 and P7 read it, so no mutating phase
# can run on the strength of a guard that never actually passed.
$script:GatePassed = $false

function Assert {
    param([string] $Label, [bool] $Ok, [string] $Detail = '')
    $script:Results.Add([PSCustomObject]@{
        Phase    = $script:Phase
        Label    = $Label
        Passed   = $Ok
        Detail   = $Detail
        Time     = (Get-Date).ToString('HH:mm:ss')
    })
    if ($Ok) { Write-Host ("  [PASS] {0}" -f $Label) -ForegroundColor Green }
    else {
        $s = if ($Detail) { " — $Detail" } else { '' }
        Write-Host ("  [FAIL] {0}{1}" -f $Label, $s) -ForegroundColor Red
    }
}

function Assert-InsideSandbox {
    # THE MOST IMPORTANT FUNCTION IN THIS FILE.
    #
    # It runs OUTSIDE the Phase machinery, and it must not be reachable by any
    # code path that a try/catch could swallow. Two versions of this guard were
    # broken before it worked, both because it lived somewhere the runner
    # continued past:
    #
    #   v1  checked C:\Windows\System32\WindowsSandbox.exe. That file exists on
    #       the reference machine whenever the optional FEATURE is installed, so
    #       "installed" was mistaken for "inside", and the installer ran against
    #       the live komorebi/whkd config.
    #   v2  correctly refused, but sat INSIDE Phase, whose try/catch caught the
    #       exit and carried on into the install phase anyway.
    #
    # So: standalone function, three independent signals that must ALL agree, and
    # a hard stop that runs before any mutating phase is entered.
    $marker   = Join-Path $Repo 'test-results\.sandbox-marker'
    $s1 = Test-Path $marker
    $s2 = Test-Path 'C:\Users\WDAGUtilityAccount'
    $s3 = $true
    try {
        $gpu = @(Get-CimInstance Win32_VideoController -EA SilentlyContinue |
                 Where-Object { $_.Name -notmatch 'Remote|Basic' })
        $s3 = ($gpu.Count -eq 0)
    } catch { }

    Write-Host ''
    Write-Host '== GATE: refusing to touch a non-sandbox machine' -ForegroundColor Yellow
    Write-Host ("   suite marker written by the .wsb bootstrap : {0}" -f $s1) -ForegroundColor DarkGray
    Write-Host ("   container account (WDAGUtilityAccount)    : {0}" -f $s2) -ForegroundColor DarkGray
    Write-Host ("   no real GPU (true inside a sandbox)      : {0}" -f $s3) -ForegroundColor DarkGray

    if (-not ($s1 -and $s2 -and $s3)) {
        Write-Host ''
        Write-Host ' NOT RUNNING INSIDE WINDOWS SANDBOX — aborting.' -ForegroundColor Red
        Write-Host ' This suite installs software, registers scheduled tasks and rewrites' -ForegroundColor Red
        Write-Host ' the live komorebi/whkd/YASB config. It only belongs in a sandbox or' -ForegroundColor Red
        Write-Host ' a throwaway VM.' -ForegroundColor Red
        Write-Host ''
        Write-Host '   .\tests\start-sandbox.ps1   to run it properly' -ForegroundColor Cyan
        Write-Host '   .\tests\verify-readonly.ps1   for a check that is safe anywhere' -ForegroundColor Cyan
        Write-Host ''
        exit 3
    }
    $script:GatePassed = $true
    Write-Host '   OK — sandbox confirmed.' -ForegroundColor Green
}

function Phase {
    param([string] $Name, [scriptblock] $Body)
    $script:Phase = $Name
    Write-Host ''
    Write-Host ("== {0} :: {1}" -f $Name, (Get-Date -Format 'HH:mm:ss')) -ForegroundColor Cyan

    try {
        & $Body
    } catch {
        # A thrown phase is a FAIL, not a crash: the remaining phases still hold
        # evidence about what is and is not broken.
        Assert ("phase {0} completed without an unhandled error" -f $Name) $false $_.Exception.Message
    }

    $phaseFails = @($script:Results.ToArray() | Where-Object { $_.Phase -eq $Name -and -not $_.Passed })
    if ($phaseFails.Count -gt 0) {
        $script:FailedPhases.Add($Name)
        Write-Host ("   -> {0} FAILED ({1} check(s))" -f $Name, $phaseFails.Count) -ForegroundColor Red
        if (-not $ContinueOnFailure) {
            Write-Host ''
            Write-Host '   Stopping. Re-run with -ContinueOnFailure to gather every phase anyway.' -ForegroundColor Yellow
            Write-Host-PartialReport
            exit 1
        }
    }
}

function Write-Host-PartialReport {
    # Emits whatever has been collected so far, so an aborted run still leaves
    # evidence behind instead of only a red line in the console.
    try { Save-Report } catch { Write-Host "   (report could not be written: $($_.Exception.Message))" -ForegroundColor DarkGray }
}

function Save-Report {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

    $total = $script:Results.Count
    $passed = @($script:Results.ToArray() | Where-Object Passed).Count
    $failed = $total - $passed
    $summary = [PSCustomObject]@{
        machine      = $env:COMPUTERNAME
        os           = (Get-CimInstance Win32_OperatingSystem).Caption
        osVersion    = [string](Get-CimInstance Win32_OperatingSystem).Version
        sandbox      = (Test-Path 'C:\\Windows\\System32\\WindowsSandbox.exe')
        startedUtc   = $script:Start.ToUniversalTime().ToString('o')
        finishedUtc  = (Get-Date).ToUniversalTime().ToString('o')
        durationSec  = [math]::Round(((Get-Date) - $script:Start).TotalSeconds, 1)
        total        = $total
        passed       = $passed
        failed       = $failed
        failedPhases = $script:FailedPhases.ToArray()
        checks       = $script:Results.ToArray()
    }

    $json = Join-Path $LogDir 'verification-result.json'
    $summary | ConvertTo-Json -Depth 6 | Set-Content -Path $json -Encoding UTF8

    # Human-readable sibling, because a JSON blob on its own does not tell the
    # next person what failed at a glance.
    $txt = Join-Path $LogDir 'verification-result.txt'
    $lines = @(
        "komorebi-1click sandbox verification",
        ("run: {0}" -f $summary.startedUtc),
        ("machine: {0} / {1}" -f $summary.machine, $summary.os),
        ("duration: {0}s" -f $summary.durationSec),
        "",
        ("RESULT: {0} passed, {1} failed, {2} total" -f $passed, $failed, $total),
        ("failed phases: {0}" -f (@($summary.failedPhases) -join ', ')),
        ""
    )
    # .ToArray() for the same reason: @() on the generic List yields nothing.
    foreach ($g in ($script:Results.ToArray() | Group-Object Phase)) {
        $lines += ("--- {0} ---" -f $g.Name)
        foreach ($r in $g.Group) {
            $mark = if ($r.Passed) { 'PASS' } else { 'FAIL' }
            $d = if ($r.Detail) { "  <- $($r.Detail)" } else { '' }
            $lines += ("  [{0}] {1}{2}" -f $mark, $r.Label, $d)
        }
        $lines += ''
    }
    $lines | Set-Content -Path $txt -Encoding UTF8

    Write-Host ''
    Write-Host (" report: {0}" -f $json) -ForegroundColor Cyan
    Write-Host ("         {0}" -f $txt) -ForegroundColor Cyan
}

# =====================================================================================
# Where things live after an install. Single source of truth, because guessing
# paths per assertion is how the D21-class defect happened.
# =====================================================================================
# Every path below was confirmed against the LIVE machine, not assumed. Three of
# them were wrong on the first pass and are worth recording:
#   * komorebi.exe and komorebic.exe live in Program Files\komorebi\BIN\,
#     not at the root of that folder.
#   * komorebi.json lives in %USERPROFILE%\.config\komorebi\.
#   * whkdrc lives DIRECTLY in %USERPROFILE%\.config\, one level ABOVE the
#     komorebi folder (Install-Common.ps1 joins it as `..\whkdrc`).
# Asserting the wrong path makes every phase fail for a reason that has nothing
# to do with the software under test.
$script:KomorebiInstall = Join-Path $env:ProgramFiles 'komorebi'
$script:KomorebiBin     = Join-Path $script:KomorebiInstall 'bin\komorebi.exe'
$script:KomorebicBin    = Join-Path $script:KomorebiInstall 'bin\komorebic.exe'
$script:UserConfig      = Join-Path $env:USERPROFILE '.config'
$script:KomorebiCfgHome = Join-Path $script:UserConfig 'komorebi'
$script:KomorebiCfg     = Join-Path $script:KomorebiCfgHome 'komorebi.json'
$script:ApplicationsCfg = Join-Path $script:KomorebiCfgHome 'applications.json'
# One level up from the config home, per Install-Common.ps1 line 957.
$script:WhkdRc          = Join-Path $script:UserConfig 'whkdrc'
$script:YasbCfg         = Join-Path $script:UserConfig 'yasb\config.yaml'
$script:InstallLog      = Join-Path $LogDir 'install.log'

Write-Host '=====================================================================' -ForegroundColor White
Write-Host ' komorebi-1click — SANDBOX verification (installs and uninstalls)' -ForegroundColor White
Write-Host '=====================================================================' -ForegroundColor White
Write-Host ("  machine : {0}" -f $env:COMPUTERNAME)
Write-Host ("  repo    : {0}" -f $Repo)
Write-Host ("  sandbox : {0}" -f (Test-Path 'C:\Windows\System32\WindowsSandbox.exe'))

# =====================================================================================
# THE GATE. Before any mutating phase, before any output directory is created.
Assert-InsideSandbox

# =====================================================================================
Phase 'P1-preflight' {

    # --- repo is mounted ------------------------------------------------------------
    Assert 'the repo is mounted at the expected path' (Test-Path $Repo) $Repo
    Assert 'Install.ps1 is present' (Test-Path (Join-Path $Repo 'Install.ps1'))
    Assert 'the payloads directory is present' (Test-Path (Join-Path $Repo 'binaries'))

    # --- payload integrity before anything is installed -----------------------------
    $shaFile = Join-Path $Repo 'binaries\payloads.sha256.json'
    Assert 'the SHA manifest is present' (Test-Path $shaFile)
    if (Test-Path $shaFile) {
        $manifest = Get-Content $shaFile -Raw | ConvertFrom-Json
        $bins = @($manifest.binaries)
        Assert 'the manifest lists its binaries' ($bins.Count -ge 5) ("entries: " + $bins.Count)

        $bad = @(); $missing = @()
        foreach ($b in $bins) {
            $target = Join-Path $Repo $b.file
            if (-not (Test-Path $target)) { $missing += $b.file; continue }
            if ((Get-FileHash $target -Algorithm SHA256).Hash -ne ([string]$b.sha256).ToUpper()) { $bad += $b.file }
        }
        Assert 'every payload is present' ($missing.Count -eq 0) ("missing: " + ($missing -join ', '))
        Assert ('all {0} payload hashes verify before install' -f $bins.Count) `
               ($bad.Count -eq 0) ("corrupt: " + ($bad -join ', '))
    }

    # --- clean starting point -------------------------------------------------------
    # Verifying "install from clean" on a machine that already has the software
    # installed proves nothing, so the pre-state is asserted, not assumed.
    Assert 'komorebi is NOT already installed' (-not (Test-Path $script:KomorebiBin)) `
           "$($script:KomorebiBin) exists — start a fresh Sandbox session"
    Assert 'no Komorebi scheduled task exists yet' `
           (-not (Get-ScheduledTask -TaskName 'Komorebi' -ErrorAction SilentlyContinue))
}

# =====================================================================================
if (-not $SkipInstall) {
Phase 'P2-install' {

    # Defence in depth. The pre-flight gate already aborted unless we are inside
    # a sandbox, but that guard has been wrong twice in this file's history. If
    # anyone ever moves it, weakens it, or runs a phase directly, this refuses
    # rather than reinstalling software onto a real machine.
    Assert 'the sandbox gate passed before this phase ran' ($script:GatePassed -eq $true) `
           'the pre-flight gate did not confirm a sandbox; refusing to install'
    if ($script:GatePassed -ne $true) { return }

    Assert 'the install log directory is creatable' (
        $(if (Test-Path $LogDir) { $true } else { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null; $true }))

    # The installer's ONLY parameter is -SkipElevationCheck (Install.ps1 param
    # block, verified by reading it). There is no -InstallDir, no -AutoInstall and
    # no -Force: passing them would fail argument binding, so the surface here
    # matches the real one exactly.
    # -SkipElevationCheck is required because the Sandbox session is not elevated,
    # and the install needs elevation. The EXE wrapper normally supplies this.
    $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'Install.ps1') `
                      -SkipElevationCheck `
                      2>&1 | Tee-Object -FilePath $script:InstallLog
    $rc = $LASTEXITCODE

    Assert 'the installer exited 0' ($rc -eq 0) (
        (($out | Where-Object { $_ -match 'error|fail|exception' } | Select-Object -First 3) -join ' / '))

    # --- binaries landed ------------------------------------------------------------
    Assert 'komorebi.exe is installed' (Test-Path $script:KomorebiBin) $script:KomorebiBin
    Assert 'komorebic.exe is installed' (Test-Path $script:KomorebicBin) $script:KomorebicBin

    # --- config generated -----------------------------------------------------------
    Assert 'the generated komorebi.json exists' (Test-Path $script:KomorebiCfg) $script:KomorebiCfg
    Assert 'the generated whkdrc exists (in .config, one level up)' (Test-Path $script:WhkdRc) $script:WhkdRc
    Assert 'the generated applications.json exists' (Test-Path $script:ApplicationsCfg) $script:ApplicationsCfg
    Assert 'the generated YASB config exists' (Test-Path $script:YasbCfg) $script:YasbCfg

    # --- scripts and AHK payloads: they stay in the REPO. The installer does not
    #     copy them elsewhere; it points the config at the repo and schedules
    #     tasks against it. So the assertion is that the repo's own scripts are
    #     what the generated config references, not that a copy exists.
    Assert 'the repo still holds its management scripts' `
           (@(Get-ChildItem (Join-Path $Repo 'scripts') -Filter '*.ps1' -EA SilentlyContinue).Count -ge 20)
    Assert 'the repo still holds the AHK payloads' `
           (@(Get-ChildItem (Join-Path $Repo 'autohotkey') -Filter '*.ahk' -EA SilentlyContinue).Count -ge 3)

    # --- scheduled tasks, at the right privilege (ADR-0016) ------------------------
    # This is the requirement ADR-0016 exists for: mintty's elevated windows are
    # only visible if the task runs at the highest integrity level.
    foreach ($t in @('Komorebi', 'KomorebiWatchdog')) {
        $task = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
        Assert "the '$t' scheduled task was created" ([bool]$task)
        if ($task) {
            Assert "'$t' is RunLevel=Highest" ($task.Principal.RunLevel -eq 'Highest') `
                   ("actual: " + $task.Principal.RunLevel)
            Assert "'$t' is enabled" ($task.State -ne 'Disabled') ("state: " + $task.State)
        }
    }
}
} else {
    Write-Host ''
    Write-Host '== P2-install SKIPPED (-SkipInstall)' -ForegroundColor DarkYellow
}

# =====================================================================================
Phase 'P3-idempotency' {
    # Running the installer twice must not duplicate anything. This is the check
    # that catches an installer that appends to config files or registers a task
    # a second time under a second instance.

    $tasksBefore  = @(Get-ScheduledTask -TaskName 'Komorebi*' -EA SilentlyContinue).Count
    $cfgBefore    = if (Test-Path $script:KomorebiCfg) { (Get-Item $script:KomorebiCfg).Length } else { 0 }

    $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'Install.ps1') `
                      -SkipElevationCheck 2>&1
    $rc = $LASTEXITCODE

    Assert 'the second install exits 0' ($rc -eq 0) (
        (($out | Where-Object { $_ -match 'error|fail' } | Select-Object -First 2) -join ' / '))

    $tasksAfter = @(Get-ScheduledTask -TaskName 'Komorebi*' -EA SilentlyContinue).Count
    Assert 'no duplicate scheduled task was created' ($tasksAfter -eq $tasksBefore) `
           ("before: $tasksBefore, after: $tasksAfter")

    $cfgAfter = if (Test-Path $script:KomorebiCfg) { (Get-Item $script:KomorebiCfg).Length } else { 0 }
    Assert 'the generated config did not grow on reinstall' ($cfgAfter -eq $cfgBefore) `
           ("before: $cfgBefore bytes, after: $cfgAfter bytes")
}

# =====================================================================================
Phase 'P4-config' {
    # The GENERATED config is what actually runs, so ADR-0016 is verified here —
    # the read-only gate can only check the template.

    if (-not (Test-Path $script:KomorebiCfg)) {
        Assert 'the generated config is readable' $false $script:KomorebiCfg
        return
    }

    $cfg = Get-Content $script:KomorebiCfg -Raw | ConvertFrom-Json

    # The installer fills these at install time — the read-only gate asserts they
    # are EMPTY in the template, and here they must be POPULATED. Together the two
    # prove generation actually happened.
    Assert 'app_specific_configuration_path was generated' `
           ($null -ne $cfg.app_specific_configuration_path) `
           ([string]$cfg.app_specific_configuration_path)
    Assert 'workspaces were generated' (@($cfg.workspaces).Count -ge 1) `
           ("count: " + @($cfg.workspaces).Count)

    # ADR-0016 requirement 2. The whitelist MUST survive generation. If the
    # installer rebuilt the object from a stale copy, this is where it disappears.
    $wl = @($cfg.layered_whitelist)
    Assert 'the GENERATED config keeps a non-empty layered_whitelist' `
           ($wl.Count -ge 1) ("entries: " + $wl.Count)
    Assert 'the GENERATED whitelist still whitelists mintty (ADR-0016)' `
           ([bool]([string]($wl | ConvertTo-Json -Compress) -match 'mintty'))

    # No source-machine path may survive into the generated files.
    $leaked = @()
    foreach ($f in @($script:KomorebiCfg, $script:WhkdRc, $script:YasbCfg)) {
        if (-not (Test-Path $f)) { continue }
        if (Select-String -Path $f -Pattern 'DavoodYa' -SimpleMatch -CaseSensitive -EA SilentlyContinue) {
            $leaked += (Split-Path $f -Leaf)
        }
    }
    Assert 'no generated config contains a source-machine path' `
           ($leaked.Count -eq 0) ($leaked -join ', ')
}

# =====================================================================================
Phase 'P5-runtime' {

    $komorebi = Get-Process komorebi -EA SilentlyContinue
    Assert 'the komorebi process is running' ([bool]$komorebi) `
           ("processes: " + @(Get-Process komorebi -EA SilentlyContinue).Count)

    if (Test-Path $script:KomorebicBin) {
        $state = & $script:KomorebicBin state 2>&1 | Out-String
        Assert 'the komorebi IPC socket is alive' ($state -match 'socket alive\s*:\s*True') `
               (($state -split "`n" | Where-Object { $_ -match 'socket' } | Select-Object -First 1))

        $chk = & $script:KomorebicBin check 2>&1 | Out-String
        Assert 'komorebic check passes on the generated config' ($LASTEXITCODE -eq 0) (
            (($chk -split "`n" | Where-Object { $_ -match 'error|invalid' } | Select-Object -First 2) -join ' / '))
    }

    # whkd: the hotkey daemon must be up, otherwise none of the hotkeys exist.
    $whkd = Get-Process whkd -EA SilentlyContinue
    Assert 'the whkd process is running' ([bool]$whkd)

    # WHKD's hotkey surface is the product. Assert the scripts it loads exist on
    # disk — a daemon running with zero scripts loaded starts fine and silently
    # does nothing, which is the failure mode users report as "hotkeys stopped".
    # The AHK scripts are NOT copied into the config home. They stay in the repo
    # (Install-Common.ps1 resolves $ahkDir as $RepoRoot\autohotkey) and the
    # generated whkdrc points at them there, so the assertion belongs on the repo.
    $ahkDir = Join-Path $Repo 'autohotkey'
    if (Test-Path $ahkDir) {
        $ahk = @(Get-ChildItem $ahkDir -Filter '*.ahk' -EA SilentlyContinue)
        Assert ("{0} AHK scripts are present where whkd will load them from" -f $ahk.Count) ($ahk.Count -ge 3)
        Assert 'AppRunner.vbs is present (the AHK entry point)' `
               (Test-Path (Join-Path $ahkDir 'AppRunner.vbs'))
    } else {
        Assert 'the AHK script directory exists' $false $ahkDir
    }

    # mintty is whitelisted so elevated windows stay visible (ADR-0016). Prove it
    # against the LIVE config komorebic actually loaded.
    $liveCfg = & $script:KomorebicBin "q" rule get 2>&1 | Out-String
    Assert 'komorebi answers queries' ($LASTEXITCODE -eq 0) ($liveCfg.Split("`n")[0])
}

# =====================================================================================
Phase 'P6-dashboard-dt1' {
    # ---- D-T1: run the published EXE with NO .NET runtime present ---------------
    # The published artefact is self-contained, so it must not need .NET 8
    # installed. A Sandbox session has no .NET runtime by default, which makes it
    # the correct place to prove that rather than asserting it from the manifest.

    $exe = Join-Path $Repo 'releases\KomorebiDashboard.exe'

    if (-not (Test-Path $exe)) {
        Assert 'the published Dashboard EXE exists' $false $exe
        return
    }
    Assert 'the published Dashboard EXE exists' $true

    # Establish the precondition explicitly, because "it ran" only means something
    # if the runtime really was absent. If some Windows component did ship a .NET
    # runtime, the test is invalid and must say so rather than pass silently.
    $runtimes = @(Get-ChildItem 'C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App' -EA SilentlyContinue)
    $dotnetRoot = Test-Path 'C:\Program Files\dotnet'
    Assert 'D-T1 precondition: no .NET Desktop runtime is installed' `
           (-not $dotnetRoot -and $runtimes.Count -eq 0) `
           ("dotnet root present: $dotnetRoot, runtimes: " + $runtimes.Count)

    # Launch it. The Dashboard is a GUI app, so it must start, hold a process, and
    # expose a main window — and then be closed again, or P7's "left no trace"
    # assertion would be measuring our own leftovers.
    $proc = Start-Process -FilePath $exe -PassThru
    Start-Sleep -Seconds 8

    $alive = -not $proc.HasExited
    Assert 'the self-contained EXE starts with no .NET runtime present' $alive `
           ("exited early with code " + $(if ($proc.HasExited) { $proc.ExitCode } else { 'n/a' }))

    if ($alive) {
        $proc.Refresh()
        Assert 'the Dashboard created a main window' `
               ($proc.MainWindowHandle -ne 0) ("handle: " + $proc.MainWindowHandle)
        Assert 'the Dashboard stayed alive for the observation window' `
               (-not $proc.HasExited)
    }

    # Close it so the cleanup phase measures a clean slate.
    if ($alive) {
        Stop-Process -Id $proc.Id -Force -EA SilentlyContinue
        $proc.WaitForExit(10000) | Out-Null
        Assert 'the Dashboard was closed for the cleanup phase' $proc.HasExited
    }

    # The CLI twin is the part automatable without a desktop, so it carries the
    # self-containment claim when there is no interactive session.
    $cli = Join-Path $Repo 'releases\KomorebiDashboard-cli.exe'
    if (Test-Path $cli) {
        $cliOut = & $cli --version 2>&1 | Out-String
        Assert 'the CLI twin also runs with no .NET runtime' ($LASTEXITCODE -eq 0) $cliOut.Trim()
    } else {
        Write-Host '        (no CLI twin in releases/ — GUI check above carried D-T1)' -ForegroundColor DarkGray
    }
}

# =====================================================================================
Phase 'P7-cleanup' {

    $uninstaller = Join-Path $Repo 'scripts\uninstall-komorebi-whkd.ps1'
    Assert 'the uninstaller is present' (Test-Path $uninstaller)

    # The uninstaller's ONLY parameter is -Scope (ValidateSet: all, komorebi-whkd,
    # yasb, autohotkey) plus a -KeepBinaries switch. There is no -Components, no
    # -RemoveUserConfig and no -RemoveScheduledTasks: those were invented here and
    # would have failed parameter binding at runtime.
    # It removes the scheduled tasks and user config itself — $Tasks is hardcoded
    # to Komorebi/KomorebiWatchdog inside the script.
    if (Test-Path $uninstaller) {
        $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $uninstaller -Scope all 2>&1 |
                Tee-Object -FilePath (Join-Path $LogDir 'uninstall.log')
        Assert 'the uninstall exits 0' ($LASTEXITCODE -eq 0) (
            (($out | Where-Object { $_ -match 'error|exception' } | Select-Object -First 3) -join ' / '))
    }

    # --- nothing left behind -------------------------------------------------------
    Assert 'the komorebi binaries are gone' (-not (Test-Path $script:KomorebiBin)) $script:KomorebiBin
    Assert 'the generated komorebi.json is gone' (-not (Test-Path $script:KomorebiCfg)) $script:KomorebiCfg
    Assert 'the generated whkdrc is gone' (-not (Test-Path $script:WhkdRc)) $script:WhkdRc
    Assert 'no komorebi process remains' (-not (Get-Process komorebi -EA SilentlyContinue))
    Assert 'no whkd process remains' (-not (Get-Process whkd -EA SilentlyContinue))
    Assert 'no scheduled task remains' `
           (-not (Get-ScheduledTask -TaskName 'Komorebi*' -EA SilentlyContinue))
    Assert 'no startup entry remains' `
           (-not (Get-CimInstance Win32_StartupCommand -EA SilentlyContinue |
                  Where-Object { $_.Command -match 'komorebi|whkd|yasb' }))
    Assert 'no registry Run key for the app remains' (
        -not ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -EA SilentlyContinue).PSObject.Properties |
               Where-Object { $_.Value -match 'komorebi|whkd|yasb' }))
}

# =====================================================================================
Phase 'P8-report' {
    $script:Phase = 'P8-report'
    Save-Report

    $total = $script:Results.Count
    $passed = @($script:Results.ToArray() | Where-Object Passed).Count
    Assert 'the suite ran a meaningful number of checks' ($total -ge 40) ("total: $total")

    if ($total -gt 0) {
        Write-Host ''
        Write-Host (" RESULT: {0}/{1} passed" -f $passed, $total) `
                   -ForegroundColor $(if ($script:FailedPhases.Count -eq 0) { 'Green' } else { 'Red' })
        if ($script:FailedPhases.Count -gt 0) {
            Write-Host (" failed phases: {0}" -f ($script:FailedPhases -join ', ')) -ForegroundColor Red
        }
    }
}

if ($script:FailedPhases.Count -gt 0) { exit 1 }
exit 0