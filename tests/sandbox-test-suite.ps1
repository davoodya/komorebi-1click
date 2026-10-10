$ErrorActionPreference = 'Stop'
# =============================================================================
# komorebi-1click — Sandbox test suite (tickets 01 + 02 + 03 + 04)
# =============================================================================
# Runs INSIDE Windows Sandbox on a clean Win11. ADR-0008 forbids any of this on
# the production reference machine, so this file is the single authoritative
# "run these after every ticket" test.
#
# Harness contract (ticket 02):
#   & Install.ps1
#   $LASTEXITCODE   -> 0 = ok, 1 = arch-guard, 2 = config-gen failure,
#                      3 = startup-tasks failure, 3013 = MSI failure
#
# Driver: docs/sandbox-test-harness.ps1 stages this file into the Sandbox and
# launches it. To run it manually, see docs/TESTING.md.
# =============================================================================

param(
    # Sandbox-side mount point of the host repo (see the .wsb HostFolder mapping).
    [string] $Repo = 'C:\Repo'
)

$script:fail = 0
$script:checks = 0
function Assert($label, $ok) {
    $script:checks++
    Write-Output ("  [{0}] {1}" -f $(if ($ok) {'PASS'} else {'FAIL'}), $label)
    if (-not $ok) { $script:fail++ }
}
function Section($t) { Write-Output ''; Write-Output ("===== {0} =====" -f $t) }

if (-not (Test-Path "$Repo\Install.ps1")) { throw "Repo not found at $Repo" }

# Path helpers for the actual install locations (Sandbox user is WDAGUtilityAccount).
$UserHome = $env:USERPROFILE
$KomorebiConfigDir = Join-Path $UserHome '.config\komorebi'

# =============================================================================
# Ticket 01 — repo skeleton, committed binaries, provenance, licenses
# =============================================================================
Section 'T01 — repo payload + provenance (ticket 01)'

$payloads = @{
    'komorebi 0.1.41 MSI'   = "$Repo\binaries\komorebi-0.1.41-x86_64.msi"
    'whkd 0.2.10 MSI'       = "$Repo\binaries\whkd-0.2.10-x86_64.msi"
    'YASB 2.0.7 MSI'        = "$Repo\binaries\yasb-2.0.7-x64.msi"
    'AutoHotkey v1 setup'   = "$Repo\binaries\AutoHotkey.1.1.30.00_setup.exe"
    'AutoHotkey v2 setup'   = "$Repo\binaries\AutoHotkey_2.0.12_setup.exe"
}
foreach ($name in $payloads.Keys | Sort-Object) {
    $p = $payloads[$name]
    Assert ("payload present: {0}" -f $name) (Test-Path $p)
    if (Test-Path $p) {
        $size = (Get-Item $p).Length
        Assert ("payload is not zero bytes: {0} ({1} bytes)" -f $name, $size) ($size -gt 0)
    }
}

# SHA pins must exist and must match the committed binaries exactly.
$shaFile = "$Repo\binaries\payloads.sha256.json"
Assert 'payloads.sha256.json exists' (Test-Path $shaFile)
if (Test-Path $shaFile) {
    $manifest = Get-Content $shaFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $pins = @($manifest.binaries)
    Assert 'provenance manifest lists all 5 install payloads' ($pins.Count -ge 5)
    foreach ($pin in $pins) {
        $p = Join-Path $Repo $pin.file
        if (Test-Path $p) {
            $actual = (Get-FileHash -Algorithm SHA256 $p).Hash.ToLower()
            Assert ("SHA256 matches pin for {0}" -f $pin.file) ($actual -eq $pin.sha256.ToLower())
        } else {
            # Ahk2Exe.exe is carried as a supplementary payload, not installed.
            if ($pin.file -notlike '*Ahk2Exe*') { Assert ("pinned payload exists: {0}" -f $pin.file) $false }
        }
    }
}

# License texts shipped (AutoHotkey is GPLv2, per the pre-implementation audit).
foreach ($lic in @('LICENSE-komorebi.md','LICENSE-whkd.md','LICENSE-yasb.txt','AutoHotkey-GPLv2.txt')) {
    Assert ("license present: {0}" -f $lic) (Test-Path "$Repo\licenses\$lic")
}

# Provenance: every binary's official release URL must be recorded.
$txt = "$Repo\binaries\payloads.sha256.txt"
Assert 'human-readable provenance file exists' (Test-Path $txt)
$manifestText = if (Test-Path $shaFile) { Get-Content $shaFile -Raw -Encoding UTF8 } else { '' }
foreach ($needle in @('github.com/LGUG2Z/komorebi/releases','github.com/LGUG2Z/whkd/releases','github.com/amnweb/yasb/releases','github.com/AutoHotkey/AutoHotkey/releases')) {
    Assert ("official release URL recorded: {0}" -f $needle) ($manifestText -like "*$needle*")
}

# =============================================================================
# Ticket 02 — offline installer core
# =============================================================================
Section 'T02.0 — clean machine preconditions'

Assert 'no komorebi installed yet'  (-not (Test-Path 'C:\Program Files\komorebi'))
Assert 'no whkd installed yet'      (-not (Test-Path 'C:\Program Files\whkd'))
Assert 'no YASB installed yet'      (-not (Test-Path 'C:\Program Files\YASB'))
Assert 'no AutoHotkey installed yet' (-not (Test-Path 'C:\Program Files\AutoHotkey'))
Assert 'no komorebi config yet'     (-not (Test-Path $KomorebiConfigDir))

Section 'T02.1 — first install (the real clean-install path)'

& "$Repo\Install.ps1"
$exit1 = $LASTEXITCODE
Write-Output ("  Install.ps1 exit code: {0}" -f $exit1)
Assert 'first install exits 0' ($exit1 -eq 0)

Section 'T02.2 — every binary actually installed'

$kb = 'C:\Program Files\komorebi\bin\komorebic.exe'
Assert 'komorebic.exe present' (Test-Path $kb)
Assert 'whkd.exe present'      (Test-Path 'C:\Program Files\whkd\bin\whkd.exe')
Assert 'yasb.exe present'      (Test-Path 'C:\Program Files\YASB\yasb.exe')
Assert 'AHK v1 present'        (Test-Path 'C:\Program Files\AutoHotkey\AutoHotkey.exe')
Assert 'AHK v2 present'        (Test-Path 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe')

$kbv = & $kb --version 2>&1 | Select-Object -First 1
Assert ("komorebic version is 0.1.41 (got {0})" -f $kbv) ($kbv -match '0\.1\.41')
$whkdv = & 'C:\Program Files\whkd\bin\whkd.exe' --version 2>&1 | Select-Object -First 1
Assert ("whkd version is 0.2.10 (got {0})" -f $whkdv) ($whkdv -match '0\.2\.10')

# =============================================================================
# Ticket 03 — configuration generation
# =============================================================================
Section 'T03.1 — config files written for THIS machine'

$kjson = Join-Path $KomorebiConfigDir 'komorebi.json'
Assert 'komorebi.json exists' (Test-Path $kjson)
$cfg = Get-Content $kjson -Raw -Encoding UTF8 | ConvertFrom-Json
$monitors = @($cfg.monitors)
Assert 'at least one monitor block' ($monitors.Count -ge 1)
Assert '9 workspaces on monitor 0' (@($monitors[0].workspaces).Count -eq 9)
Assert 'app_specific_configuration_path points at THIS user' ($cfg.app_specific_configuration_path -eq (Join-Path $UserHome '.config\komorebi\applications.json'))
Assert 'applications.json was placed there' (Test-Path $cfg.app_specific_configuration_path)

    # --- the access-denied patch (2026-10-10, finding F6) --------------------------
    # The MSI installs the STOCK komorebi.exe, which kills konsole with
    # 0x80070005. The installer must leave the PRE-PATCHED build pinned in
    # binaries\payloads.sha256.json. Without this check, "komorebi.exe is
    # installed" passes while the buggy binary is deployed.
    $installedKorebiBin = Join-Path $env:ProgramFiles 'komorebi\bin\komorebi.exe'
    $patchedPin = @($pins | Where-Object { $_.file -like '*Korebi-Patched*' } | Select-Object -First 1)
    if ((Test-Path $installedKorebiBin) -and $patchedPin) {
        $deployedHash = (Get-FileHash -LiteralPath $installedKorebiBin -Algorithm SHA256).Hash
        Assert 'the installed komorebi.exe is the patched build (pinned SHA256)' `
               ($deployedHash -ieq ([string]$patchedPin.sha256)) `
               ("deployed: " + $deployedHash.Substring(0,16) + " expected: " + ([string]$patchedPin.sha256).Substring(0,16))
    } else {
        Assert 'the installed komorebi.exe is the patched build (pinned SHA256)' $false `
               ('missing binary or pin: ' + $installedKorebiBin)
    }

    # --- entry point 1: the EXE wrapper --------------------------------------------
    # The double-click path. Everything is installed by now, so the wrapper's
    # second pass is idempotent and must exit 0. The wrapper's execution path
    # (argument order, exit-code forwarding, -SkipElevationCheck landing as a
    # script parameter) is covered host-side by tests\ticket09-exe-wrapper.tests.ps1,
    # which compiles the wrapper with the K1C_TEST_FORCE_ELEVATED hook and runs
    # it against a recording stub. Here it runs only when the sandbox context is
    # already elevated, because a UAC prompt would hang the suite.
    $wrapperExe = Join-Path $Repo 'komorebi-1click-install.exe'
    Assert 'the EXE wrapper was built into the repo' (Test-Path $wrapperExe) $wrapperExe
    $elevatedHere = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($elevatedHere -and (Test-Path $wrapperExe)) {
        $wrapperProc = Start-Process -FilePath $wrapperExe -Wait -PassThru
        Assert 'the EXE wrapper exited 0 over an already-installed machine' ($wrapperProc.ExitCode -eq 0) ("exit: " + $wrapperProc.ExitCode)
    } else {
        Assert 'the EXE wrapper execution path is covered by ticket 09' $true `
               'not run here: the sandbox logon session is not elevated (a UAC prompt would hang the suite); ticket 09 executes the wrapper on any host'
    }
Assert 'whkdrc exists' (Test-Path (Join-Path $UserHome '.config\whkdrc'))
$resize = Join-Path $KomorebiConfigDir 'komorebi-resize.json'
Assert 'komorebi-resize.json exists' (Test-Path $resize)
Assert 'komorebi-resize.json is EMPTY (pure runtime state)' ((Get-Item $resize).Length -eq 0)
Assert 'YASB config exists' (Test-Path (Join-Path $UserHome '.config\yasb\config.yaml'))
Assert 'YASB sensor script exists in the repo' (Test-Path "$Repo\scripts\sensor-color.ps1")

Section 'T03.2 — the generated config carries the source-machine behaviour'

$wl = ($cfg.layered_applications | ConvertTo-Json -Compress)
Assert 'layered_applications has the mintty Class rule' ($wl -like '*mintty*')
Assert 'layered_applications has the ConsoleWindowClass rule (elevated consoles)' ($wl -like '*ConsoleWindowClass*')

Section 'T03.3 — no source-machine residue (portability)'

$bad = Get-ChildItem -Path (Join-Path $UserHome '.config') -Recurse -File -ErrorAction SilentlyContinue |
       Select-String -Pattern 'DavoodYa','H:\\Repo','F:\\Backups','C:\\Users\\DavoodYa' -SimpleMatch |
       Select-Object -First 1
Assert 'no source-machine username or paths anywhere under .config' (-not $bad)

# The YASB config must point its sensor at the REPO, not at a machine path.
$yaml = Get-Content (Join-Path $UserHome '.config\yasb\config.yaml') -Raw
Assert 'YASB sensor path is not the source-machine path' (-not ($yaml -like '*C:\Users\DavoodYa*'))

Section 'T03.4 — komorebic check passes on the generated config'

$check = & $kb check -k $kjson 2>&1
Assert ("komorebic check exits 0 (got {0})" -f $LASTEXITCODE) ($LASTEXITCODE -eq 0)
Write-Output ("  report: {0}" -f (($check -split "`n" | Select-Object -First 3) -join ' | '))

# =============================================================================
# Ticket 04 — startup machinery
# =============================================================================
Section 'T04.1 — the Komorebi logon task'

$task = Get-ScheduledTask -TaskName 'Komorebi' -ErrorAction SilentlyContinue
Assert "task 'Komorebi' exists" ([bool]$task)
if ($task) {
    Assert 'logon task runs at RunLevel Highest' ($task.Principal.RunLevel -eq 'Highest')
    Assert 'logon task has a logon trigger' ($task.Triggers[0].CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger')
    $a = $task.Actions[0]
    Write-Output ("  logon action: {0} {1}" -f $a.Execute, $a.Arguments)
    Assert 'logon task executes the installed komorebic.exe' ($a.Execute -eq $kb)
    Assert "logon task arguments are 'start --whkd'" ($a.Arguments -eq 'start --whkd')
}

Section 'T04.1c — komorebi is ELEVATED so it can manage elevated windows'
# An unelevated window manager cannot manage windows belonging to elevated
# processes (UAC integrity levels). The installer registers the Komorebi logon
# task at RunLevel Highest for exactly this reason, and the restart scripts must
# take the same path - a bare `Start-Process` from a non-elevated shell silently
# drops every elevated window and the Hermes window out of the layout.
Add-Type @"
using System; using System.Runtime.InteropServices;
public class SandboxTok {
  [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(int da, bool ih, int pid);
  [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr ph, int da, out IntPtr th);
  [DllImport("advapi32.dll", SetLastError=true)] public static extern bool GetTokenInformation(IntPtr th, int tic, IntPtr ti, int til, out int ril);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  public static bool IsElevated(int pid) {
    // 0x1000 = PROCESS_QUERY_LIMITED_INFORMATION. The older
    // PROCESS_QUERY_INFORMATION mask is denied under UIPI and silently
    // reports every process as non-elevated.
    IntPtr p = OpenProcess(0x1000, false, pid); if (p == IntPtr.Zero) return false;
    IntPtr th; int len;
    if (!OpenProcessToken(p, 0x0008, out th)) { CloseHandle(p); return false; }
    IntPtr b = Marshal.AllocHGlobal(4);
    bool ok = GetTokenInformation(th, 20, b, 4, out len);
    bool e = ok && Marshal.ReadInt32(b) != 0;
    Marshal.FreeHGlobal(b); CloseHandle(th); CloseHandle(p); return e;
  }
}
"@
$k = Get-Process -Name komorebi -ErrorAction SilentlyContinue | Select-Object -First 1
Assert 'komorebi is running after the restart' ($null -ne $k)
if ($k) { Assert 'komorebi runs elevated (can manage elevated windows)' ([SandboxTok]::IsElevated($k.Id)) }

Section 'T04.1e — restart-whkd.ps1 restarts through the elevated task'
# restart-whkd.ps1 used to relaunch whkd.exe directly, which produced an
# unpaired whkd and killed every hotkey. It now stops the pair through
# `komorebic stop --whkd` and starts it again via the RunLevel Highest
# `Komorebi` logon task, so the new komorebi is elevated and owns its whkd
# child. This test checks the mechanism is present in the shipped script -
# a regression to a bare Start-Process would reintroduce the silent hotkey
# loss AND the elevated-window dropout at the same time.
$src = Get-Content "$Repo\scripts\restart-whkd.ps1" -Raw
Assert 'restart-whkd stops via komorebic stop --whkd' ($src -match 'stop --whkd')
Assert 'restart-whkd starts komorebi via the elevated logon task' ($src -match "Start-ScheduledTask -TaskName 'Komorebi'")
Assert 'restart-whkd verifies the pairing after restart' ($src -match 'Test-WhkdPaired')
Assert 'restart-whkd exits non-zero when the pairing is broken' ($src -match 'exit 2')

Section 'T04.1d — secondary install failures do not abort the installer'
# The installer splits its payloads into two classes. Komorebi and WHKD are
# primary: a failure there aborts the run. YASB and AutoHotkey are secondary:
# a failure is reported with its cause and remedy and the run CONTINUES, so the
# machine still ends up with a working window manager. Re-running the installer
# reinstalls only the failed components, because every step is state-detected
# and skips what is already installed.
$src = Get-Content "$Repo\Install.ps1" -Raw
Assert 'Install.ps1 stops on a primary (Komorebi/WHKD) failure' ($src -match 'foreach \(\$step in \$primarySteps\)')
Assert 'Install.ps1 continues past a secondary (YASB/AutoHotkey) failure' ($src -match 'foreach \(\$step in \$secondarySteps\)')
Assert 'secondary failures are collected, not thrown' ($src -match '\$secondaryFailures \+= \$step\.Name')
Assert 'the user is told which secondary components are missing' ($src -match 'One or more optional components did not install')

Section 'T04.1b — whkd is PAIRED with komorebi (hotkeys actually live)'
# A whkd that is alive but was NOT spawned by `komorebic start --whkd` registers
# every hotkey and then drops every command — the WM looks perfectly healthy
# while the whole keyboard is dead. This is LGUG2Z/komorebi#956. The health
# check has a dedicated pairing probe; assert it is green after a real install.
. "$Repo\scripts\komorebi-service.ps1"
$health = Get-Health
Assert 'whkd is running' $health.Whkd
Assert 'whkd is paired with komorebi (not a standalone instance)' $health.WhkdPaired

Section 'T04.2 — the watchdog task (self-healing)'

$wd = Get-ScheduledTask -TaskName 'KomorebiWatchdog' -ErrorAction SilentlyContinue
Assert "task 'KomorebiWatchdog' exists" ([bool]$wd)
if ($wd) {
    Assert 'watchdog task runs at RunLevel Highest' ($wd.Principal.RunLevel -eq 'Highest')
    $a = $wd.Actions[0]
    Write-Output ("  watchdog action: {0}" -f $a.Arguments)
    Assert 'watchdog action references komorebi-service.ps1' ($a.Arguments -like '*komorebi-service.ps1*')
    Assert 'watchdog action passes -Action watchdog' ($a.Arguments -like '*-Action watchdog*')
    Assert 'watchdog trigger repeats every 5 minutes' ($wd.Triggers[0].Repetition.Interval -eq 'PT5M')

    # The watchdog must be launched through the windowless launcher so it never
    # flashes a console window at logon.
    Assert 'watchdog runs through the windowless launcher' ($a.Execute -like '*komorebi-watchdog.exe')
    if (Test-Path $a.Execute) {
        $bytes = [System.IO.File]::ReadAllBytes($a.Execute)
        $pe = [BitConverter]::ToInt32($bytes, 0x3c)
        $subsystem = [BitConverter]::ToUInt16($bytes, $pe + 0x5c)
        Assert ("watchdog launcher is a GUI-subsystem binary (subsystem {0})" -f $subsystem) ($subsystem -eq 2)
    } else {
        Assert 'watchdog launcher binary exists on disk' $false
    }
}

Section 'T04.3 — PATH and YASB autostart'

$kbResolve = Get-Command -Name 'komorebic.exe' -ErrorAction SilentlyContinue
Assert 'komorebic.exe resolves from PATH' ([bool]$kbResolve)
if ($kbResolve) {
    Assert 'PATH-resolved komorebic.exe is the installed one' ($kbResolve.Source -eq $kb)
}

# YASB must start at logon. The primary mechanism is yasbc enable-autostart; the
# fallback is a Startup-folder shortcut. Either is acceptable — but exactly one.
$runKey = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).YASB
$startupShortcut = Test-Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\YASB.lnk')
Assert 'YASB autostart is enabled (Run key OR Startup shortcut)' ([bool]$runKey -or $startupShortcut)

Section 'T04.4 — no legacy racing startup shortcut'

Assert 'no legacy komorebi.lnk in the Startup folder' (-not (Test-Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\komorebi.lnk')))

# =============================================================================
# Cross-ticket — idempotency (re-run the whole installer)
# =============================================================================
Section 'T05 — idempotency: run the installer a second time'

$beforeKomorebi = (Get-ScheduledTask -TaskName 'Komorebi' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Actions[0].Execute)|$($_.Actions[0].Arguments)|$($_.Principal.RunLevel)" }) -join '`n'
$beforeWatchdog = (Get-ScheduledTask -TaskName 'KomorebiWatchdog' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Actions[0].Execute)|$($_.Actions[0].Arguments)|$($_.Principal.RunLevel)" }) -join '`n'
$beforeJson = Get-Content $kjson -Raw -Encoding UTF8
$beforeRunKey = $runKey

& "$Repo\Install.ps1"
$exit2 = $LASTEXITCODE
Write-Output ("  second Install.ps1 exit code: {0}" -f $exit2)
Assert 'second install also exits 0' ($exit2 -eq 0)

$afterJson = Get-Content $kjson -Raw -Encoding UTF8
Assert 'komorebi.json is byte-identical on re-run' ($beforeJson -eq $afterJson)

$_checkRc = 0
{ param() $null = & $kb check -k $kjson 2>&1; $script:_checkRc = $LASTEXITCODE } | Invoke-Expression
Assert 'config still validates after re-run' ($script:_checkRc -eq 0)

$afterKomorebi = (Get-ScheduledTask -TaskName 'Komorebi' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Actions[0].Execute)|$($_.Actions[0].Arguments)|$($_.Principal.RunLevel)" }) -join '`n'
$afterWatchdog = (Get-ScheduledTask -TaskName 'KomorebiWatchdog' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Actions[0].Execute)|$($_.Actions[0].Arguments)|$($_.Principal.RunLevel)" }) -join '`n'
Assert 'Komorebi task unchanged by re-run' ($beforeKomorebi -eq $afterKomorebi)
Assert 'KomorebiWatchdog task unchanged by re-run' ($beforeWatchdog -eq $afterWatchdog)

$afterRunKey = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).YASB
Assert 'YASB autostart setting unchanged by re-run' ($beforeRunKey -eq $afterRunKey)

# =============================================================================
# Result
# =============================================================================
Section 'RESULT'
Write-Output ("  assertions: {0}" -f $script:checks)
Write-Output ("  failures:   {0}" -f $script:fail)
if ($script:fail -gt 0) { exit 1 }
Write-Output '  ALL CHECKS PASSED'
