#Requires -Version 5.1
<#
.SYNOPSIS
    Komorebi-1click installer.

.DESCRIPTION
    Installs Komorebi (plus its access-denied patch), WHKD, YASB and AutoHotkey
    (v1 + v2) completely offline from the binaries committed to this repository.

    Every payload's SHA256 is verified before anything is installed. Each step
    detects the current state first and skips itself when the target is already
    present, so re-running this script always reaches the same end state.

    Entry points (all converge on this file):
      1. komorebi-1click-install.exe  (double-click; the wrapper elevates, then
         runs this script with -SkipElevationCheck)
      2. .\Install.ps1                (direct run; this script self-elevates
         through the UAC prompt when it is not already elevated)
      3. irm <url>/install.ps1 | iex  (bootstraps the repo, then re-execs this
         file; the same self-elevation applies afterwards)

    After the binaries, configuration generation, startup tasks and the
    AutoHotkey startup launcher complete the machine.

.NOTES
    All paths resolve from this script's own location, so the repository can be
    cloned anywhere. There are no machine-specific constants in this file.

    Exit codes: 0 success · 1 a primary component (or the payload verification)
    failed, or elevation could not be obtained · 2 configuration generation
    failed · 3 startup tasks failed · 4 the AutoHotkey launcher failed ·
    10 usable but incomplete (a secondary component failed).
#>

[CmdletBinding()]
param(
    # Skip the elevation check entirely. Intended for the EXE wrapper (it
    # elevates before it launches this script) and for automation.
    [switch]$SkipElevationCheck,

    # Verification mode (2026-10-10). The FULL pipeline runs - payload
    # integrity, installed state detection, config comparison - but every
    # mutating action becomes a "[DRY-RUN] would ..." line instead of an
    # action, so nothing is installed, written, or changed. This is the
    # sanctioned way to prove the installer on a live, working machine (the
    # Windows Sandbox suites cover the real-install path). The EXE wrapper
    # forwards arguments, so `komorebi-1click-install.exe -DryRun` works too.
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Capture the requested mode BEFORE the shared library is dot-sourced. The
# library initialises its own $DryRun flag in this same script scope, so the
# switch parameter is copied into a variable the library never touches; the
# banner and Set-InstallerDryRun below then use the captured value.
$script:DryRunRequested = [bool]$DryRun

# ---------------------------------------------------------------------------
# Bootstrapping: resolve the repository root and load the installer library.
# ---------------------------------------------------------------------------

# RepoRoot is the directory that contains this script. Never use the current
# working directory: a user double-clicking the wrapper starts in System32.
#
# `$PSScriptRoot` is correct for the two on-disk entry points (the EXE and a
# direct `.\Install.ps1`), but it is EMPTY under `irm ... | iex`, because that
# form runs the script from memory with no file behind it. Taking RepoRoot
# straight from $PSScriptRoot there resolved to nothing and the installer died
# on the very first Join-Path with a confusing error. So the in-memory case is
# detected explicitly and handled by fetching the repository archive, then
# re-executing the real Install.ps1 from disk. That keeps every decision in
# exactly one file: all three entry points converge on this same code path.
if ($PSScriptRoot) {
    $RepoRoot = $PSScriptRoot
} else {
    # `irm | iex` path. Two overrides exist, in priority order:
    #   $env:KOMOREBI_1CLICK_ROOT  an already-cloned local repository
    #   $env:KOMOREBI_1CLICK_URL   the base URL the script was fetched from
    $bootstrapRoot = $env:KOMOREBI_1CLICK_ROOT
    if (-not $bootstrapRoot) {
        $baseUrl = $env:KOMOREBI_1CLICK_URL
        if (-not $baseUrl) { $baseUrl = 'https://github.com/davoodya/komorebi-1click/releases/latest' }

        # Keep the repository beside the user's other local installs rather than
        # in TEMP, so a re-run can reuse it and the installed system stays
        # inspectable afterwards.
        $bootstrapRoot = Join-Path $env:LOCALAPPDATA 'komorebi-1click'
        if (-not (Test-Path -LiteralPath (Join-Path $bootstrapRoot 'scripts\Install-Common.ps1'))) {
            $zip = Join-Path $env:TEMP 'komorebi-1click.zip'
            $archive = "$baseUrl/download/komorebi-1click.zip"
            Write-Host "[bootstrap] fetching $archive" -ForegroundColor Cyan
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $archive -OutFile $zip -UseBasicParsing

            $staging = Join-Path $env:TEMP ('komorebi-1click-extract-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
            Expand-Archive -LiteralPath $zip -DestinationPath $staging -Force
            Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

            # A GitHub source/asset ZIP wraps everything in one top-level folder.
            $extracted = Get-ChildItem -LiteralPath $staging -Directory | Select-Object -First 1
            $inner = if ($extracted) { $extracted.FullName } else { $staging }

            if (Test-Path -LiteralPath $bootstrapRoot) {
                Remove-Item -LiteralPath $bootstrapRoot -Recurse -Force
            }
            New-Item -ItemType Directory -Path (Split-Path $bootstrapRoot -Parent) -Force | Out-Null
            Move-Item -LiteralPath $inner -Destination $bootstrapRoot
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $RepoRoot = $bootstrapRoot

    # Re-exec the on-disk installer so the real work runs from a real file with
    # $PSScriptRoot set. The bootstrap itself only ever gets to run this once.
    $realInstaller = Join-Path $RepoRoot 'Install.ps1'
    if (-not (Test-Path -LiteralPath $realInstaller)) {
        throw "bootstrap failed: no Install.ps1 under '$RepoRoot'."
    }
    Write-Host "[bootstrap] handing over to $realInstaller" -ForegroundColor Cyan
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $realInstaller @PSBoundParameters
    exit $LASTEXITCODE
}

. (Join-Path $RepoRoot 'scripts\Install-Common.ps1')

Set-InstallerDryRun -Enabled:$script:DryRunRequested
if ($script:DryRunRequested) {
    Write-Host ''
    Write-Host '=========================================================================' -ForegroundColor DarkGray
    Write-Host '  DRY RUN: nothing will be installed, written, or changed.' -ForegroundColor Cyan
    Write-Host '  Every read (payload hashes, installed state, config comparison) runs' -ForegroundColor DarkGray
    Write-Host '  for real, so what you see is this machine''s true state.' -ForegroundColor DarkGray
    Write-Host '=========================================================================' -ForegroundColor DarkGray
    Write-Host ''
}

Write-InstallerHeader

# ---------------------------------------------------------------------------
# Preconditions: architecture and elevation.
# ---------------------------------------------------------------------------
# Elevation is MANDATORY (the MSIs write into C:\Program Files). Instead of
# refusing a non-elevated run — which read as "nothing happened" because the
# launcher window closed immediately afterwards — the installer now asks for
# elevation itself, exactly like the EXE wrapper does. On success it relaunches
# this same script elevated and forwards the outcome; the exit code of the
# elevated run is this run's exit code. -SkipElevationCheck bypasses the whole
# mechanism (used by the wrapper, which has already elevated, and by the
# Sandbox suite, which runs pre-elevated).

Assert-ArchitectureSupported

if ($DryRun) {
    # Nothing is written in a dry run, so elevation is unnecessary - and asking
    # for it would defeat the purpose of a zero-impact verification.
    Write-Host '  Dry run: skipping the elevation gate (no writes happen).' -ForegroundColor DarkGray
} elseif (-not $SkipElevationCheck) {
    $forwarded = @()
    foreach ($key in $PSBoundParameters.Keys) {
        if ($key -ne 'SkipElevationCheck') { $forwarded += "-$key" }
    }
    Invoke-InstallerElevation -Arguments $forwarded
}

# ---------------------------------------------------------------------------
# Load the payload manifest and verify every binary before touching the system.
# ---------------------------------------------------------------------------
# The manifest covers every redistributed binary, including the pre-patched
# komorebi.exe deployed by the Komorebi patch step below.

$payloads = Get-PayloadManifest -Path (Join-Path $RepoRoot 'binaries\payloads.sha256.json')

Test-PayloadIntegrity -Payloads $payloads -RepoRoot $RepoRoot

# ---------------------------------------------------------------------------
# Install steps. Each one is state-detected and idempotent.
# ---------------------------------------------------------------------------
# The components are split into two priority classes:
#
#   PRIMARY (Komorebi, the Komorebi patch, WHKD) — the window manager, its
#     required access-denied patch, and the hotkey layer. If one of these
#     fails, the product cannot function at all, so the run aborts immediately
#     with the failure and its fix shown to the user.
#
#   SECONDARY (YASB, AutoHotkey v1/v2) — the status bar and the user scripts.
#     These are conveniences on top of the WM; a machine without them is still
#     usable, so a failure here is reported to the user with its fix and the
#     run CONTINUES to the remaining steps. The user fixes it and re-runs the
#     installer: everything that already succeeded is detected as installed and
#     skipped, so only the failed components are reinstalled.
#
# Both classes print the same failure report (step, cause, remedy) through
# Report-InstallerFailure; only the stopping behaviour differs.

$primarySteps = @(
    @{ Name = 'Komorebi';    Action = { Install-Komorebi    -Payload $payloads['komorebi-0.1.41-x86_64.msi'] } }
    @{ Name = 'Komorebi patch'; Action = { Install-KomorebiPatch -RepoRoot $RepoRoot -PatchedSha256 $payloads['komorebi.exe'].sha256 } }
    @{ Name = 'WHKD';        Action = { Install-Whkd        -Payload $payloads['whkd-0.2.10-x86_64.msi'] } }
)

$secondarySteps = @(
    @{ Name = 'YASB';         Action = { Install-Yasb         -Payload $payloads['yasb-2.0.7-x64.msi'] } }
    @{ Name = 'AutoHotkey v1'; Action = { Install-AutoHotkeyV1 -Payload $payloads['AutoHotkey.1.1.30.00_setup.exe'] } }
    @{ Name = 'AutoHotkey v2'; Action = { Install-AutoHotkeyV2 -Payload $payloads['AutoHotkey_2.0.12_setup.exe'] } }
)

foreach ($step in $primarySteps) {
    try {
        & $step.Action
    } catch {
        Report-InstallerFailure -Step "Install $($step.Name)" -ErrorRecord $_
        Write-InstallerFailureFooter -Reason 'A core window-manager component failed. Komorebi cannot run without it, so the install stopped here.'
        exit 1
    }
}

$secondaryFailures = @()
foreach ($step in $secondarySteps) {
    try {
        & $step.Action
    } catch {
        Report-InstallerFailure -Step "Install $($step.Name)" -ErrorRecord $_
        $secondaryFailures += $step.Name
    }
}

# ---------------------------------------------------------------------------
# Configuration generation.
# ---------------------------------------------------------------------------
# Writes the Komorebi/WHKD/YASB configuration for THIS machine from the portable
# templates: the monitor layout and display preferences are generated from the
# live hardware, everything else is copied byte-for-byte, the generated
# app_specific_configuration_path is validated against the deployed
# applications.json, and komorebic check validates the result before success
# is declared.

$configurationFailed = $false
try {
    Install-Configuration -RepoRoot $RepoRoot
} catch {
    Report-InstallerFailure -Step 'Generate configuration' -ErrorRecord $_
    $configurationFailed = $true
}
if ($configurationFailed) { exit 2 }

# ---------------------------------------------------------------------------
# Startup machinery.
# ---------------------------------------------------------------------------
# Registers the Komorebi logon task and the watchdog (both at RunLevel Highest
# so elevated windows stay manageable), enables YASB autostart, and makes sure
# komorebic.exe is on PATH before anything launches.

$startupFailed = $false
try {
    Install-StartupTasks -RepoRoot $RepoRoot
} catch {
    Report-InstallerFailure -Step 'Set up startup tasks' -ErrorRecord $_
    $startupFailed = $true
}
if ($startupFailed) { exit 3 }

# ---------------------------------------------------------------------------
# AutoHotkey startup launcher (ticket 05).
# ---------------------------------------------------------------------------
# Generates AppRunner.vbs in the Startup folder from the three .ahk scripts
# shipped under autohotkey\. The VBS is regenerated, never copied, so every
# path in it points at this machine's interpreters and this repository.

$ahkFailed = $false
try {
    Install-AutoHotkeyStartup -RepoRoot $RepoRoot
} catch {
    Report-InstallerFailure -Step 'Set up the AutoHotkey startup launcher' -ErrorRecord $_
    $ahkFailed = $true
}
if ($ahkFailed) { exit 4 }

# ---------------------------------------------------------------------------
# Done.
# ---------------------------------------------------------------------------

# A secondary component can have failed without aborting the run. Tell the
# user what is missing and how to get it, and use a dedicated exit code so an
# unattended run (the EXE wrapper) can tell "everything" from "usable but
# incomplete". Re-running this installer reinstalls only those components,
# because every other step is state-detected and skips itself.
if ($secondaryFailures.Count) {
    $list = ($secondaryFailures | Select-Object -Unique) -join ', '
    Write-Host ''
    Write-Host '  One or more optional components did not install:' -ForegroundColor Yellow
    Write-Host "    $list" -ForegroundColor Yellow
    Write-Host '  The window manager and its hotkeys are installed and working.' -ForegroundColor Green
    Write-Host '  Fix the reported cause, then run this installer again: every' -ForegroundColor DarkGray
    Write-Host '  component that succeeded is detected and skipped, so only the' -ForegroundColor DarkGray
    Write-Host '  failed ones are reinstalled.' -ForegroundColor DarkGray
    Write-InstallerFooter
    exit 10
}

Write-InstallerFooter
