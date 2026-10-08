# rust-ticket01-ui.ps1
#
# Runtime verification of the Rust + Tauri dashboard's window, driven through UI
# Automation so it reports what is actually on screen rather than what the markup
# claims. Ticket 01's acceptance requires a visible header, one tab, both rows and
# a real click that streams to completion; a build that links is not evidence of
# any of those, and the WPF build's history (defect D21, a window that launched
# completely blank) is why this check exists at all.
#
# Two things about WebView2 that this script encodes, because getting them wrong
# produces false failures rather than real ones:
#   1. The accessibility tree materialises a few seconds AFTER the window appears.
#      Every assertion therefore waits for the tree, never for the window alone.
#   2. WebView2 exposes the DOM as ordinary automation elements (Text, TabItem,
#      Button, Edit, Document). Assertions read those names; they do not assume a
#      WPF-style control tree.
#
# Usage:
#   pwsh -File tests/rust-ticket01-ui.ps1
#   pwsh -File tests/rust-ticket01-ui.ps1 -ExePath <path> -EvidenceDir <dir>
#
# Exit codes: 0 all checks passed, 1 at least one failed, 2 no window appeared.

[CmdletBinding()]
param(
    [string]$ExePath = (Join-Path $PSScriptRoot '..\releases\rust\KomorebiDashboard.exe'),
    [string]$EvidenceDir = (Join-Path $PSScriptRoot '..\test-results\rust-ticket01')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

# Teardown is scoped to the process tree this script itself started: the app's
# WebView2 children must die with it, and nothing else on the machine may be
# touched. Never solve this by name (a machine-wide `Stop-Process msedgewebview2`
# would kill other applications' web views).
function Stop-LaunchedTree {
    param([int]$Id)
    if ($Id -le 0) { return }
    & taskkill.exe /PID $Id /T /F 2>&1 | Out-Null
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

# One uniform enumeration for everything. Reading the type from the element
# instead of asking for one control type at a time is what keeps the text, button
# and edit assertions consistent with each other.
function Get-Snapshot {
    param($Window)
    $nodes = @()
    foreach ($e in $Window.FindAll($Scope::Descendants, $AnyCondition)) {
        $nodes += [pscustomobject]@{
            Type = $e.Current.ControlType.ProgrammaticName -replace 'ControlType\.', ''
            Name = $e.Current.Name
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

# ------------------------------------------------------------------ launch
Write-Output ("launching {0}" -f (Resolve-Path -LiteralPath $ExePath))
$started = Get-Date
$proc = Start-Process -FilePath $ExePath -PassThru
if (-not $proc) {
    $results | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $EvidenceDir 'ui-results.json') -Encoding UTF8
    exit 2
}

# 100 ms polling: a coarse interval would report the polling granularity as the
# app's startup time.
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
$timeToWindowMs = [int]((Get-Date) - $started).TotalMilliseconds
Write-Output ("window appeared after {0} ms (upper bound: poll interval is 100 ms)" -f $timeToWindowMs)

try {
    # ---- wait for the accessibility tree to materialise
    $snapshot = Wait-For -TimeoutSeconds 60 -IntervalMs 500 -Probe {
        $snap = Get-Snapshot -Window $window
        if (Find-Node $snap 'Button' 'Check') { return $snap }
        return $null
    }
    if (-not $snapshot) { $snapshot = Get-Snapshot -Window $window }

    $blob = Get-Blob -Snapshot $snapshot
    $types = $snapshot | ForEach-Object { $_.Type } | Sort-Object -Unique
    Write-Output ("automation tree: {0} elements; types: {1}" -f $snapshot.Count, ($types -join ', '))

    $collect = {
        param($s, $t, $n)
        (($s | Where-Object { $_.Type -eq $t -and $_.Name -eq $n }) | Measure-Object).Count
    }

    # ---- the window is a real, non-blank UI (D21 regression guard)
    Assert-That 'the window appeared and has content' ($blob.Trim().Length -gt 0) (
        'rendered text length {0}' -f $blob.Trim().Length)

    # ---- header: logo alternative text is empty by design, so identity is text
    Assert-That 'header shows the product name' ($blob -match 'Komorebi Admin Dashboard') 'product name not in rendered text'
    Assert-That 'header shows the component list' ($blob -match 'WHKD.*YASB.*AutoHotkey') 'component list not in rendered text'
    Assert-That 'header shows the build version' ($blob -match 'v\d+\.\d+\.\d+') 'no version string in rendered text'

    # ---- exactly one tab today, labelled by the registry's group
    Assert-That 'one tab is rendered and it is Debugging' (
        (& $collect $snapshot 'TabItem' 'Debugging') -eq 1 -and (& $collect $snapshot 'TabItem' 'Settings') -eq 0) (
        'TabItem nodes: {0}' -f (($snapshot | Where-Object Type -eq 'TabItem').Name -join ', '))
    Assert-That 'the tab shows its heading and description' (
        $blob -match 'Read-only health checks and the streaming test verb') 'tab description missing'

    # ---- the two registry rows, driven by one registry table
    Assert-That 'the Status row shows its label and help' (
        (& $collect $snapshot 'Text' 'Status') -ge 1 -and $blob -match 'Read-only health check') 'status row not rendered'
    Assert-That "the Status row's button carries the verb's action label (Check)" (
        (& $collect $snapshot 'Button' 'Check') -eq 1) 'no button named Check'
    Assert-That 'the Demo Stream row shows its label and help' (
        (& $collect $snapshot 'Text' 'Demo Stream') -ge 1 -and $blob -match 'proves no-lag streaming') 'demo-stream row not rendered'
    Assert-That "the Demo Stream row's button carries the verb's action label (Stream)" (
        (& $collect $snapshot 'Button' 'Stream') -eq 1) 'no button named Stream'
    Assert-That 'exactly two verbs are offered' (
        (& $collect $snapshot 'Button' 'Check') + (& $collect $snapshot 'Button' 'Stream') -eq 2) (
        'expected the two tracer verbs only')

    # ---- read-only badge, present on exactly the read-only rows
    $badges = (& $collect $snapshot 'Text' 'READ-ONLY')
    Assert-That 'both read-only verbs are badged' ($badges -ge 2) ('READ-ONLY badges: {0}' -f $badges)
    Assert-That 'no row button is a generic Run' ((& $collect $snapshot 'Button' 'Run') -eq 0) 'a row rendered a generic Run button'

    # ---- the value box appears for the verb that takes a value, and only that one
    $edits = ($snapshot | Where-Object Type -eq 'Edit')
    Assert-That 'exactly the argument-taking row offers a value box' ($edits.Count -eq 1) (
        'edit controls: {0}' -f (($edits.Name) -join ', '))
    Assert-That 'the value box belongs to the Demo Stream row' (
        ($edits | Where-Object { $_.Name -match 'Demo Stream' } | Measure-Object).Count -eq 1) 'value box not labelled for its row'

    # ---- console pane, shared and present
    Assert-That 'the console pane is present with its Clear action' (
        (& $collect $snapshot 'Text' 'Console') -ge 1 -and (& $collect $snapshot 'Button' 'Clear') -eq 1) 'console header or Clear button missing'
    Assert-That 'the console starts empty with a ready status line' (
        $blob -match 'No output yet' -and $blob -match 'Ready' -and $blob -match '0 lines') 'empty-console state not rendered'

    # ------------------------------------------------- the real click
    $check = Find-Node $snapshot 'Button' 'Check'
    $clicked = Get-Date
    ($check.Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()

    $after = Wait-For -TimeoutSeconds 120 -IntervalMs 250 -Probe {
        $snap = Get-Snapshot -Window $window
        $text = Get-Blob -Snapshot $snap
        if ($text -match 'exit 0' -and $text -match 'succeeded') { return $snap }
        return $null
    }
    $clickMs = [int]((Get-Date) - $clicked).TotalMilliseconds

    Assert-That 'clicking Check runs the script, streams it and reports exit 0' ($null -ne $after) (
        'no "exit 0" + "succeeded" status within 120 s; elapsed {0} ms' -f $clickMs)

    if ($after) {
        $text = Get-Blob -Snapshot $after
        Set-Content -Path (Join-Path $EvidenceDir 'ui-console-text.txt') -Value $text -Encoding UTF8
        Assert-That 'the console shows the streamed script output, not a placeholder' (
            $text -notmatch 'No output yet' -and $text -match '(?i)komorebi|service|status|task') 'streamed text did not look like script output'
        Assert-That 'the status line reports a line count after the run' ($text -match '\d+ lines') 'no line count after the run'
        Assert-That 'the verdict is not a failure' ($text -notmatch 'FAILED|TIMED OUT') 'the run reported a failure state'
        Write-Output ("click-to-verdict elapsed {0} ms" -f $clickMs)
    }

    Assert-That 'the window stayed alive and responsive through the run' (-not $proc.HasExited) 'the process exited during the run'

    # A Tauri app also owns a windowless 'Tao Thread Event Target' window (its
    # message loop). Only named windows are UI, so only those are counted.
    $named = @($UIA::RootElement.FindAll($Scope::Children, $pidCond) | Where-Object { $_.Current.Name })
    Assert-That 'exactly one dashboard window exists' ($named.Count -eq 1) (
        'named top-level windows: {0} ({1})' -f $named.Count, (($named | ForEach-Object { $_.Current.Name }) -join ', '))
}
finally {
    Stop-LaunchedTree -Id $proc.Id
}

$payload = [ordered]@{
    executable     = (Resolve-Path -LiteralPath $ExePath).Path
    timeToWindowMs = $timeToWindowMs
    checks         = $results
    failures       = @($failures)
}
$payload | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $EvidenceDir 'ui-results.json') -Encoding UTF8

Write-Output ''
if ($failures.Count -gt 0) {
    Write-Output ("FAILED: {0} of {1} checks" -f $failures.Count, $results.Count)
    exit 1
}
Write-Output ("PASSED: all {0} rendered-UI checks" -f $results.Count)
exit 0
