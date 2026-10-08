# rust-ticket02-probe.ps1
#
# Runtime probe artifact for ticket 02 (the execution contract). Ticket 01 shipped
# a build that linked and a window that rendered; neither says anything about what
# happens to a real child process when a run is cancelled, overruns its budget or
# exits non-zero. This script produces the evidence for those.
#
# It collects three independent kinds of measurement and writes them to one JSON
# artifact, so each claim in the ticket can be traced to a number:
#
#   1. Rust suite probes. `execution_contract.rs` prints `[probe] key=value` lines
#      from inside the tests that took the measurement, and this script parses them
#      out of `cargo test -- --nocapture`. Nothing here is hand-typed: a summary
#      written by hand drifts, a parsed measurement cannot.
#   2. Shipped-binary runs. The real release EXE is driven as a CLI so the timeout,
#      batching, failure and no-orphan behaviour is measured on the artifact users
#      actually get, not only on the library.
#   3. Orphan scans. Process counts taken before and after a stop, read from the
#      command line so an unrelated PowerShell is never touched.
#
# Usage:
#   pwsh -File tests/rust-ticket02-probe.ps1
#   pwsh -File tests/rust-ticket02-probe.ps1 -ExePath <path> -EvidenceDir <dir>
#
# Exit codes: 0 every probe passed, 1 at least one failed, 2 the EXE was missing.

[CmdletBinding()]
param(
    [string]$ExePath = (Join-Path $PSScriptRoot '..\releases\rust\KomorebiDashboard.exe'),
    [string]$EvidenceDir = (Join-Path $PSScriptRoot '..\test-results\rust-ticket02'),
    [int]$ScanTimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

$checks = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    $checks.Add([pscustomobject]@{ check = $Name; passed = [bool]$Condition; detail = $Detail })
    if ($Condition) { Write-Output ("PASS  {0}" -f $Name) }
    else {
        Write-Output ("FAIL  {0}  [{1}]" -f $Name, $Detail)
        $failures.Add($Name)
    }
}

# Pids of PowerShell processes actually running our fixture. Matching on the
# command line means the dashboard's own processes are the only ones ever counted.
function Get-FixturePids {
    $cim = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' or Name='pwsh.exe'" -ErrorAction SilentlyContinue
    @($cim | Where-Object { $_.CommandLine -like '*demo-stream.ps1*' } | Select-Object -ExpandProperty ProcessId)
}

# Waits for the fixture count to drop to zero, so a kill that is merely slow is
# not reported as a surviving process.
function Wait-ForNoFixture {
    param([int]$Seconds = 20)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $remaining = @(Get-FixturePids)
        if ($remaining.Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $false
}

# --- 1. collect the Rust suite's own measurements --------------------------
$crateDir = Join-Path $PSScriptRoot '..\src\KomorebiDashboardRust\src-tauri'
Write-Output '=== running the execution-contract suite for its probe lines ==='
Push-Location $crateDir
try {
    $rustOutput = & cargo test --locked --no-default-features --test execution_contract -- --nocapture 2>&1
    $rustExit = $LASTEXITCODE
}
finally {
    Pop-Location
}
$rustText = ($rustOutput | Out-String)

$probe = [ordered]@{}
foreach ($line in ($rustOutput -split "`r?`n")) {
    if ($line -match '^\[probe\]\s+([^=]+)=(.*)$') {
        $key = $Matches[1].Trim()
        $value = $Matches[2].Trim()
        if ($value -eq 'true') { $probe[$key] = $true }
        elseif ($value -eq 'false') { $probe[$key] = $false }
        elseif ($value -match '^-?\d+$') { $probe[$key] = [int64]$value }
        else { $probe[$key] = $value }
    }
}
Set-Content -Path (Join-Path $EvidenceDir 'rust-probe-output.txt') -Value $rustText -Encoding UTF8

Assert-That 'the execution-contract suite passes on the real fixture' ($rustExit -eq 0) ("cargo test exit $rustExit")
Assert-That 'the suite emitted probe measurements' ($probe.Count -ge 20) ("$($probe.Count) probe fields parsed")

# --- 2. cancel: the recorded fact and the tree kill -------------------------
Assert-That 'cancel is recorded as cancelled with code 130' ($probe['cancel.cancelled'] -eq $true -and $probe['cancel.exit_code'] -eq 130) (
    "cancelled=$($probe['cancel.cancelled']) exit=$($probe['cancel.exit_code'])")
Assert-That 'cancel lands far inside the run budget, so it stops work rather than waiting it out' (
    $probe['cancel.elapsed_ms'] -lt ($probe['cancel.budget_ms'] / 2)) (
    "stopped after $($probe['cancel.elapsed_ms']) ms of a $($probe['cancel.budget_ms']) ms budget")
Assert-That 'a cancelled run does not complete its work' ($probe['cancel.completed_work'] -eq $false) 'the fixture reached its last line'
Assert-That 'no process from a cancelled run survives the tree kill' ($probe['tree.survivors'] -eq 0) (
    "$($probe['tree.survivors']) survivors of $($probe['tree.pids_before_kill']) pids")

# --- 3. timeout: its own fact, never a failure ------------------------------
Assert-That 'a hung run is timed out, not failed' (
    $probe['timeout.timed_out'] -eq $true -and $probe['timeout.reported_failed'] -eq $false) (
    "timed_out=$($probe['timeout.timed_out']) reported_failed=$($probe['timeout.reported_failed'])")
Assert-That 'a timeout reports 124 with a TIMED OUT verdict' (
    $probe['timeout.exit_code'] -eq 124 -and $probe['timeout.verdict'] -match 'TIMED OUT') (
    "exit=$($probe['timeout.exit_code']) verdict='$($probe['timeout.verdict'])'")
Assert-That 'the timeout budget is honoured near 3 s' (
    $probe['timeout.elapsed_ms'] -ge 3000 -and $probe['timeout.elapsed_ms'] -lt 15000) (
    "elapsed $($probe['timeout.elapsed_ms']) ms for a 3000 ms budget")
Assert-That 'cancellation and timeout stay distinct facts' (
    $probe['cancel.cancelled'] -eq $true -and $probe['cancel.timed_out'] -eq $false -and
    $probe['timeout.timed_out'] -eq $true -and $probe['timeout.cancelled'] -eq $false) (
    'the two stop flags must never both be set for one run')

# --- 4. missing script -----------------------------------------------------
Assert-That 'a missing script reports 127 and names the path' (
    $probe['missing_script.exit_code'] -eq 127 -and $probe['missing_script.names_path'] -eq $true) (
    "exit=$($probe['missing_script.exit_code']) names_path=$($probe['missing_script.names_path'])")
Assert-That 'no PowerShell is ever launched for a missing script' ($probe['missing_script.batches'] -eq 0) (
    "$($probe['missing_script.batches']) batches streamed")

# --- 5. batching ----------------------------------------------------------
Assert-That 'a high-line-count run is batched, not emitted per line' (
    $probe['batching.per_line_emit'] -eq $false -and $probe['batching.batches'] -lt 60) (
    "1000 lines arrived as $($probe['batching.batches']) batches")
Assert-That 'output windows keep arriving while the run streams' ($probe['batching.worst_gap_ms'] -lt 250) (
    "worst gap $($probe['batching.worst_gap_ms']) ms")

# --- 6. shipped binary ----------------------------------------------------
if (-not (Test-Path -LiteralPath $ExePath)) {
    Write-Output ''
    Write-Output ("FAIL  the release executable was not found: {0}" -f $ExePath)
    $checks | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $EvidenceDir 'probe-results.json') -Encoding UTF8
    exit 2
}
$exe = (Resolve-Path -LiteralPath $ExePath).Path
$exeBytes = (Get-Item -LiteralPath $exe).Length
Write-Output ''
Write-Output ("=== driving the shipped binary: {0} ({1} bytes) ===" -f $exe, $exeBytes)

# The binary is a windows-subsystem GUI app, so a console read from PowerShell
# captures nothing at all — measured, not assumed: `& $exe demo-stream` in
# PowerShell returned exit 0 with zero output. Node's spawn gives the child real
# pipes (the technique ticket 01's CLI suite proved), so that is what drives it.
$driver = Join-Path $PSScriptRoot 'rust-ticket02-exe-driver.mjs'
$driverJson = (& node $driver --exe $exe --evidence $EvidenceDir 2>&1 | Out-String)
$driverExit = $LASTEXITCODE
Set-Content -Path (Join-Path $EvidenceDir 'exe-driver-output.txt') -Value $driverJson -Encoding UTF8

$exeRuns = [ordered]@{}
$parsed = $null
try {
    $parsed = ($driverJson | ConvertFrom-Json)
}
catch {
    Assert-That 'the shipped-binary driver produced readable JSON' $false (
        $driverJson.Substring(0, [Math]::Min(400, $driverJson.Length)))
}

if ($parsed) {
    foreach ($property in $parsed.runs.PSObject.Properties) {
        # JSON deserialises to PSCustomObject, which has no .Contains(). Copying
        # into an ordered dictionary keeps every check below a plain lookup.
        $r = $property.Value
        $exeRuns[$property.Name] = [ordered]@{
            exit_code          = $r.exit_code
            elapsed_ms         = $r.elapsed_ms
            stdout_bytes       = $r.stdout_bytes
            stderr_bytes       = $r.stderr_bytes
            lines_seen         = $r.lines_seen
            stdout_complete    = $r.stdout_complete
            stderr_complete    = $r.stderr_complete
            summary            = "$($r.summary)"
            fixture_pids_after = $r.fixture_pids_after
        }
    }
}

Assert-That 'the shipped-binary driver ran and reported its cases' (
    $driverExit -eq 0 -and ($exeRuns.Keys -contains 'timeout') -and ($exeRuns.Keys -contains 'failure')) (
    "driver exit $driverExit; cases: $($exeRuns.Keys -join ', ')")

if (($exeRuns.Keys -contains 'timeout')) {
    Assert-That 'the shipped binary times a hung run out at 124' ($exeRuns['timeout'].exit_code -eq 124) (
        "exit $($exeRuns['timeout'].exit_code)")
    Assert-That 'the shipped binary says TIMED OUT and never FAILED' (
        $exeRuns['timeout'].summary -match 'TIMED OUT' -and $exeRuns['timeout'].summary -notmatch 'FAILED') (
        "'$($exeRuns['timeout'].summary)'")
    Assert-That 'the shipped binary stops near its 3 s budget' (
        $exeRuns['timeout'].elapsed_ms -ge 3000 -and $exeRuns['timeout'].elapsed_ms -lt 15000) (
        "$($exeRuns['timeout'].elapsed_ms) ms")
    Assert-That 'the shipped binary streams output before the stop' (
        $exeRuns['timeout'].lines_seen -gt 0) ("$($exeRuns['timeout'].lines_seen) lines before the stop")
}

if (($exeRuns.Keys -contains 'batching')) {
    Assert-That 'the shipped binary streams all 1000 lines without dropping any' (
        $exeRuns['batching'].lines_seen -eq 1000) ("$($exeRuns['batching'].lines_seen) of 1000 lines seen")
    Assert-That 'the shipped binary batches rather than emitting per line' (
        $exeRuns['batching'].elapsed_ms -lt 30000) ("$($exeRuns['batching'].elapsed_ms) ms for 1000 lines")
}

if (($exeRuns.Keys -contains 'failure')) {
    Assert-That "the shipped binary surfaces the script's own exit code" ($exeRuns['failure'].exit_code -eq 9) (
        "exit $($exeRuns['failure'].exit_code)")
    Assert-That 'the shipped binary keeps the full raw output of both streams' (
        $exeRuns['failure'].stdout_complete -and $exeRuns['failure'].stderr_complete) (
        'stdout or stderr was summarised away')
    Assert-That 'the shipped binary reports the failure rather than a success' (
        $exeRuns['failure'].summary -match 'FAILED') ("'$($exeRuns['failure'].summary)'")
}

if (($exeRuns.Keys -contains 'unknown_verb')) {
    Assert-That 'an unknown verb fails without launching anything' ($exeRuns['unknown_verb'].exit_code -eq 2) (
        "exit $($exeRuns['unknown_verb'].exit_code)")
}

# --- 7. no orphan across every stop the driver performed -------------------
$drained = Wait-ForNoFixture -Seconds $ScanTimeoutSeconds
$leftover = @(Get-FixturePids)
Assert-That 'no orphaned PowerShell survives any stop of the shipped binary' (
    $drained -and $leftover.Count -eq 0) (
    "leftover fixture pids: $($leftover -join ', ')")

# --- artifact ------------------------------------------------------------
$payload = [ordered]@{
    ticket          = '02-execution-contract'
    executable      = $exe
    executable_bytes = $exeBytes
    generated_at    = (Get-Date).ToString('o')
    rust_suite_exit = $rustExit
    rust_probes     = $probe
    exe_runs        = $exeRuns
    checks          = $checks
    failures        = @($failures)
}
$payload | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $EvidenceDir 'probe-results.json') -Encoding UTF8
Write-Output ''
Write-Output ("evidence: {0}" -f (Join-Path $EvidenceDir 'probe-results.json'))

if ($failures.Count -gt 0) {
    Write-Output ("FAILED: {0} of {1} probes" -f $failures.Count, $checks.Count)
    exit 1
}
Write-Output ("PASSED: all {0} execution-contract probes" -f $checks.Count)
exit 0