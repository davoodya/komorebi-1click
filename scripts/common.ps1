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

# --- read-only diagnosis ------------------------------------------------
function Show-KomorebiDiagnosis {
<#
    .SYNOPSIS
        Print the current state of the komorebi stack WITHOUT changing it.
    .DESCRIPTION
        Exposed as `-DiagnoseOnly` on the restart scripts. It exists because
        every real fault in this stack has looked like "a hotkey does nothing",
        and the three candidate causes are indistinguishable from the outside:

          * komorebi or whkd is not running,
          * they are running but UNPAIRED (komorebi without the whkd it owns),
          * whkd is up but hotkeys never loaded, so the binds are dead.

        `restart-whkd.ps1` once started whkd.exe directly, which produced
        exactly the second state: an orphaned whkd that a later `komorebic
        start --whkd` refuses to replace, so every hotkey stayed dead while
        both processes still appeared to be running.

        STRICTLY READ-ONLY. It starts nothing, stops nothing, writes no config
        and touches no scheduled task, so it is safe to run at any time.
#>
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host '=== komorebi stack diagnosis (read-only) ===' -ForegroundColor Cyan

    $rows = @()
    foreach ($n in @('komorebi', 'whkd', 'yasb', 'AutoHotkey')) {
        $procs = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
        $state = if ($procs.Count -eq 0) { 'not running' } else { "running (x$($procs.Count))" }
        $rows += [pscustomobject]@{ Component = $n; State = $state }
    }
    foreach ($r in $rows) {
        $colour = if ($r.State -eq 'not running') { 'Yellow' } else { 'Green' }
        Write-Host ('  {0,-12} {1}' -f $r.Component, $r.State) -ForegroundColor $colour
    }

    # komorebi and whkd are one unit: whkd is the child komorebi owns. Running
    # one without the other is the paired-but-broken state, so it is called out
    # explicitly instead of leaving the reader to subtract two rows themselves.
    $komorebiUp = Test-Process 'komorebi'
    $whkdUp     = Test-Process 'whkd'
    Write-Host ''
    if ($komorebiUp -and $whkdUp) {
        Write-Host '  pairing       OK - komorebi and whkd are both up' -ForegroundColor Green
    } elseif ($komorebiUp -and -not $whkdUp) {
        Write-Host '  pairing       BROKEN - komorebi is up but whkd is missing.' -ForegroundColor Red
        Write-Host '                Repair with: restart-whkd.ps1' -ForegroundColor Yellow
    } elseif (-not $komorebiUp -and $whkdUp) {
        Write-Host '  pairing       BROKEN - an ORPHANED whkd is running with no komorebi.' -ForegroundColor Red
        Write-Host '                Repair with: restart-all.ps1 (never start whkd.exe directly)' -ForegroundColor Yellow
    } else {
        Write-Host '  pairing       both down' -ForegroundColor Yellow
    }

    # The watchdog is the thing that silently stops supervising when a restart
    # run dies, so its Enabled flag matters as much as the process states.
    $watch = Get-ScheduledTask -TaskName 'KomorebiWatchdog' -ErrorAction SilentlyContinue
    if (-not $watch) {
        Write-Host '  watchdog      task not registered' -ForegroundColor Yellow
    } elseif ($watch.State -eq 'Disabled') {
        # A disabled task still reports LastTaskResult 0x0, so the result code
        # alone is misleading. Assert the state, never the result.
        Write-Host '  watchdog      DISABLED - komorebi/whkd are unsupervised' -ForegroundColor Red
        Write-Host '                Repair with: Enable-ScheduledTask -TaskName KomorebiWatchdog' -ForegroundColor Yellow
    } else {
        Write-Host ("  watchdog      {0} (supervised)" -f $watch.State) -ForegroundColor Green
    }

    # How many hotkeys whkd actually loaded. Zero with whkd "running" is the
    # signature of a bind file whkd rejected.
    try {
        $whkdProc = @(Get-Process -Name whkd -ErrorAction SilentlyContinue)
        if ($whkdProc.Count -gt 0) {
            $hotkeys = (Get-CimInstance Win32_Process -Filter "Name='whkd.exe'" |
                        Select-Object -ExpandProperty CommandLine) -join ' | '
            if ($hotkeys -match 'layer\s*\d+') {
                Write-Host '  whkd layer    loaded (a layer was passed on the command line)' -ForegroundColor Green
            } else {
                Write-Host '  whkd layer    unknown - could not read the layer from the command line' -ForegroundColor DarkGray
            }
        }
    } catch { }

    Write-Host ''
    Write-Host '  Nothing was changed by this report.' -ForegroundColor DarkGray
}
