<#
.SYNOPSIS
    Diagnoses and repairs the komorebi "Access is denied. (0x80070005)" startup
    failure on Windows 11 25H2/26H2.

.DESCRIPTION
    On Windows 11 26H2 (build 26300) komorebi v0.1.41 walks four Win32 gates in
    main(), and each one can kill it. This script checks all four and repairs the
    ones that are broken. It is idempotent: run it as often as you like.

        Gate 1  allow_set_foreground_window()      main.rs:203  -> binary patch
        Gate 2  set_process_dpi_awareness_context() main.rs:223 -> remove manifest
        Gate 3  foreground_lock_timeout()           main.rs:254  -> binary patch
        Gate 4  ApplicationSpecificConfiguration    asc.rs:40    -> restore file

    Gates 1 and 3 are patched by replacing a 6-byte `call [rip+rel32]` with
    `mov eax,1 ; nop`. The offsets are specific to komorebi v0.1.41, so the
    script REFUSES to patch unless the version and the anchor byte patterns both
    match exactly. Never patch a binary you have not verified.

    Gate 2 needs no binary change: an external komorebi.exe.manifest that
    upstream does not ship pre-sets DPI awareness, which makes komorebi's own
    runtime call fail. Renaming the manifest away is the whole fix.

.PARAMETER DryRun
    Report what would change without changing anything.

.PARAMETER NoElevate
    Do not auto-elevate. Use when you have already opened an elevated shell.

.EXAMPLE
    .\Access-Denied-0x80070005-fixing.ps1
    Diagnose and repair (auto-elevates if needed).

.EXAMPLE
    .\Access-Denied-0x80070005-fixing.ps1 -DryRun
    Show the diagnosis and what would be done, change nothing.

.NOTES
    Requires Windows PowerShell 5.1. Run from any shell; the script re-launches
    itself elevated when it needs to write to Program Files or register tasks.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------- auto-elevate -------
# Gates 1-3 need write access to Program Files and Task Scheduler, so re-launch
# ourselves elevated when we do not already have it. On this box
# ConsentPromptBehaviorAdmin=0, so this happens with no visible prompt; on a
# default machine the standard UAC consent dialog appears once.
if (-not $NoElevate -and -not $DryRun) {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Not elevated - re-launching as Administrator..." -ForegroundColor Yellow
        $self = $MyInvocation.MyCommand.Path
        if (-not $self) { $self = $PSCommandPath }
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$self`"", '-NoElevate')
        $p = Start-Process powershell.exe -ArgumentList $argList -Verb RunAs -Wait -PassThru
        exit $p.ExitCode
    }
}

# ---------------------------------------------------------------- constants --
$KomobiniBin   = 'C:\Program Files\komorebi\bin'
$KomorebiExe   = Join-Path $KomobiniBin 'komorebi.exe'
$Manifest      = Join-Path $KomobiniBin 'komorebi.exe.manifest'
$KomorebiJson  = Join-Path $env:USERPROFILE 'komorebi.json'
$AscPath       = Join-Path $env:USERPROFILE '.config\komorebi\applications.json'
$RepoConfig    = 'H:\Repo\komorebi-1click\config\applications.json'
$ServiceScript = 'H:\Repo\komorebi-1click\scripts\komorebi-service.ps1'
$BackupDir     = 'H:\Repo\komorebi-1click\backup\access-denied-fix'

# The version these offsets are known-good for. Anything else: refuse to patch.
$ExpectedVersion = '0.1.41'

# Patch site 1 (gate 3): the unique `mov ecx, 0x2001` sequence.
$SpiPattern  = [byte[]](0xB9,0x01,0x20,0x00,0x00, 0x31,0xD2, 0x45,0x31,0xC0,
                        0x41,0xB9,0x02,0x00,0x00,0x00, 0xFF,0x15)
$SpiOffset   = 0x2898E9
# Patch site 2 (gate 1): the single call to user32!AllowSetForegroundWindow.
$AsfwIatSlot = 0xA1AEA8
$AsfwOffset  = 0x28D7E4

$PatchBytes  = [byte[]](0xB8,0x01,0x00,0x00,0x00,0x90)   # mov eax,1 ; nop

$script:Problems = 0
$script:Fixed    = 0

function Say($m)  { Write-Host $m }
function Ok($m)   { Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Bad($m)  { Write-Host "  [FAIL] $m" -ForegroundColor Red;   $script:Problems++ }
function Fix($m)  { Write-Host "  [FIX ] $m" -ForegroundColor Cyan;  $script:Fixed++ }
function Info($m) { Write-Host "  [ -- ] $m" -ForegroundColor DarkGray }
function Head($m) { Write-Host ""; Write-Host "=== $m ===" -ForegroundColor Yellow }

# ------------------------------------------------------------------ helpers --
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Read-BytesAt($path, $offset, $count) {
    $fs = [System.IO.File]::OpenRead($path)
    try {
        $null = $fs.Seek($offset, 'Begin')
        $b = New-Object byte[] $count
        $null = $fs.Read($b, 0, $count)
        return $b
    } finally { $fs.Close() }
}

function Test-Same($a, $b) {
    if ($a.Length -ne $b.Length) { return $false }
    for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }
    return $true
}

function Format-Bytes($b) { ($b | ForEach-Object { $_.ToString('X2') }) -join ' ' }

# ------------------------------------------------------------------ banner --
Say ""
Say "=========================================================="
Say " komorebi  Access is denied (0x80070005)  -  diagnosis/repair"
Say " $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Say " elevated: $(Test-Admin)   DryRun: $DryRun"
Say "=========================================================="

if (-not (Test-Path $KomorebiExe)) {
    Bad "komorebi.exe not found at $KomorebiExe - is komorebi installed?"
    Say ""
    Say "Nothing to repair. Exiting."
    exit 1
}

# ------------------------------------------------------- gate 2: the manifest
Head "Gate 2  -  external komorebi.exe.manifest (DPI pre-set)"

if (Test-Path $Manifest) {
    Fix "an external manifest exists. Upstream v$ExpectedVersion does not ship one;"
    Say  "        it pre-sets DPI awareness so komorebi's own SetProcessDpiAwarenessContext"
    Say  "        call returns ERROR_ACCESS_DENIED (0x80070005)."
    if (-not $DryRun) {
        if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
        Copy-Item $Manifest (Join-Path $BackupDir 'komorebi.exe.manifest') -Force
        Rename-Item $Manifest 'komorebi.exe.manifest.bak' -Force
        Ok  "renamed to .bak (original preserved in $BackupDir)"
    } else { Info "would rename to .bak and back up the original" }
} else {
    Ok "no external manifest present"
}

# ------------------------------------------------- gate 1+3: the binary patch
Head "Gates 1 & 3  -  binary patch (AllowSetForegroundWindow + SPI_SETFOREGROUNDLOCKTIMEOUT)"

$ver = (& (Join-Path $KomobiniBin 'komorebic.exe') --version 2>&1 | Out-String)
if ($ver -notmatch [regex]::Escape($ExpectedVersion)) {
    Bad "komorebi version is not $ExpectedVersion."
    Say  "        The patch offsets below are only valid for $ExpectedVersion."
    $firstLine = ($ver -split "`n" | Select-Object -First 1)
    Say  "        Detected: $firstLine"
    Say  "        Refusing to patch an unverified binary. Fix gates 2 and 4 only."
} else {
    Info "version $ExpectedVersion confirmed"

    $bin = [System.IO.File]::ReadAllBytes($KomorebiExe)
    Info "binary size $($bin.Length) bytes"

    # --- check "already patched" FIRST: on a patched binary the gate-3 anchor
    #     no longer matches (its trailing FF 15 became B8 01 00 00 00 90), so
    #     searching for it first would report a false FAIL.
    $needSpi  = -not (Test-Same (Read-BytesAt $KomorebiExe $SpiOffset 6)  $PatchBytes)
    $needAsfw = -not (Test-Same (Read-BytesAt $KomorebiExe $AsfwOffset 6) $PatchBytes)

    if (-not $needSpi -and -not $needAsfw) {
        Ok "both call sites are ALREADY patched - nothing to do"
        Ok "  gate 3 @ 0x$($SpiOffset.ToString('X'))  = $(Format-Bytes $PatchBytes)"
        Ok "  gate 1 @ 0x$($AsfwOffset.ToString('X')) = $(Format-Bytes $PatchBytes)"
    } else {
        if ($needSpi)  { Info "gate 3 @ 0x$($SpiOffset.ToString('X')) needs patching" }
        if ($needAsfw) { Info "gate 1 @ 0x$($AsfwOffset.ToString('X')) needs patching" }

        # --- locate gate 3 by its unique anchor ---
        $spiHits = 0; $spiAt = -1
        for ($i = 0; $i -le $bin.Length - $SpiPattern.Length; $i++) {
            $m = $true
            for ($j = 0; $j -lt $SpiPattern.Length; $j++) {
                if ($bin[$i + $j] -ne $SpiPattern[$j]) { $m = $false; break }
            }
            if ($m) { $spiHits++; $spiAt = $i + 16 }
        }
        Info "gate 3 anchor 'mov ecx,0x2001' occurrences: $spiHits (expected 1)"

        if ($spiHits -ne 1) {
            Bad "gate 3 anchor is ambiguous ($spiHits matches) - refusing to patch"
        } elseif ($spiAt -ne $SpiOffset) {
            Bad "gate 3 call is at 0x$($spiAt.ToString('X')) but the known offset is 0x$($SpiOffset.ToString('X'))"
            Say  "        This is a different build. Refusing to patch."
        } else {
            Ok "gate 3 call site located at 0x$($SpiOffset.ToString('X'))"
        }

    # --- gate 1: confirm the IAT slot and its single call site ---
    $asfwOk = $false
    $asfwAt = -1
    if ($spiHits -eq 1 -and $spiAt -eq $SpiOffset) {
        # resolve every FF 15 and find the one targeting the ASFW IAT slot
        $secs = @()
        $e = [BitConverter]::ToInt32($bin, 0x3C)
        $nsec = [BitConverter]::ToUInt16($bin, $e + 6)
        $optsz = [BitConverter]::ToUInt16($bin, $e + 20)
        $st = $e + 24 + $optsz
        for ($i = 0; $i -lt $nsec; $i++) {
            $s = $st + $i * 40
            $secs += [pscustomobject]@{
                VAddr = [BitConverter]::ToUInt32($bin, $s + 12)
                RawPtr = [BitConverter]::ToUInt32($bin, $s + 20)
                RawSize = [BitConverter]::ToUInt32($bin, $s + 16)
                Delta = [BitConverter]::ToInt32($bin, $s + 20) - [BitConverter]::ToInt32($bin, $s + 12)
            }
        }
        function ConvertTo-Rva($off) {
            foreach ($s in $secs) {
                if ($off -ge $s.RawPtr -and $off -lt ($s.RawPtr + $s.RawSize)) {
                    return [int64]$off - $s.Delta
                }
            }
            return $null
        }
        function ConvertTo-File($rva) {
            foreach ($s in $secs) {
                if ($rva -ge $s.VAddr -and $rva -lt ($s.VAddr + [Math]::Max($s.RawSize, 0x1000))) {
                    return [int64]$rva + $s.Delta
                }
            }
            return $null
        }
        $count = 0
        for ($i = 0; $i -le $bin.Length - 6; $i++) {
            if ($bin[$i] -ne 0xFF -or $bin[$i + 1] -ne 0x15) { continue }
            $rel = [BitConverter]::ToInt32($bin, $i + 2)
            $rva = ConvertTo-Rva $i
            if ($null -eq $rva) { continue }
            $tgt = ConvertTo-File ([int64]$rva + 6 + $rel)
            if ($tgt -eq $AsfwIatSlot) { $count++; $asfwAt = $i }
        }
        Info "gate 1 call sites targeting the AllowSetForegroundWindow IAT slot: $count (expected 1)"
        if ($count -eq 1 -and $asfwAt -eq $AsfwOffset) {
            $asfwOk = $true
            Ok "gate 1 call site located at 0x$($AsfwOffset.ToString('X'))"
        } elseif ($count -eq 1) {
            Bad "gate 1 call is at 0x$($asfwAt.ToString('X')) but the known offset is 0x$($AsfwOffset.ToString('X'))"
        } else {
            Bad "gate 1 call site count is $count (expected 1)"
        }
    }

    # --- patch (only reachable when a site actually needs it) ---
    if ($spiHits -eq 1 -and $spiAt -eq $SpiOffset -and $asfwOk) {
        if ($needSpi)  { Info "gate 3 needs patching at 0x$($SpiOffset.ToString('X'))" }
        if ($needAsfw) { Info "gate 1 needs patching at 0x$($AsfwOffset.ToString('X'))" }

        if ($DryRun) {
            Info "would back up, patch $(([int]$needSpi) + ([int]$needAsfw)) site(s), verify, write"
        } else {
            if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
            $orig = Join-Path $BackupDir 'komorebi.exe.orig'
            if (-not (Test-Path $orig)) {
                Copy-Item $KomorebiExe $orig -Force
                Ok "pristine original saved to $orig"
            } else {
                Info "pristine original already saved at $orig"
            }

            $before = [System.IO.File]::ReadAllBytes($KomorebiExe)
            $after  = [byte[]]$before.Clone()
            if ($needSpi)  { [Array]::Copy($PatchBytes, 0, $after, $SpiOffset, 6) }
            if ($needAsfw) { [Array]::Copy($PatchBytes, 0, $after, $AsfwOffset, 6) }

            # verify: exactly the intended bytes differ
            $diffs = @(); for ($i = 0; $i -lt $after.Length; $i++) { if ($after[$i] -ne $before[$i]) { $diffs += $i } }
            $expect = @()
            if ($needSpi)  { $expect += ($SpiOffset..($SpiOffset + 5)) }
            if ($needAsfw) { $expect += ($AsfwOffset..($AsfwOffset + 5)) }
            if (Compare-Object $diffs $expect) {
                Bad "verification failed - changed bytes are not exactly the two call sites. NOT written."
            } else {
                [System.IO.File]::WriteAllBytes($KomorebiExe, $after)
                Fix "patched $(([int]$needSpi) + ([int]$needAsfw)) site(s) - $(Format-Bytes $PatchBytes)"
                Ok  "verified: exactly $($diffs.Count) bytes changed, all inside the two call sites"
            }
        }
    }
    }
}

# ------------------------------------------- gate 4: the missing ASC file
Head "Gate 4  -  app_specific_configuration_path file"

if (Test-Path $KomorebiJson) {
    $cfgRaw = Get-Content $KomorebiJson -Raw
    $ascRef = $null
    if ($cfgRaw -match '"app_specific_configuration_path"\s*:\s*"([^"]+)"') { $ascRef = $matches[1] }
    if (-not $ascRef) {
        Info "app_specific_configuration_path is null - komorebi loads no ASC file, gate 4 not applicable"
    } else {
        $expanded = [Environment]::ExpandEnvironmentVariables($ascRef)
        # komorebi reads this through serde_json, which turns JSON \\ into a
        # single \. PowerShell's ExpandEnvironmentVariables does not, so unescape
        # it here or every path comes out with doubled separators.
        $expanded = $expanded.Replace('\\', '\')
        Info "config references: $ascRef"
        Info "expands to      : $expanded"
        if (Test-Path $expanded) {
            Ok "ASC file present ($((Get-Item $expanded).Length) bytes)"
        } else {
            Fix "ASC file is MISSING - this is what makes komorebi die at asc.rs:40 (os error 2)"
            if ($DryRun) {
                Info "would restore it from $RepoConfig"
            } elseif (-not (Test-Path $RepoConfig)) {
                Bad "cannot restore: $RepoConfig not found"
                Say  "        Copy applications.json back manually, or set"
                Say  "        app_specific_configuration_path to null in $KomorebiJson"
            } else {
                $dir = Split-Path $expanded -Parent
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                Copy-Item $RepoConfig $expanded -Force
                Ok "restored from $RepoConfig ($((Get-Item $expanded).Length) bytes)"
            }
        }
    }
} else {
    Bad "$KomorebiJson not found - komorebi has no configuration"
}

# ------------------------------------------------------- registry + tasks
Head "Environment  -  registry and scheduled tasks"

$flt = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name ForegroundLockTimeout -EA SilentlyContinue).ForegroundLockTimeout
if ($flt -eq 2147483647) {
    Fix "ForegroundLockTimeout is pinned at MAX_INT (2147483647) - resetting to 200000"
    if (-not $DryRun) {
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name ForegroundLockTimeout -Value 200000 -Type DWord
        Ok  "registry now $((Get-ItemProperty 'HKCU:\Control Panel\Desktop').ForegroundLockTimeout)"
    }
} else {
    Ok "ForegroundLockTimeout = $flt"
}
Info "note: on 26H2 the in-memory value is read at session start, so a reboot is"
Info "      needed for a change here to take effect. It does not block the fix."

if (Test-Path $ServiceScript) {
    foreach ($t in 'Komorebi','KomorebiWatchdog') {
        $task = Get-ScheduledTask -TaskName $t -EA SilentlyContinue
        if ($task) {
            $launcher = "$env:USERPROFILE\bin\komorebi-watchdog.exe"
            $bad = ($t -eq 'KomorebiWatchdog') -and ($task.Actions[0].Execute -notlike '*komorebi-watchdog.exe')
            if ($bad) {
                Fix "$t runs powershell.exe directly, which flashes a console window every interval"
                Say  "        re-registering through the windowless GUI launcher"
            } elseif ($task.Principal.RunLevel -ne 'Highest') {
                Fix "$t is registered with RunLevel=$($task.Principal.RunLevel); re-registering as Highest"
            } else {
                Ok "$t is correct (RunLevel=$($task.Principal.RunLevel))"
            }
        } else {
            Fix "$t is missing - it must be registered for logon autostart"
        }
    }
    if (-not $DryRun -and ($script:Fixed -gt 0 -or -not (Get-ScheduledTask -TaskName 'Komorebi' -EA SilentlyContinue))) {
        if (Test-Admin) {
            Say ""
            Say "  Re-registering both tasks via komorebi-service.ps1 -Action install ..."
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ServiceScript -Action install 2>&1 |
                Select-String -Pattern '\[OK\]|\[warn\]|FAILED' | ForEach-Object { Say "        $_" }
        } else {
            Say ""
            Say "  Tasks need re-registering but this shell is not elevated."
            Say "  Run in an ADMIN shell:   & '$ServiceScript' -Action install"
        }
    }
} else {
    Info "$ServiceScript not found - skipping task management"
}

# ------------------------------------------------------------------ verdict --
Head "Result"

Get-Process komorebi,whkd -EA SilentlyContinue |
    Select-Object Name,Id | Format-Table -AutoSize | Out-String | ForEach-Object { Say $_ }

if ($script:Problems -gt 0) {
    Say "$($script:Problems) problem(s) could not be repaired automatically." -ForegroundColor Red
    Say "See the FAIL lines above."
} elseif ($script:Fixed -gt 0) {
    Say "Repaired $($script:Fixed) item(s)." -ForegroundColor Green
    Say ""
    Say "Next:"
    Say "  1. Reboot (the ForegroundLockTimeout SPI value is read at session start)."
    Say "  2. After the reboot komorebi + whkd autostart via the 'Komorebi' task."
    Say "  3. Verify:   komorebic.exe state"
} else {
    Say "Everything already healthy - nothing to do." -ForegroundColor Green
    Say "Verify with:   komorebic.exe state"
}

Say ""
exit $(if ($script:Problems -gt 0) { 1 } else { 0 })
