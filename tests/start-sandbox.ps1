#Requires -Version 5.1
<#
=============================================================================================
komorebi-1click — SANDBOX ROUND-TRIP LAUNCHER (ticket 14)

WHY THIS EXISTS
    Verification splits in two, because the two halves cannot share a machine:

      verify-readonly.ps1        READS only. Safe on the real machine.
      sandbox-verify-install.ps1 INSTALLS, RESTARTS and UNINSTALLS.
                                   Sandbox or a throwaway VM, never the real machine.

    To run the second half you must get a disposable Windows with the repo mounted
    inside it, run the suite, and get the report back out. Doing that by hand is
    exactly where it quietly stops being done. This script does the whole round
    trip in one command and copies the report to the HOST when it finishes.

    Windows Sandbox is also DISPOSABLE BY DESIGN: everything the installer writes
    into the sandbox (Program Files, the generated config, the scheduled tasks)
    vanishes when the session closes. That is what makes it the right place to
    verify "clean install, then leave no trace" for real rather than in theory.

HOW IT WORKS
    1. writes a temporary .wsb that mounts this repo READ/WRITE (read-write, so the
       installer's own state files land where the suite expects them)
    2. launches WindowsSandbox.exe with it
    3. a bootstrap script inside the sandbox runs the suite and writes the report
    4. the results land in the mounted folder, i.e. back on the host, and are
       printed here

PREREQUISITES
    * Windows 11 Pro/Enterprise/Education (Sandbox needs Pro+), or the VM fallback
    * Windows Sandbox optional feature enabled
    * this repo on a LOCAL disk — Sandbox cannot map a network drive or \\wsl$

    Enable once, as Administrator:
        Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM

    If Sandbox is unavailable, use a throwaway VM instead: mount the repo, run
    tests\\sandbox-verify-install.ps1, and copy %LogDir% back out.

USAGE
    .\\tests\\start-sandbox.ps1                       # full round trip
    .\\tests\\start-sandbox.ps1 -KeepOpen            # leave the sandbox up to poke at
    .\\tests\\start-sandbox.ps1 -ReadExistingReport  # just print the last report

NOTHING HERE TOUCHES THE HOST SYSTEM. The only host-side write is this repo's
own test-results folder.
=============================================================================================
#>

[CmdletBinding()]
param(
    # Where to drop the results once the sandbox finishes.
    [string] $OutDir = (Join-Path $PSScriptRoot '..\test-results'),

    # Do not close the sandbox when the run finishes (for manual poking).
    [switch] $KeepOpen,

    # Just re-print the most recent report; does not launch anything.
    [switch] $ReadExistingReport
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ResultDir = Join-Path $RepoRoot 'test-results'
$JsonPath = Join-Path $ResultDir 'verification-result.json'

function Show-Report {
    param([string] $Path)
    if (-not (Test-Path $Path)) {
        Write-Host "No report at: $Path" -ForegroundColor Yellow
        return $false
    }

    $r = Get-Content $Path -Raw | ConvertFrom-Json
    Write-Host ''
    Write-Host '=====================================================================' -ForegroundColor White
    Write-Host (" sandbox verification — {0}" -f $r.machine) -ForegroundColor White
    Write-Host '=====================================================================' -ForegroundColor White
    Write-Host (" os        : {0} ({1})" -f $r.os, $r.osVersion)
    Write-Host (" started   : {0}" -f $r.startedUtc)
    Write-Host (" duration  : {0}s" -f $r.durationSec)
    Write-Host (" RESULT    : {0} passed, {1} failed, {2} total" -f $r.passed, $r.failed, $r.total)
    if ($r.total -eq 0) { Write-Host ' (no checks were recorded)' -ForegroundColor Yellow }
    if (@($r.failedPhases).Count -gt 0) {
        Write-Host (" bad phases: {0}" -f (@($r.failedPhases) -join ', ')) -ForegroundColor Red
    }

    # If `checks` is missing or empty, say so instead of reporting success from an
    # empty set. A report with no checks would otherwise read as "0 failed".
    $checks = @($r.checks)
    if ($checks.Count -eq 0) {
        Write-Host ' NOTE: the report contains no checks — the suite did not get far enough.' -ForegroundColor Yellow
    }

    $fails = @($checks | Where-Object { -not $_.Passed })
    if ($fails.Count -gt 0) {
        Write-Host ''
        Write-Host ' failing checks:' -ForegroundColor Red
        foreach ($f in $fails) {
            $d = if ($f.Detail) { "  <- $($f.Detail)" } else { '' }
            Write-Host ("   [{0}] {1}{2}" -f $f.Phase, $f.Label, $d) -ForegroundColor Red
        }
    }
    Write-Host ''
    return ($r.failed -eq 0)
}

if ($ReadExistingReport) {
    if (Show-Report -Path $JsonPath) { exit 0 } else { exit 1 }
}

# =====================================================================================
Write-Host '=====================================================================' -ForegroundColor White
Write-Host ' komorebi-1click — launching Windows Sandbox' -ForegroundColor White
Write-Host '=====================================================================' -ForegroundColor White

# --- 1. can we even do this? ------------------------------------------------------------
$sandboxExe = "$env:SystemRoot\System32\WindowsSandbox.exe"
if (-not (Test-Path $sandboxExe)) {
    Write-Host ''
    Write-Host ' Windows Sandbox is not available on this machine.' -ForegroundColor Red
    Write-Host ''
    Write-Host ' Options, in order of preference:' -ForegroundColor White
    Write-Host '   1. Enable it (Administrator, once):'
    Write-Host '        Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM'
    Write-Host '      (requires Windows 11 Pro/Enterprise/Education)'
    Write-Host '   2. Use a throwaway VM instead:'
    Write-Host '      - share this folder into the VM'
    Write-Host ("      - run: pwsh -File `"$(Join-Path $RepoRoot 'tests\sandbox-verify-install.ps1')`"")
    Write-Host '      - copy the report back out'
    Write-Host ''
    Write-Host ' The read-only half runs anywhere, no sandbox needed:' -ForegroundColor Cyan
    Write-Host ("   pwsh -File `"$(Join-Path $RepoRoot 'tests\verify-readonly.ps1')`"")
    exit 2
}

# --- 2. refuse a repo Sandbox cannot mount ------------------------------------------------
# Sandbox maps local fixed drives only. A UNC or \\wsl$ path fails deep inside the
# container with an unhelpful error, so it is worth catching here with a clear one.
if ($RepoRoot -match '^\\\\' -or $RepoRoot -match '^\\\\wsl\$') {
    Write-Host ''
    Write-Host " This repo is on a network or WSL path:" -ForegroundColor Red
    Write-Host "   $RepoRoot"
    Write-Host ' Windows Sandbox can only map a LOCAL folder. Copy the repo to a local'
    Write-Host ' drive (e.g. C:\src\komorebi-1click) and run this again.'
    exit 2
}

# --- 3. build the bootstrap + config ----------------------------------------------------
if (-not (Test-Path $ResultDir)) { New-Item -ItemType Directory -Path $ResultDir -Force | Out-Null }

# The bootstrap runs INSIDE the sandbox. It is written into the repo folder, which
# the .wsb maps, so the sandbox can see it without any second copy step.
$bootstrap = Join-Path $RepoRoot 'tests\sandbox-bootstrap.ps1'
if (-not (Test-Path $bootstrap)) {
    Write-Host "Missing bootstrap: $bootstrap" -ForegroundColor Red
    exit 2
}

$wsb = Join-Path $env:TEMP 'komorebi-verify.wsb'
@"
<Configuration>
  <VGpu>Disable</VGpu>
  <Networking>Default</Networking>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$RepoRoot</HostFolder>
      <SandboxFolder>C:\komorebi-src</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\komorebi-src\tests\sandbox-bootstrap.ps1</Command>
  </LogonCommand>
</Configuration>
"@ | Set-Content -Path $wsb -Encoding UTF8

Write-Host (" repo   : {0}" -f $RepoRoot)
Write-Host (" config : {0}" -f $wsb)
Write-Host (" results: {0}" -f $ResultDir)
Write-Host ''
Write-Host ' Launching. The sandbox installs and uninstalls inside itself; when it'
Write-Host ' closes, everything it wrote is already gone.'
Write-Host ''

# --- 4. clear stale results AND the sandbox marker ------------------------------
# The marker matters more than the reports: the suite's guard treats it as proof
# it is running inside a sandbox. A marker left over from a previous session would
# let a later run satisfy signal 1 on the HOST, so it must be cleared here, every
# time, immediately before the sandbox is launched.
foreach ($f in @('verification-result.json', 'verification-result.txt',
                 'bootstrap-failure.json', '.sandbox-marker')) {
    $p = Join-Path $ResultDir $f
    if (Test-Path $p) { Remove-Item $p -Force; Write-Host "  cleared stale $f" -ForegroundColor DarkGray }
}

# --- 5. run ----------------------------------------------------------------------------
$proc = Start-Process -FilePath $sandboxExe -ArgumentList $wsb -PassThru

if ($KeepOpen) {
    Write-Host ' Sandbox left open (-KeepOpen). Close it when finished.' -ForegroundColor Cyan
    Write-Host ' To read the report:  .\tests\start-sandbox.ps1 -ReadExistingReport'
    return
}

# Wait for the sandbox to close. A Sandbox session that exits early (feature off,
# no memory, refused by policy) must not hang this forever, so it is bounded.
Write-Host ' Waiting for the sandbox session to finish (Ctrl+C to stop waiting)...' -ForegroundColor DarkGray
$deadline = (Get-Date).AddMinutes(45)
while (-not $proc.HasExited) {
    if ((Get-Date) -gt $deadline) {
        Write-Host ''
        Write-Host ' Timed out after 45 minutes with the sandbox still open.' -ForegroundColor Yellow
        Write-Host ' The report is written by the sandbox itself, so close it to finish the run.'
        break
    }
    Start-Sleep -Seconds 10
}

# The report is written by the sandbox into the mapped folder, i.e. onto the host.
if (Test-Path $JsonPath) {
    Write-Host ''
    Write-Host ' Sandbox closed — reading the report it left behind:' -ForegroundColor Cyan
    if (Show-Report -Path $JsonPath) {
        Write-Host ' Every destructive check passed, and the sandbox is already gone.' -ForegroundColor Green
        exit 0
    } else {
        Write-Host ' The suite ran but some checks failed. See the list above.' -ForegroundColor Red
        exit 1
    }
}

Write-Host ''
Write-Host ' No report was produced.' -ForegroundColor Red
Write-Host ' The sandbox may not have reached the suite. Check inside it:'
Write-Host ("   pwsh -File C:\komorebi-src\tests\sandbox-verify-install.ps1")
exit 1