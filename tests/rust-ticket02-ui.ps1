# rust-ticket02-ui.ps1
#
# Rendered-UI verification for ticket 02 (the execution contract). Ticket 01's
# suite proves the window renders and one click streams; it deliberately says
# nothing about stopping a run. This suite drives the real Cancel button and reads
# what the console pane actually shows afterwards.
#
# Why a separate file rather than more assertions in the ticket-01 suite: ticket
# 01 has already been reviewed and committed, and its evidence should keep
# describing exactly the build it was written against. Ticket 02's evidence lives
# here, so neither suite can silently invalidate the other's history.
#
# Two WebView2 facts this relies on (both learned the hard way in ticket 01):
#   1. The accessibility tree materialises seconds after the window appears, so
#      every assertion waits for the tree rather than for the window alone.
#   2. WebView2 exposes the DOM as ordinary automation elements. Names are read
#      from those elements; a WPF-style control tree is not assumed.
#
# Usage:
#   pwsh -File tests/rust-ticket02-ui.ps1
#   pwsh -File tests/rust-ticket02-ui.ps1 -ExePath <path> -EvidenceDir <dir>
#
# Exit codes: 0 all checks passed, 1 at least one failed, 2 no window appeared.

[CmdletBinding()]
param(
    [string]$ExePath = (Join-Path $PSScriptRoot '..\releases\rust\KomorebiDashboard.exe'),
    [string]$EvidenceDir = (Join-Path $PSScriptRoot '..\test-results\rust-ticket02-ui')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

# Teardown is scoped to the tree this script started: the app's WebView2 children
# must die with it, and nothing else on the machine may be touched. Never solve
# this by name — a machine-wide `Stop-Process msedgewebview2` would kill other
# applications' web views.
function Stop-LaunchedTree {
    param([int]$Id)
    if ($Id -le 0) { return }
    & taskkill.exe /PID $Id /T /F 2>&1 | Out-Null
}

# Pids of PowerShell processes actually running our fixture, matched on the command
# line so an unrelated PowerShell is never asserted about.
function Get-FixturePids {
    $cim = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' or Name='pwsh.exe'" -ErrorAction SilentlyContinue
    @($cim | Where-Object { $_.CommandLine -like '*demo-stream.ps1*' } | Select-Object -ExpandProperty ProcessId)
}

# A kill is asynchronous, so a slow reap must not be mistaken for a survivor.
function Wait-ForNoFixture {
    param([int]$Seconds = 30)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        if (@(Get-FixturePids).Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $false
}

if (-not (Test-Path -LiteralPath $ExePath)) { throw "executable not found: $ExePath" }
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

$UIA = [System.Windows.Automation.AutomationElement]
$Scope = [System.Windows.Automation.TreeScope]
$AnyCondition = [System.Windows.Automation.Condition]::TrueCondition

$results = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    $results.Add([pscustomobject]@{ check = $Name; passed = [bool]$Condition; detail = $Detail })
    if ($Condition) { Write-Output ("PASS  {0}" -f $Name) }
    else {
        Write-Output ("FAIL  {0}  [{1}]" -f $Name, $Detail)
        $failures.Add($Name)
    }
}

function Get-Snapshot {
    param($Window)
    $nodes = @()
    foreach ($e in $Window.FindAll($Scope::Descendants, $AnyCondition)) {
        $nodes += [pscustomobject]@{
            Type    = $e.Current.ControlType.ProgrammaticName -replace 'ControlType\.', ''
            Name    = $e.Current.Name
            Element = $e
        }
    }
    return $nodes
}

function Get-Blob {
    param($Snapshot)
    return (($Snapshot | ForEach-Object { $_.Name }) -join "`n")
}

function Find-Node {
    param($Snapshot, [string]$Type, [string]$Name)
    foreach ($n in $Snapshot) {
        if ($n.Type -eq $Type -and $n.Name -eq $Name) { return $n }
    }
    return $null
}

function Wait-For {
    param([scriptblock]$Probe, [int]$TimeoutSeconds = 40, [int]$IntervalMs = 250)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $value = & $Probe
        if ($value) { return $value }
        Start-Sleep -Milliseconds $IntervalMs
    }
    return $null
}

function Invoke-Node {
    param($Node)
    ($Node.Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
}

# ------------------------------------------------------------------ launch
Write-Output ("launching {0}" -f (Resolve-Path -LiteralPath $ExePath))
$started = Get-Date
$proc = Start-Process -FilePath $ExePath -PassThru
if (-not $proc) {
    $results | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $EvidenceDir 'ui-results.json') -Encoding UTF8
    exit 2
}

$pidCond = New-Object System.Windows.Automation.PropertyCondition($UIA::ProcessIdProperty, $proc.Id)
$window = Wait-For -TimeoutSeconds 45 -IntervalMs 100 -Probe {
    $UIA::RootElement.FindFirst($Scope::Children, $pidCond)
}

if (-not $window) {
    Write-Output 'FAIL  the window never appeared within 45s'
    $results.Add([pscustomobject]@{ check = 'window appears'; passed = $false; detail = 'no top-level window' })
    $results | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $EvidenceDir 'ui-results.json') -Encoding UTF8
    Stop-LaunchedTree -Id $proc.Id
    exit 2
}
Write-Output ("window appeared after {0} ms" -f [int]((Get-Date) - $started).TotalMilliseconds)

$cancelMs = 0
try {
    $snapshot = Wait-For -TimeoutSeconds 60 -IntervalMs 500 -Probe {
        $snap = Get-Snapshot -Window $window
        if (Find-Node $snap 'Button' 'Stream') { return $snap }
        return $null
    }
    if (-not $snapshot) { $snapshot = Get-Snapshot -Window $window }

    $collect = {
        param($s, $t, $n)
        (($s | Where-Object { $_.Type -eq $t -and $_.Name -eq $n }) | Measure-Object).Count
    }

    # ---- the Cancel affordance is absent while there is nothing to cancel.
    # It is rendered only for a live run, so its absence is the idle state: a
    # button that is present but inert would invite clicks that do nothing.
    Assert-That 'no Cancel action is offered while nothing is running' (
        (& $collect $snapshot 'Button' 'Cancel') -eq 0) 'a Cancel button was rendered with no run in flight'
    Assert-That 'the console starts with a ready status and no output' (
        (Get-Blob -Snapshot $snapshot) -match 'No output yet' -and (Get-Blob -Snapshot $snapshot) -match 'Ready') (
        'idle console state not rendered')

    $fixtureBefore = @(Get-FixturePids).Count

    # ------------------------------------------------- a run, then a real cancel
    $stream = Find-Node $snapshot 'Button' 'Stream'
    $valueBox = (Get-Snapshot -Window $window | Where-Object { $_.Type -eq 'Edit' } | Select-Object -First 1)
    if ($valueBox) {
        # 600 lines at the fixture's default 100 ms is over a minute of work, so
        # the run cannot finish on its own inside this test.
        ($valueBox.Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)).SetValue('600')
    }

    $clicked = Get-Date
    Invoke-Node $stream

    $running = Wait-For -TimeoutSeconds 60 -IntervalMs 250 -Probe {
        $snap = Get-Snapshot -Window $window
        $text = Get-Blob -Snapshot $snap
        $cancel = Find-Node $snap 'Button' 'Cancel'
        if ($text -notmatch 'No output yet' -and $cancel -and $cancel.Element.Current.IsEnabled) { return $snap }
        return $null
    }
    Assert-That 'streaming starts and Cancel becomes offered' ($null -ne $running) (
        'the run never began streaming, or Cancel never became enabled')

    # The window must stay alive and responsive while output is streaming.
    Assert-That 'the window is still responsive while the run streams' (
        $null -ne $running -and -not $proc.HasExited) 'the process died during the run'

    $cancelled = $null
    if ($running) {
        $cancel = Find-Node $running 'Button' 'Cancel'
        Invoke-Node $cancel
        $cancelled = Wait-For -TimeoutSeconds 60 -IntervalMs 250 -Probe {
            $snap = Get-Snapshot -Window $window
            if ((Get-Blob -Snapshot $snap) -match 'CANCELLED') { return $snap }
            return $null
        }
        $cancelMs = [int]((Get-Date) - $clicked).TotalMilliseconds
    }

    Assert-That 'clicking Cancel records the run as CANCELLED' ($null -ne $cancelled) (
        'no CANCELLED verdict appeared within 60 s of the click')

    if ($cancelled) {
        $text = Get-Blob -Snapshot $cancelled
        Set-Content -Path (Join-Path $EvidenceDir 'ui-cancel-text.txt') -Value $text -Encoding UTF8
        Assert-That 'a cancelled run is never reported as FAILED or TIMED OUT' (
            $text -notmatch 'FAILED' -and $text -notmatch 'TIMED OUT') (
            'cancellation collapsed into another verdict')
        Assert-That 'the cancelled run surfaces its own exit code' ($text -match 'exit 130') (
            'exit 130 was not shown for the cancelled run')
        Assert-That 'the streamed output before the stop is preserved' (
            $text -match '(?i)demo-stream') 'no streamed output survived the cancel'
        Write-Output ("cancel-to-verdict elapsed {0} ms" -f $cancelMs)
    }

    # ---- no orphan, on the real cancel path
    $drained = Wait-ForNoFixture -Seconds 30
    $fixtureAfter = @(Get-FixturePids).Count
    Assert-That 'no orphaned PowerShell survives the in-window cancel' ($drained -and $fixtureAfter -eq 0) (
        'fixture pids before={0} after={1}' -f $fixtureBefore, $fixtureAfter)

    # ---- after a stop the app is immediately usable again: the Cancel action is
    # withdrawn once the run has a verdict, and the rows are available to start a
    # new run.
    $readyAgain = Wait-For -TimeoutSeconds 30 -IntervalMs 250 -Probe {
        $snap = Get-Snapshot -Window $window
        $cancel = Find-Node $snap 'Button' 'Cancel'
        $stream = Find-Node $snap 'Button' 'Stream'
        if (-not $cancel -and $stream -and $stream.Element.Current.IsEnabled) { return $snap }
        return $null
    }
    Assert-That 'Cancel is withdrawn once the run has a verdict' ($null -ne $readyAgain) (
        'Cancel was still offered after the run ended')

    $named = @($UIA::RootElement.FindAll($Scope::Children, $pidCond) | Where-Object { $_.Current.Name })
    Assert-That 'exactly one dashboard window exists' ($named.Count -eq 1) (
        'named top-level windows: {0}' -f $named.Count)
}
finally {
    Stop-LaunchedTree -Id $proc.Id
}

$payload = [ordered]@{
    executable  = (Resolve-Path -LiteralPath $ExePath).Path
    cancelMs    = $cancelMs
    checks      = $results
    failures    = @($failures)
}
$payload | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $EvidenceDir 'ui-results.json') -Encoding UTF8

Write-Output ''
if ($failures.Count -gt 0) {
    Write-Output ("FAILED: {0} of {1} checks" -f $failures.Count, $results.Count)
    exit 1
}
Write-Output ("PASSED: all {0} rendered-UI checks" -f $results.Count)
exit 0