#Requires -Version 5.1
<#
.SYNOPSIS
    Build the komorebi-1click installer EXE from its C# source.
.DESCRIPTION
    Dev-time build step (ADR-0004). It runs on the machine that has csc.exe --
    the in-box .NET Framework compiler -- and produces a single-file, GUI
    subsystem EXE with no target-machine dependency. The target machine only
    ever runs the finished binary.

    ps2exe and Inno Setup were both rejected by ADR-0004, so this script
    compiles hand-written C# and nothing else.

.PARAMETER OutputPath
    Where to write the EXE. Defaults to the repository root, so the EXE sits
    directly beside Install.ps1 as the wrapper requires.
.PARAMETER RepoRoot
    Repository root. Defaults to the parent of this script's folder.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build-exe.ps1
#>

[CmdletBinding()]
param(
    [string] $OutputPath,
    [string] $RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot)   { $RepoRoot = Split-Path $PSScriptRoot -Parent }
if (-not $OutputPath) {
    # The repository root, NOT an install\ subfolder: the wrapper locates
    # Install.ps1 next to itself, and Install.ps1 needs binaries\, config\ and
    # scripts\ anyway, so the whole repository is the shipped payload.
    $OutputPath = Join-Path $RepoRoot 'komorebi-1click-install.exe'
}

# The x64 .NET Framework 4 compiler ships with every supported Windows release,
# so no build-time dependency has to be installed anywhere.
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) {
    throw "csc.exe not found at $csc. This build step needs the in-box .NET Framework compiler."
}

$src = Join-Path $RepoRoot 'scripts\komorebi-install.cs'
if (-not (Test-Path -LiteralPath $src)) {
    throw "wrapper source not found at $src"
}

$outDir = Split-Path $OutputPath -Parent
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

Write-Host "[build-exe] compiling $src" -ForegroundColor Cyan
Write-Host "[build-exe] output   $OutputPath" -ForegroundColor DarkGray

# /target:winexe  -> GUI subsystem, so double-clicking never flashes a console.
# /reference:System.Windows.Forms.dll -> MessageBox, the only way a
#   console-less binary can show an error to a double-clicking user.
$args = @(
    '/nologo'
    '/target:winexe'
    '/optimize+'
    '/warnaserror-'
    '/reference:System.Windows.Forms.dll'
    "/out:$OutputPath"
    $src
)

$output = & $csc @args 2>&1
$exit = $LASTEXITCODE
if ($output) { $output | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray } }
if ($exit -ne 0 -or -not (Test-Path -LiteralPath $OutputPath)) {
    throw "compilation failed (csc exit $exit)"
}

# A console-subsystem build would flash a window on every double-click, so the
# PE header is checked rather than trusted: subsystem 2 == Windows GUI.
$bytes = [System.IO.File]::ReadAllBytes($OutputPath)
$peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
$subsystem = [BitConverter]::ToUInt16($bytes, $peOffset + 0x5c)
if ($subsystem -ne 2) {
    Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
    throw "the produced binary is console-subsystem ($subsystem), not GUI. Removed."
}

$kb = [math]::Round($bytes.Length / 1KB, 1)
Write-Host "[build-exe] OK - $OutputPath ($kb KB, GUI subsystem)" -ForegroundColor Green

# The EXE is useless without Install.ps1 beside it, so say so here rather than
# letting the user discover it on the target machine.
$installer = Join-Path (Split-Path $OutputPath -Parent) 'Install.ps1'
if (-not (Test-Path -LiteralPath $installer)) {
    Write-Host "[build-exe] WARNING: Install.ps1 is not next to the EXE." -ForegroundColor Yellow
    Write-Host "[build-exe]          The EXE needs it there at run time." -ForegroundColor Yellow
}
