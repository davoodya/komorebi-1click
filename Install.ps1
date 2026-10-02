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

$installSteps = @(
    { Install-Komorebi    -Payload $payloads['komorebi-0.1.41-x86_64.msi'] }
    { Install-Whkd        -Payload $payloads['whkd-0.2.10-x86_64.msi'] }
    { Install-Yasb        -Payload $payloads['yasb-2.0.7-x64.msi'] }
    { Install-AutoHotkeyV1 -Payload $payloads['AutoHotkey.1.1.30.00_setup.exe'] }
    { Install-AutoHotkeyV2 -Payload $payloads['AutoHotkey_2.0.12_setup.exe'] }
)

foreach ($step in $installSteps) {
    & $step
}

# ---------------------------------------------------------------------------
# Done.
# ---------------------------------------------------------------------------

Write-InstallerFooter
