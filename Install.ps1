#Requires -Version 5.1
<#
.SYNOPSIS
    Komorebi-1click installer.
.DESCRIPTION
    Installs Komorebi, WHKD, YASB and AutoHotkey (v1 + v2) completely offline
    from the binaries committed to this repository.

    Every payload's SHA256 is verified before anything is installed. Each step
    detects the current state first and skips itself when the target is already
    present, so re-running this script always reaches the same end state.

    Configuration generation, startup tasks and the AutoHotkey startup launcher
    are handled by later tickets (03, 04, 05); this script installs only the
    five binaries.
.NOTES
    All paths resolve from this script's own location, so the repository can be
    cloned anywhere. There are no machine-specific constants in this file.
#>

[CmdletBinding()]
param(
    # Skip the interactive elevation prompt. Intended for automation and for the
    # EXE wrapper, which elevates before it launches this script.
    [switch]$SkipElevationCheck
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Bootstrapping: resolve the repository root and load the installer library.
# ---------------------------------------------------------------------------

# RepoRoot is the directory that contains this script. Never use the current
# working directory: a user double-clicking the wrapper starts in System32.
$RepoRoot = $PSScriptRoot

. (Join-Path $RepoRoot 'scripts\Install-Common.ps1')

Write-InstallerHeader

# ---------------------------------------------------------------------------
# Preconditions: architecture and elevation.
# ---------------------------------------------------------------------------

Assert-ArchitectureSupported

if (-not $SkipElevationCheck) {
    Assert-RunningElevated
}

# ---------------------------------------------------------------------------
# Load the payload manifest and verify every binary before touching the system.
# ---------------------------------------------------------------------------

$payloads = Get-PayloadManifest -Path (Join-Path $RepoRoot 'binaries\payloads.sha256.json')

Test-PayloadIntegrity -Payloads $payloads -RepoRoot $RepoRoot

# ---------------------------------------------------------------------------
# Install steps. Each one is state-detected and idempotent.
# ---------------------------------------------------------------------------
# The components are split into two priority classes:
#
#   PRIMARY (Komorebi, WHKD) — the window manager and its hotkey layer. If one
#     of these fails, the product cannot function at all, so the run aborts
#     immediately with the failure and its fix shown to the user.
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
# live hardware, everything else is copied byte-for-byte, and komorebic check
# validates the result before success is declared.

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
