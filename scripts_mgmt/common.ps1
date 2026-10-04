# =====================================================================
# Komorebi & WHkd Management Scripts — shared helpers
#   komorebi.exe / komorebic.exe : C:\Program Files\komorebi\bin\
#   whkd.exe                     : C:\Program Files\whkd\bin\
# Run any script:  powershell -ExecutionPolicy Bypass -File <script>.ps1
# =====================================================================

$ErrorActionPreference = "Stop"
# If launched from a WSL/UNC working directory, move to a real Windows drive
# so that "C:\..." style paths resolve correctly.
if ((Get-Location).Path -like "\\\\*") { Push-Location "C:\" }

# --- resolve exe paths -------------------------------------------------
function Resolve-KomorebiExe {
    $cands = @(
        "$env:ProgramFiles\komorebi\bin\komorebi.exe",
        "$env:LOCALAPPDATA\Programs\komorebi\bin\komorebi.exe"
    ) | Where-Object { Test-Path $_ }
    if (-not $cands) { throw "komorebi.exe not found" }
    return @($cands)[0]
}

function Resolve-KomorebicExe {
    $cands = @(
        "$env:ProgramFiles\komorebi\bin\komorebic.exe",
        "$env:LOCALAPPDATA\Programs\komorebi\bin\komorebic.exe"
    ) | Where-Object { Test-Path $_ }
    if (-not $cands) { throw "komorebic.exe not found" }
    return @($cands)[0]
}

function Resolve-WhkdExe {
    $cands = @(
        "$env:ProgramFiles\whkd\bin\whkd.exe",
        "$env:LOCALAPPDATA\Programs\whkd\bin\whkd.exe"
    ) | Where-Object { Test-Path $_ }
    if (-not $cands) { throw "whkd.exe not found" }
    return @($cands)[0]
}

function Resolve-YasbExe {
    # YASB installs at C:\Program Files\YASB\yasb.exe. Returns $null (not an
    # error) when it is absent, so callers can treat a missing bar as a skip.
    $cands = @(
        "$env:ProgramFiles\YASB\yasb.exe",
        "$env:ProgramFiles\yasb\yasb.exe",
        "$env:LOCALAPPDATA\Programs\YASB\yasb.exe"
    ) | Where-Object { Test-Path $_ }
    if (-not $cands) { return $null }
    return @($cands)[0]
}

function Resolve-AutoHotkeyExe {
    # v1 interpreter at the vendor-default path. Returns $null when absent.
    $exe = "$env:ProgramFiles\AutoHotkey\AutoHotkey.exe"
    if (Test-Path $exe) { return $exe }
    return $null
}

function Resolve-AutoHotkeyV2Exe {
    # v2 interpreter, installed into the v1 tree by the v2 setup.
    $exe = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
    if (Test-Path $exe) { return $exe }
    return $null
}

# --- process helpers ---------------------------------------------------
function Test-Process([string]$Name) {
    return [bool](Get-Process -Name $Name -ErrorAction SilentlyContinue)
}

function Stop-ProcessTree([string]$Name) {
    Get-Process -Name $Name -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.Kill(); $_.WaitForExit(3000) } catch { }
    }
    Start-Sleep -Milliseconds 400
    Write-Host "  stopped $Name" -ForegroundColor DarkGray
}
