#Requires -Version 5.1
<#
    komorebi + whkd  -  service control for Windows 11

    Actions:
      status     health report (process, socket, monitors, layouts, hotkeys)
      start      clean start with --whkd  (whkd is REQUIRED for hotkeys)
      restart    same as start, but explicit
      retile     ask komorebi to re-tile the current workspace
      install    register a logon scheduled task + a watchdog task
      uninstall  remove both scheduled tasks
      watchdog   internal: only restarts when the WM is actually dead

    Run from Windows PowerShell. Use the .bat wrappers in this folder.
#>

[CmdletBinding()]
param(
    [ValidateSet('install', 'uninstall', 'start', 'stop', 'restart', 'status', 'retile', 'watchdog')]
    [string] $Action = 'status',

    [ValidateRange(1, 120)]
    [int] $WatchdogMinutes = 5
)

$ErrorActionPreference = 'Stop'

# Long paths are fine here (PowerShell quotes them). The 8.3 short form is
# only needed inside whkdrc, where the command gets wrapped in quotes again.
$KomorebiExe   = 'C:\Program Files\komorebi\bin\komorebic.exe'
$WhkdExe       = 'C:\Program Files\whkd\bin\whkd.exe'
$WhkdrcPath    = Join-Path $env:USERPROFILE '.config\whkdrc'

$TaskName      = 'Komorebi'
$WatchTaskName = 'KomorebiWatchdog'

$StateDir      = Join-Path $env:LOCALAPPDATA 'komorebi'
$SockFile      = Join-Path $StateDir 'komorebi.sock'
$HwndFile      = Join-Path $StateDir 'komorebi.hwnd.json'
$LogFile       = Join-Path $StateDir 'service.log'

# ── helpers ──────────────────────────────────────────────────────────────

function Write-Log {
    param([string] $Message, [string] $Level = 'INFO')
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Get-Uptime {
    param($Proc)
    if (-not $Proc) { return 'n/a' }
    try   { return ('{0:n0}m' -f ((Get-Date) - $Proc.StartTime).TotalMinutes) }
    catch { return 'n/a' }
}

function Install-Runner {
    # WHY THIS EXISTS
    #   whkd runs `.shell <cmd>` per hotkey via CreateProcess WITHOUT
    #   CREATE_NO_WINDOW. The default shell, `powershell`, is a console-subsystem
    #   program, so a visible console flashes on every keypress.
    #
    #   Shadowing powershell.exe does NOT fix it: `where powershell.exe` resolves
    #   System32 -> Machine PATH -> User PATH, so a shim in %USERPROFILE%\bin is
    #   always second and never wins. Beating System32 needs admin rights and
    #   would affect every program on the machine.
    #
    #   NOTE (whkd 0.2.10, verified against its source): the `.shell` line only
    #   accepts the bare names `cmd`, `powershell` or `pwsh` — anything else
    #   makes whkd PANIC with "could not load whkdrc" and every hotkey dies.
    #   So this runner is NOT used as the `.shell`; it is only kept as a
    #   dependency-free helper for other scripts. Do not point whkdrc at it.
    #   invocations (111 of 112 are `C:\Progra~1\...\komorebic.exe <args>`), so
    #   the runner launches the target DIRECTLY - no shell is spawned, so there
    #   is nothing that could allocate a console. Being a GUI-subsystem binary
    #   it gets no console of its own either.
    #
    #   NOTE: whkd's `.shell` parser is strict. If it rejects the runner name we
    #   keep `.shell powershell` and the flicker may occasionally return; that is
    #   why 8-TEST-SHELL-FORM.bat exists.
    $binDir  = Join-Path $env:USERPROFILE 'bin'
    $csSrc   = Join-Path $env:USERPROFILE '.config\komorebi-runner.cs'
    $target  = Join-Path $binDir 'komorebi-runner.exe'
    $cscExe  = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'

    if (-not (Test-Path $csSrc)) {
        Write-Log 'komorebi-runner.cs is missing; keeping the plain powershell shell' -Level 'WARN'
        return $false
    }
    if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }

    if (-not (Test-Path $target) -or (Get-Item $target).LastWriteTime -lt (Get-Item $csSrc).LastWriteTime) {
        if (-not (Test-Path $cscExe)) {
            Write-Log 'no C# compiler found; cannot build the runner' -Level 'WARN'
            return $false
        }
        Write-Host '  building the windowless komorebi runner...' -ForegroundColor DarkGray
        $out = & $cscExe /nologo /target:winexe /optimize+ /out:$target $csSrc 2>&1
        if (-not (Test-Path $target)) {
            Write-Log "runner build failed: $out" -Level 'ERROR'
            return $false
        }
    }

    # The runner is referenced by BARE NAME, so its folder must be on PATH.
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $userPath) { $userPath = '' }
    if ($userPath -notlike "*$binDir*") {
        $parts = @($userPath -split ';' | Where-Object { $_.Trim() })
        [Environment]::SetEnvironmentVariable('Path', (@($binDir) + $parts) -join ';', 'User')
        Write-Host "  added $binDir to the user PATH" -ForegroundColor DarkGray
    }
    $env:Path = $env:Path + ';' + $binDir

    # Verify the compiled binary really is GUI subsystem. A console build would
    # bring the flicker straight back, so check rather than assume.
    try {
        $b = [System.IO.File]::ReadAllBytes($target)
        $pe = [BitConverter]::ToInt32($b, 0x3c)
        $sub = [BitConverter]::ToUInt16($b, $pe + 0x5c)
        if ($sub -ne 2) {
            Write-Log "runner is not a GUI binary (subsystem $sub); ignoring it" -Level 'ERROR'
            return $false
        }
    } catch {
        Write-Log "could not verify the runner subsystem: $_" -Level 'WARN'
        return $false
    }

    Write-Log "windowless komorebi runner ready at $target (GUI subsystem)"
    return $true
}

function Remove-Runner {
    $target = Join-Path $env:USERPROFILE 'bin\komorebi-runner.exe'
    if (Test-Path $target) {
        Remove-Item $target -Force
        Write-Host "  removed $target" -ForegroundColor Yellow
    }
}

function Wait-ForProcess {
    param([string] $Name, [int] $Seconds = 20)
    for ($i = 0; $i -lt ($Seconds * 2); $i++) {
        Start-Sleep -Milliseconds 500
        if (@(Get-Process -Name $Name -ErrorAction SilentlyContinue).Count -gt 0) { return $true }
    }
    return $false
}

function Get-WindowsMonitor {
    # Windows' own rect for a monitor, in the SAME physical-pixel coordinate
    # space komorebi reports. System.Windows.Forms.Screen.Bounds are LOGICAL
    # (DPI-scaled) values: a monitor at 125% reports 864x1536 logical where
    # komorebi reports the physical 1080x1920. Converting per-monitor keeps the
    # comparison apples-to-apples, otherwise Get-Health raises a phoney
    # "komorebi disagrees with Windows" mismatch on every scaled display.
    param([string] $Name)
    if ($null -eq $script:MonCache) {
        $script:MonCache = @{}
        try {
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class KomorebiDpi {
    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO { public uint cbSize; public int left, top, right, bottom; }
    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromRect(ref RECT lprc, uint dwFlags);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")]
    public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);
    [DllImport("user32.dll")]
    public static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("gdi32.dll")]
    public static extern int GetDeviceCaps(IntPtr hdc, int nIndex);
    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    public static double ScaleOf(int logicalX, int logicalY, int logicalW, int logicalH) {
        RECT r; r.Left = logicalX; r.Top = logicalY; r.Right = logicalX + logicalW; r.Bottom = logicalY + logicalH;
        IntPtr hm = MonitorFromRect(ref r, 2);
        if (hm == IntPtr.Zero) { return 1.0; }
        MONITORINFO mi; mi = new MONITORINFO(); mi.cbSize = (uint)Marshal.SizeOf(mi);
        if (!GetMonitorInfo(hm, ref mi)) { return 1.0; }
        IntPtr dc = GetDC(hm);
        if (dc == IntPtr.Zero) { return 1.0; }
        try {
            int logPixelsX = GetDeviceCaps(dc, 88);   // LOGPIXELSX
            return (logPixelsX <= 0) ? 1.0 : (logPixelsX / 96.0);
        } finally { ReleaseDC(hm, dc); }
    }
}
"@
            foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
                $key = $s.DeviceName -replace '^\\\\\\.\\\\', ''
                $b = $s.Bounds
                $scale = [KomorebiDpi]::ScaleOf($b.X, $b.Y, $b.Width, $b.Height)
                $script:MonCache[$key] = [pscustomobject]@{
                    Right  = [int][Math]::Round($b.X + $b.Width * $scale)
                    Bottom = [int][Math]::Round($b.Y + $b.Height * $scale)
                }
            }
        } catch { return $null }
    }
    if ($script:MonCache.ContainsKey($Name)) { return $script:MonCache[$Name] }
    return $null
}


function Get-Health {
    $h = [ordered]@{
        Process        = $false
        ProcessUptime  = 'n/a'
        Socket         = $false
        Whkd           = $false
        WhkdUptime     = 'n/a'
        WhkdPaired     = $false
        Monitors       = 0
        TiledWindows   = 0
        HotkeyBindings = 0
        BadMonitors    = @()
        MonitorMismatch = @()
        Nameless       = @()
        ZeroContainers = @()
        GhostMaximized = @()
    }
    # BUG FIX: the early-return used to run BEFORE $h.Process was ever set,
    # so it always returned the empty snapshot and always said BROKEN even
    # when komorebi and whkd were running fine.
    $proc = Get-Process -Name komorebi -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) { $h.Process = $true; $h.ProcessUptime = Get-Uptime $proc }
    $w = Get-Process -Name whkd -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($w) { $h.Whkd = $true; $h.WhkdUptime = Get-Uptime $w }

    # PAIRING CHECK (the bug that silently kills every hotkey):
    # whkd can be alive, parsing whkdrc perfectly, and STILL be useless —
    # when it was not spawned by `komorebic start --whkd` it registers the
    # hotkeys but its komorebic calls do not reach this komorebi instance.
    #
    # The signal: `--whkd` launches whkd through a transient helper that exits
    # immediately, so whkd's parent PID points at a GONE process. A standalone
    # whkd instead has a LIVE shell (pwsh/powershell/cmd) as its parent. Walk
    # the chain: reaching a gone parent means the official launcher ran it;
    # reaching a live shell means something else did.
    if ($h.Whkd -and $h.Process) {
        $cur = Get-CimInstance Win32_Process -Filter "Name = 'whkd.exe'" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        $seen = @{}
        $paired = $false
        for ($i = 0; $cur -and $i -lt 12 -and -not $seen.ContainsKey($cur.ProcessId); $i++) {
            if ($cur.Name -ieq 'komorebi.exe') { $paired = $true; break }
            $seen[$cur.ProcessId] = $true
            $next = Get-CimInstance Win32_Process -Filter "ProcessId = $($cur.ParentProcessId)" -ErrorAction SilentlyContinue
            if ($null -eq $next) {
                # The parent is gone. komorebi's own --whkd launcher is a
                # short-lived helper that exits right after spawning whkd, so a
                # dead parent here is the signature of the OFFICIAL start path.
                $paired = $true
                break
            }
            # A live shell as whkd's ancestor is the standalone (broken) case.
            if ($next.Name -imatch 'pwsh\.exe|powershell\.exe|cmd\.exe|wt\.exe|conhost\.exe') { break }
            $cur = $next
        }
        $h.WhkdPaired = $paired
    }

    if (Test-Path $WhkdrcPath) {
        $h.HotkeyBindings = @(Get-Content $WhkdrcPath -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '^\s*\S.*:' -and $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' }).Count
    }

    if (-not $h.Process) { return [pscustomobject]$h }

    $raw = & $KomorebiExe state 2>$null | Out-String
    if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]$h }
    try { $s = $raw | ConvertFrom-Json }
    catch { return [pscustomobject]$h }
    $h.Socket = $true

    $mon = @($s.monitors.elements)
    $h.Monitors = $mon.Count
    foreach ($m in $mon) {
        $sz = $m.size
        # `komorebic state` serialises a monitor as { left, top, right, bottom }
        # where `right`/`bottom` are the WIDTH/HEIGHT, not the far edge. On the
        # primary (left=0, top=0) `right - left` happens to agree; on every
        # offset monitor it does not (e.g. left=1920 right=1080 => -840). Read
        # the fields as what they actually are.
        $wd = [int]$sz.right
        $ht = [int]$sz.bottom
        if ($wd -le 0 -or $ht -le 0) {
            $h.BadMonitors += ('{0}: {1}x{2} (left={3} top={4})' -f `
                $m.name, $wd, $ht, $sz.left, $sz.top)
        }
        # Catch the subtler case too: a rect that looks plausible but still
        # disagrees with Windows. The real fault is that komorebi puts the raw
        # pixel WIDTH into the `right` field for every non-primary monitor, so
        # the damage shows up as absurd container sizes long before the monitor
        # itself looks wrong. Compare against Windows directly.
        $win = Get-WindowsMonitor -Name $m.name
        if ($win) {
            $dw = [int]$win.Right
            $dh = [int]$win.Bottom
            if ($dw -ne $wd -or $dh -ne $ht) {
                $h.MonitorMismatch += ('{0}: komorebi says {1}x{2}, Windows says {3}x{4}' -f `
                    $m.name, $wd, $ht, $dw, $dh)
            }
        }
        $wsi = 0
        foreach ($ws in @($m.workspaces.elements)) {
            if ([string]::IsNullOrEmpty($ws.name)) { $h.Nameless += ('{0} ws#{1}' -f $m.name, $wsi) }
            $conts = @($ws.containers.elements)
            $float = @($ws.floating_windows.elements)
            if ($ws.maximized_window -and $conts.Count -eq 0 -and $float.Count -eq 0) {
                $h.GhostMaximized += ('{0}/{1}: {2}' -f $m.name, $ws.name, $ws.maximized_window.exe)
            }
            foreach ($c in $conts) {
                foreach ($x in @($c.windows.elements)) {
                    $h.TiledWindows++
                    $r = $x.rect
                    if (([int]$r.right - [int]$r.left) -le 0 -or ([int]$r.bottom - [int]$r.top) -le 0) {
                        $h.ZeroContainers += ('{0} [{1}]' -f $x.title, $x.exe)
                    }
                }
            }
            $wsi++
        }
    }
    return [pscustomobject]$h
}

function Show-Status {
    $h = Get-Health
    Write-Host ''
    Write-Host '================ komorebi health ================' -ForegroundColor Cyan
    Write-Host ('  komorebi process : {0}  (up {1})' -f $h.Process, $h.ProcessUptime) -ForegroundColor $(if ($h.Process) { 'Green' } else { 'Red' })
    Write-Host ('  socket alive     : {0}' -f $h.Socket) -ForegroundColor $(if ($h.Socket) { 'Green' } else { 'Red' })
    Write-Host ('  whkd (hotkeys)   : {0}  (up {1})' -f $h.Whkd, $h.WhkdUptime) -ForegroundColor $(if ($h.Whkd) { 'Green' } else { 'Red' })
    # Report the pairing separately from the process: a whkd that is alive but
    # NOT paired registers every hotkey and then drops every command, which is
    # exactly the silent failure mode this check exists to surface.
    if ($h.Whkd -and -not $h.WhkdPaired) {
        Write-Host ('  whkd PAIRING     : BROKEN - whkd is alive but NOT spawned by komorebi') -ForegroundColor Red
        Write-Host '                     fix: komorebic stop --whkd; komorebic start --whkd' -ForegroundColor Red
    } elseif ($h.Whkd -and $h.WhkdPaired) {
        Write-Host '  whkd PAIRING     : OK (spawned by komorebi --whkd)' -ForegroundColor Green
    }
    Write-Host ('  hotkey bindings  : {0}' -f $h.HotkeyBindings)
    Write-Host ('  monitors         : {0}' -f $h.Monitors)
    Write-Host ('  tiled windows    : {0}' -f $h.TiledWindows)

    $problems = 0
    if ($h.BadMonitors) {
        $problems++
        Write-Host ''
        Write-Host '  [PROBLEM] monitor geometry is invalid:' -ForegroundColor Red
        $h.BadMonitors | ForEach-Object { Write-Host "     $_" -ForegroundColor Red }
    }
    if ($h.MonitorMismatch) {
        $problems++
        Write-Host '  [PROBLEM] komorebi disagrees with Windows about monitor size:' -ForegroundColor Red
        $h.MonitorMismatch | ForEach-Object { Write-Host "     $_" -ForegroundColor Red }
        Write-Host '     If this appears on a scaled monitor, check that Windows is not' -ForegroundColor Yellow
        Write-Host '     reporting logical (DPI-scaled) sizes. Run 6-DISPLAY-DIAG.bat to' -ForegroundColor Yellow
        Write-Host '     compare native pixels against komorebi, then 0-SAFE-RESTART.bat.' -ForegroundColor Yellow
    }
    if ($h.Nameless) {
        Write-Host ''
        Write-Host '  [INFO] workspaces have no names (index-driven layout):' -ForegroundColor DarkGray
        $h.Nameless | Select-Object -First 5 | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
        Write-Host '     this is fine when whkdrc addresses workspaces by index' -ForegroundColor DarkGray
    }
    if ($h.ZeroContainers) {
        Write-Host ''
        Write-Host '  [WARN] zero-size containers (hidden/minimised windows):' -ForegroundColor Yellow
        $h.ZeroContainers | Select-Object -First 8 | ForEach-Object { Write-Host "     $_" -ForegroundColor Yellow }
    }
    if ($h.GhostMaximized) {
        $problems++
        Write-Host ''
        Write-Host '  [WARN] maximized window with no containers (ghost layout):' -ForegroundColor Yellow
        $h.GhostMaximized | ForEach-Object { Write-Host "     $_" -ForegroundColor Yellow }
        Write-Host '     fix: run  0-SAFE-RESTART.bat' -ForegroundColor Yellow
    }
    if (-not $h.Whkd -and $h.Process) {
        $problems++
        Write-Host ''
        Write-Host '  [PROBLEM] komorebi runs but whkd does not -> NO hotkeys will work' -ForegroundColor Red
        Write-Host '     fix: run  0-SAFE-RESTART.bat  (it starts with --whkd)' -ForegroundColor Yellow
    }

    Write-Host ''
    if (-not $h.Process)      { Write-Host '  VERDICT: BROKEN  (komorebi not running)' -ForegroundColor Red }
    elseif ($problems -gt 0)  { Write-Host ('  VERDICT: DEGRADED  ({0} problem(s))' -f $problems) -ForegroundColor Yellow }
    else                      { Write-Host '  VERDICT: HEALTHY' -ForegroundColor Green }
    Write-Host '===============================================' -ForegroundColor Cyan
    Write-Host ''
    return $h
}

function Test-StaleHwnd {
    # A crashed komorebi leaves a truncated/invalid komorebi.hwnd.json behind.
    # On the next logon that makes the WM exit immediately, so hotkeys never
    # come up. Healthy format is a JSON array holding one non-zero hwnd.
    if (-not (Test-Path $HwndFile)) { return $false }
    try {
        $raw = (Get-Content $HwndFile -Raw).Trim()
        if ($raw.Length -lt 3) { return $true }           # truncated to nothing
        $o = $raw | ConvertFrom-Json
        if ($null -eq $o) { return $true }
        $arr = @($o)
        if ($arr.Count -ne 1) { return $true }            # expected exactly one
        if ([int64]$arr[0] -eq 0) { return $true }        # null window handle
        return $false
    } catch { return $true }                             # unparseable = stale
}

function Start-Komorebi {
    if (-not (Test-Path $KomorebiExe)) { throw "komorebi not found at $KomorebiExe" }
    # Make hotkeys windowless: install the runner, then point whkdrc at it if
    # this whkd build accepts the name. Fall back to the plain shell otherwise.
    $shellName = 'powershell'
    try {
        if (Install-Runner) { $shellName = 'komorebi-runner' }
    } catch { Write-Log "runner install skipped: $_" -Level 'WARN' }

    # A whkdrc that whkd cannot parse makes every hotkey dead while komorebi
    # itself looks perfectly healthy, so validate the file before starting.
    if (Test-Path $WhkdrcPath) {
        # Resolve the repair script relative to THIS file, so it keeps working
        # no matter which folder the management scripts live in.
        $repair = Join-Path $PSScriptRoot 'repair-whkdrc.ps1'
        if (Test-Path $repair) {
            $raw = Get-Content $WhkdrcPath -Raw -ErrorAction SilentlyContinue
            $needs = $false
            if ($null -ne $raw) {
                # Accept either the bare shell or the windowless shim. The shim
                # is preferred: it is a GUI-subsystem binary, so no console can
                # flash on every hotkey.
                $head = (Get-Content $WhkdrcPath -TotalCount 1 -ErrorAction SilentlyContinue)
                $wantShell = ".shell $shellName"
                if ($head -and $head -ne $wantShell -and
                    $head -ne '.shell powershell' -and
                    $head -ne '.shell komorebi-runner') { $needs = $true }
                if ($raw -match "`"") { $needs = $true }
                if (($raw.ToCharArray() | Where-Object { [int]$_ -gt 126 }).Count -gt 0) { $needs = $true }
            } else { $needs = $true }
            if ($needs) {
                Write-Host '  whkdrc looks malformed - repairing it first' -ForegroundColor Yellow
                try { & $repair -Path $WhkdrcPath -Shell $shellName | Out-Null
                      Write-Log 'whkdrc repaired' } catch { Write-Log "repair failed: $_" -Level 'ERROR' }
            }
        }
    }

    if (Test-StaleHwnd) {
        Write-Host '  found a stale hwnd file from a previous crash, removing it' -ForegroundColor Yellow
        Write-Log 'stale komorebi.hwnd.json removed'
    }
    Write-Host '  stopping any running instance...' -ForegroundColor DarkGray
    Write-Log 'stop requested'
    try { & $KomorebiExe stop --whkd 2>$null | Out-Null } catch { }
    Get-Process -Name komorebi, whkd -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Remove-Item $SockFile -Force -ErrorAction SilentlyContinue
    Remove-Item $HwndFile -Force -ErrorAction SilentlyContinue

    Write-Host '  starting komorebi WITH --whkd (whkd is what makes hotkeys work)...' -ForegroundColor DarkGray
    Write-Log 'starting komorebi --whkd'
    # Refresh PATH from the registry. The machine PATH is correctly
    # bracketed ('C:\Program Files\whkd\bin\'), so `--whkd` is the right
    # way to start; but a stale inherited PATH makes komorebi report
    # "could not find whkd" and refuse to start at all.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($machine) { $env:Path = $machine + ';' + $user }

    # Redirect the children so they do NOT inherit this script's stdout/stderr
    # handles. When they inherit them (the default), PowerShell cannot exit until
    # the long-lived komorebi/whkd children close their copy of the pipe, so the
    # script appears to hang forever even though everything actually started.
    $outFile = Join-Path $StateDir 'komorebi.out.log'
    Start-Process -FilePath $KomorebiExe -ArgumentList 'start', '--whkd' `
                  -WorkingDirectory (Split-Path $KomorebiExe) `
                  -RedirectStandardOutput $outFile `
                  -RedirectStandardError (Join-Path $StateDir 'komorebi.err.log') | Out-Null

    if (-not (Wait-ForProcess -Name 'komorebi' -Seconds 20)) {
        Write-Log 'komorebi did not start' -Level 'ERROR'
        return $false
    }

    # whkd is spawned by --whkd, but it panics with "could not load whkdrc" when
    # the config is malformed. Capture its own stderr so the real reason is
    # printed instead of leaving a silently dead hotkey layer.
    Start-Sleep -Seconds 2
    if (@(Get-Process -Name whkd -ErrorAction SilentlyContinue).Count -eq 0) {
        Write-Host '  whkd did not come up - starting it directly and capturing its error' -ForegroundColor Yellow
        if (-not (Test-Path $WhkdExe)) {
            Write-Log "whkd missing at $WhkdExe" -Level 'ERROR'
            return $false
        }
        $errFile = Join-Path $StateDir 'whkd-start.err'
        try {
            # Redirect BOTH streams. If only stderr is redirected, whkd inherits
            # this script's stdout pipe and PowerShell can never exit, because
            # the long-lived whkd keeps that handle open.
            Start-Process -FilePath $WhkdExe -WorkingDirectory (Split-Path $WhkdExe) `
                          -RedirectStandardError $errFile `
                          -RedirectStandardOutput (Join-Path $StateDir 'whkd-start.out') `
                          -WindowStyle Hidden | Out-Null
        } catch {
            Write-Log "whkd launch failed: $_" -Level 'ERROR'
        }
        if (-not (Wait-ForProcess -Name 'whkd' -Seconds 8)) {
            if (Test-Path $errFile) {
                $msg = (Get-Content $errFile -Raw -ErrorAction SilentlyContinue)
                $msg = (($msg -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 3) -join '  |  '
                if ($msg) {
                    Write-Host '  whkd refused to start. Its own error:' -ForegroundColor Red
                    Write-Host "    $msg" -ForegroundColor Red
                }
            }
            Write-Log 'whkd did not start - hotkeys will NOT work' -Level 'ERROR'
            return $false
        }
        # CRITICAL: a whkd started this way is NOT paired with komorebi. It
        # registers every hotkey and then drops every command, so the WM looks
        # healthy while nothing responds to the keyboard. Do not report success.
        Write-Log 'whkd started standalone (NOT paired with komorebi) - hotkeys will be dead' -Level 'ERROR'
        Write-Host '  whkd is running but is NOT paired with komorebi.' -ForegroundColor Red
        Write-Host '  Hotkeys will be dead. Re-run with `komorebic stop --whkd` then' -ForegroundColor Red
        Write-Host '  `komorebic start --whkd` so komorebi owns the whkd child.' -ForegroundColor Red
        return $false
    }

    Write-Log 'komorebi + whkd are up'
    return $true
}

# ── actions ──────────────────────────────────────────────────────────────

switch ($Action) {

    'status' {
        Show-Status | Out-Null
    }

    # Stop-only, no restart. Used by safe-restart.ps1 when this shell is NOT
    # elevated: it stops the pair here and then triggers the RunLevel Highest
    # `Komorebi` logon task to bring it back elevated. Starting komorebi from
    # this branch on a non-admin account would relaunch it unelevated, and an
    # unelevated window manager cannot manage elevated windows.
    'stop' {
        try { & $KomorebiExe stop --whkd 2>$null | Out-Null } catch { }
        Get-Process -Name komorebi, whkd -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Remove-Item $SockFile -Force -ErrorAction SilentlyContinue
        Remove-Item $HwndFile -Force -ErrorAction SilentlyContinue
        Write-Host '  komorebi + whkd stopped. Start them again with the Komorebi' -ForegroundColor DarkGray
        Write-Host '  logon task (elevated) or `komorebic start --whkd`.' -ForegroundColor DarkGray
    }

    'start'   { if (Start-Komorebi) { Show-Status | Out-Null } else { Write-Host '  FAILED to start' -ForegroundColor Red } }
    'restart' {
        # Same mutex as the watchdog so a restart can never race the watchdog.
        $mut = New-Object System.Threading.Mutex($false, 'Global\komorebi-service-start')
        try {
            if (-not $mut.WaitOne(10000)) {
                Write-Host '  another start/restart is already running; waiting for it' -ForegroundColor Yellow
                if (-not $mut.WaitOne(60000)) { Write-Host '  timed out waiting; proceeding anyway' -ForegroundColor Red }
            }
            if (Start-Komorebi) { Show-Status | Out-Null } else { Write-Host '  FAILED to start' -ForegroundColor Red }
        }
        finally { $mut.ReleaseMutex() }
    }

    'retile' {
        & $KomorebiExe retile | Out-Null
        Start-Sleep -Milliseconds 800
        Show-Status | Out-Null
    }

    'watchdog' {
        # Only ever restarts when the WM is genuinely gone. Never touches a
        # running-but-degraded WM, so it can never destroy your layout.
        # Must require BOTH. An earlier version only checked the socket, so a
        # WM with a live socket but a dead whkd was left alone and every
        # hotkey stayed broken.
        $h = Get-Health
        if ($h.Process -and $h.Whkd) { exit 0 }

        # RACE FIX: `restart` stops komorebi+whkd and waits ~2s before
        # re-launching. The watchdog runs every 5 minutes, so it can land in
        # exactly that gap, see "both down", and start a SECOND instance
        # against the same socket. The loser gets killed, and the winner ends
        # up with a half-initialised state in which workspaces stop responding.
        # Wait up to 90s for the restart in flight to finish before deciding.
        $deadline = (Get-Date).AddSeconds(90)
        while ((Get-Date) -lt $deadline) {
            $h = Get-Health
            if ($h.Process -and $h.Whkd) { exit 0 }
            $stillDying = @(Get-Process -Name komorebi, whkd -ErrorAction SilentlyContinue).Count
            if ($stillDying -eq 0) { break }   # nothing left; the start phase is next
            Start-Sleep -Seconds 3
        }

        # Acquire a mutex so two watchdogs (or a watchdog + manual restart)
        # can never start komorebi at the same time.
        $mut = New-Object System.Threading.Mutex($false, 'Global\komorebi-service-start')
        try {
            if (-not $mut.WaitOne(10000)) {
                Write-Log 'watchdog: another start is in progress; backing off' -Level 'WARN'
                exit 0
            }
            Write-Log 'watchdog: komorebi or whkd is down, restarting' -Level 'WARN'
            Start-Komorebi | Out-Null
        }
        finally { $mut.ReleaseMutex() }
    }

    'install' {
        $id = "$env:USERDOMAIN\$env:USERNAME"

        # Build the windowless watchdog launcher. Without it the scheduled
        # task flashes a console every interval.
        try {
            $wcs  = Join-Path $env:USERPROFILE '.config\komorebi-watchdog.cs'
            $wexe = Join-Path $env:USERPROFILE 'bin\komorebi-watchdog.exe'
            $wcsc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
            if ((Test-Path $wcs) -and (Test-Path $wcsc)) {
                if (-not (Test-Path (Split-Path $wexe)))
                    { New-Item -ItemType Directory -Path (Split-Path $wexe) -Force | Out-Null }
                & $wcsc /nologo /target:winexe /optimize+ /out:$wexe $wcs 2>&1 | Out-Null
                if (Test-Path $wexe) {
                    $b  = [System.IO.File]::ReadAllBytes($wexe)
                    $pe = [BitConverter]::ToInt32($b, 0x3c)
                    if ([BitConverter]::ToUInt16($b, $pe + 0x5c) -eq 2) {
                        Write-Host '  [OK] windowless watchdog launcher built (GUI, never flashes)' -ForegroundColor Green
                    } else {
                        Write-Host '  [warn] launcher is not a GUI binary; watchdog may flash' -ForegroundColor Yellow
                        Remove-Item $wexe -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        } catch { Write-Log "watchdog launcher build failed: $_" -Level 'WARN' }

        # The old Startup-folder shortcut would race the scheduled task and
        # can start a second komorebi against the same socket. Remove it.
        $oldLnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\komorebi.lnk'
        if (Test-Path $oldLnk) {
            Remove-Item $oldLnk -Force
            Write-Host "  removed the old Startup shortcut (it would race this task)" -ForegroundColor Yellow
        }

        # NOTE: these MUST NOT be named $action / $trigger / $settings.
        # PowerShell variable names are case-insensitive, so $action would
        # overwrite the $Action parameter and the [switch] block would then
        # try to validate a task-action object as a string.
        $taskAction = New-ScheduledTaskAction -Execute $KomorebiExe -Argument 'start --whkd'
        $taskTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $taskTrigger.Delay = 'PT25S'   # let Windows settle and the taskbar/YASB appear
        # Only request elevation when we actually have it. Asking for
        # RunLevel Highest from a non-elevated shell makes Register-ScheduledTask
        # fail, which would leave komorebi with no autostart at all.
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($isAdmin) {
            $principal = New-ScheduledTaskPrincipal -UserId $id -LogonType Interactive -RunLevel Highest
        } else {
            Write-Host '  (running unelevated: registering with the current user token)' -ForegroundColor DarkGray
            $principal = New-ScheduledTaskPrincipal -UserId $id -LogonType Interactive
        }
        $taskSettings = New-ScheduledTaskSettingsSet `
                        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                        -MultipleInstances IgnoreNew `
                        -ExecutionTimeLimit ([TimeSpan]::Zero) `
                        -StartWhenAvailable

        Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger $taskTrigger `
            -Principal $principal -Settings $taskSettings `
            -Description 'komorebi window manager with whkd hotkeys' -Force | Out-Null
        Write-Host "  [OK] registered scheduled task '$TaskName' (runs at logon +25s, elevated)" -ForegroundColor Green

        # Run the watchdog through a GUI-subsystem launcher. Task Scheduler
        # creates a console for powershell.exe and only hides it afterwards, so
        # -WindowStyle Hidden still flashes a window roughly every interval.
        # A GUI app is never given a console at all, which is what stops the
        # periodic CMD/PowerShell blink.
        $watchLauncher = Join-Path $env:USERPROFILE 'bin\komorebi-watchdog.exe'
        $wExe = 'powershell.exe'
        $wArgs = ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Action watchdog -WatchdogMinutes {1}' -f $PSCommandPath, $WatchdogMinutes)
        if (Test-Path $watchLauncher) {
            $wExe = $watchLauncher
        } else {
            Write-Host '  [warn] windowless watchdog launcher missing; falling back to powershell' -ForegroundColor Yellow
            $wArgs = '-NoProfile -WindowStyle Hidden ' + $wArgs
        }
        $watchAction = New-ScheduledTaskAction -Execute $wExe -Argument $wArgs
        $watchTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) `
            -RepetitionInterval (New-TimeSpan -Minutes $WatchdogMinutes) `
            -RepetitionDuration (New-TimeSpan -Days 3650)
        Register-ScheduledTask -TaskName $WatchTaskName -Action $watchAction -Trigger $watchTrigger `
            -Principal $principal -Settings $taskSettings `
            -Description 'restarts komorebi only if the WM has died' -Force | Out-Null
        Write-Host ("  [OK] registered watchdog '{0}' (every {1} min, only acts if WM is dead)" -f $WatchTaskName, $WatchdogMinutes) -ForegroundColor Green

        Write-Host ''
        Write-Host '  Starting komorebi now...' -ForegroundColor Cyan
        if (Start-Komorebi) { Show-Status | Out-Null } else { Write-Host '  FAILED to start' -ForegroundColor Red }
    }

    'uninstall' {
        foreach ($t in @($TaskName, $WatchTaskName)) {
            if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
                Unregister-ScheduledTask -TaskName $t -Confirm:$false
                Write-Host "  removed '$t'" -ForegroundColor Yellow
            }
        }
        Write-Host '  komorebi and whkd were left running' -ForegroundColor DarkGray
    }
}
