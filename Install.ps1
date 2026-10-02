#Requires -Version 5.1
<#
.SYNOPSIS
    Komorebi-1click installer.
.DESCRIPTION
    Installs Komorebi, WHKD, YASB and AutoHotkey (v1 + v2) completely offline
    from the binaries committed to this repository, then generates the full
    configuration for the target machine.

    This is the placeholder shipped with ticket 01. The installer logic itself
    is ticket 02 (see .scratch/komorebi-1click-installer/issues/02-install-core.md).
.NOTES
    The installer resolves every path from its own location, so the repository
    can be cloned anywhere. Never hardcode a machine-specific path here.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Resolve the repository root from this script's own location, never from CWD.
$RepoRoot = $PSScriptRoot

Write-Host ''
Write-Host 'Komorebi-1click installer' -ForegroundColor Cyan
Write-Host 'Repository root:' $RepoRoot -ForegroundColor DarkGray
Write-Host ''

# The installer core is not implemented yet (ticket 02). Fail loudly rather than
# silently doing nothing, so `irm | iex` never reports a false success.
$Message = @'
The installer core is not implemented yet.

This repository currently ships only the payload and provenance foundation
(ticket 01). The offline installer itself is ticket 02.

You can already verify the committed payloads offline:

    Get-FileHash .\binaries\*.msi, .\binaries\*.exe -Algorithm SHA256
    # compare against binaries\payloads.sha256.txt

See the README for the full component and provenance list.
'@

Write-Host $Message -ForegroundColor Yellow
exit 1
