#Requires -Version 5.1
<#
.SYNOPSIS
    Bring hotkeys back after kill-whkd, WITHOUT breaking the komorebi pairing.
.DESCRIPTION
    Backs the dashboard's `start-whkd` verb (ADR-0013: "whkd only").

    WHY THIS DOES NOT RUN whkd.exe DIRECTLY
      This is the single most important thing in this file. Running whkd.exe by
      hand produces an ORPHANED whkd: komorebi does not own it, it registers
      every hotkey and then drops every command (LGUG2Z/komorebi#956), and a
      later `komorebic start --whkd` refuses to replace it. The symptom is that
      every hotkey stays dead while both processes still look healthy -- which is
      exactly the fault documented in
      docs/POSTMORTEM-20261004-whkd-pairing.md.

      So this script refuses the unsafe path by default. The only supported way
      to spawn whkd is `komorebic start --whkd`, which is what restart-whkd.ps1
      does (watchdog-safe, and elevation-aware).

      Use -Force to override when you have confirmed whkd is genuinely absent and
      no stale socket is holding the old instance.
.PARAMETER Force
    Delegate straight to restart-whkd.ps1 even when komorebi is not running.
#>
[CmdletBinding()]
param([switch] $Force)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$komorebiUp = Test-Process 'komorebi'

if (-not $komorebiUp -and -not $Force) {
    Write-Host '[start-whkd] komorebi is NOT running.' -ForegroundColor Red
    Write-Host '[start-whkd] whkd cannot be spawned on its own without breaking the' -ForegroundColor Red
    Write-Host '[start-whkd] pairing (it must be owned by komorebi). Start komorebi first:' -ForegroundColor Red
    Write-Host '[start-whkd]     start-all.ps1     (or restart-all.ps1)' -ForegroundColor Yellow
    Write-Host '[start-whkd] If you are certain no stale whkd holds the socket, use -Force.' -ForegroundColor DarkGray
    exit 1
}

if (Test-Process 'whkd') {
    Write-Host '[start-whkd] whkd is already running. Use restart-whkd.ps1 to reload its config.' -ForegroundColor DarkGray
    exit 0
}

Write-Host '[start-whkd] delegating to restart-whkd.ps1 (the only whkd-safe spawn path) ...' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'restart-whkd.ps1')
exit $LASTEXITCODE