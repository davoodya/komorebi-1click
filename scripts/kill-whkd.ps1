#Requires -Version 5.1
<#
.SYNOPSIS
    Stop whkd only, leaving komorebi and yasb running.
.DESCRIPTION
    Backs the dashboard's `kill-whkd` verb (ADR-0013).

    WHY THIS IS SAFE WHILE START-WHKD IS NOT
      Stopping whkd on its own does not break the pairing: komorebic keeps
      running, its socket stays alive, and whkd can be brought back cleanly.
      The reverse is not true -- see start-whkd.ps1.

      Whkd is the child komorebi owns. Started any other way it registers every
      hotkey and then drops every command (LGUG2Z/komorebi#956). That is why
      there is a separate start-whkd.ps1 with an explicit guard rather than a
      copy of this file with the verbs swapped.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

Write-Host '[kill-whkd] stopping whkd ...' -ForegroundColor Cyan

if (-not (Test-Process 'whkd')) {
    Write-Host '[kill-whkd] whkd was not running. Nothing to do.' -ForegroundColor DarkGray
    exit 0
}

Stop-ProcessTree 'whkd'
Write-Host '[kill-whkd] DONE. komorebi and yasb untouched.' -ForegroundColor Green
Write-Host '[kill-whkd] To bring hotkeys back: start-whkd.ps1 (or restart-all.ps1)' -ForegroundColor DarkGray
exit 0