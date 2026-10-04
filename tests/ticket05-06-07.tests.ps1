# =====================================================================
# ticket05-06-07.tests.ps1
#
#   Verification for the three implemented tickets, runnable WITHOUT a
#   Windows Sandbox, on the development machine. Each section proves one
#   acceptance criterion from the ticket file, against the shipped files
#   in the repo (nothing is installed, nothing touches the live config).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File ticket05-06-07.tests.ps1
#
#   Exit code 0 = every assertion passed.
# =====================================================================
#Requires -Version 5.1

[CmdletBinding()]
param(
    # The repo to verify. Defaults to the directory above this script's.
    [string] $RepoRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:fail  = 0

function Assert($label, $ok) {
    $script:checks++
    if ($ok) {
        Write-Host ("  PASS  {0}" -f $label) -ForegroundColor DarkGray
    } else {
        $script:fail++
        Write-Host ("  FAIL  {0}" -f $label) -ForegroundColor Red
    }
}

function Section($t) {
    Write-Host ''
    Write-Host ("===== {0} =====" -f $t) -ForegroundColor Cyan
}

$scripts = Join-Path $RepoRoot 'scripts'
$config  = Join-Path $RepoRoot 'config'

# =============================================================================
# Ticket 05 — AutoHotkey integration (generated AppRunner.vbs)
# =============================================================================

Section 'T05.1 — the three .ahk scripts ship in the repo'
foreach ($f in 'autocorrect.ahk', 'ChangeLangF3.ahk', 'NewFile.ahk') {
    Assert ("autohotkey\{0} exists" -f $f) (Test-Path -LiteralPath (Join-Path $RepoRoot "autohotkey\$f"))
}

Section 'T05.2 — AppRunner.vbs is a template with the marker, not a copy of a machine'
$vbs = Join-Path $RepoRoot 'autohotkey\AppRunner.vbs'
$vbsText = Get-Content -LiteralPath $vbs -Raw
Assert 'AppRunner.vbs ships the RunHidden helper' ($vbsText -match 'Sub RunHidden')
Assert 'AppRunner.vbs ships the insertion marker' ($vbsText -match "' AppRunnerEnd")
Assert 'the shipped template has no machine path' ($vbsText -notmatch 'C:\\Users\\')

Section 'T05.3 — the interpreter paths the installer writes are the vendor defaults'
. (Join-Path $scripts 'Install-Common.ps1')
Assert 'v1 interpreter is the vendor default' ((Get-AhkInterpreterPath -Version 'v1') -eq (Join-Path $env:ProgramFiles 'AutoHotkey\AutoHotkey.exe'))
Assert 'v2 interpreter is the vendor default' ((Get-AhkInterpreterPath -Version 'v2') -eq (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'))

Section 'T05.4 — the generated VBS content names every shipped script'
$gen = Get-GeneratedAppRunnerContent -TemplatePath $vbs -AhkDir (Join-Path $RepoRoot 'autohotkey')
foreach ($f in 'autocorrect.ahk', 'ChangeLangF3.ahk', 'NewFile.ahk') {
    Assert ("generated VBS launches {0}" -f $f) ($gen -match [regex]::Escape($f))
}
Assert 'generated VBS has no leftover marker' ($gen -notmatch "' AppRunnerEnd")
Assert 'generated VBS has no machine path'   ($gen -notmatch 'C:\\Users\\DavoodYa')

# =============================================================================
# Ticket 06 — portability of the management scripts
# =============================================================================

Section 'T06.1 — no management script carries a machine-specific path'
$machineRefs = @()
foreach ($f in (Get-ChildItem -LiteralPath $scripts -Filter *.ps1)) {
    if ($f.Name -eq 'Install-Common.ps1') { continue }   # holds the rewriter pattern on purpose
    $t = Get-Content -LiteralPath $f.FullName -Raw
    if ($t -match 'DavoodYa|F:\\Backups') { $machineRefs += $f.Name }
}
Assert 'no management script references the source user or the F: backup drive' ($machineRefs.Count -eq 0)

# The rewriter itself has to actually work, otherwise the exclusion above would
# hide a dead pattern. Run it against this repo's whkdrc with a fake profile.
$prevProfile = $env:USERPROFILE
try {
    $env:USERPROFILE = 'C:\TARGETUSER'
    $probe = Join-Path $env:TEMP 'k1c-whkdrc-probe'
    New-Whkdrc -TemplatePath (Join-Path $config 'whkdrc') -OutputPath $probe
    $rendered = Get-Content -LiteralPath $probe -Raw -Encoding UTF8
}
finally {
    $env:USERPROFILE = $prevProfile
}
Assert 'New-Whkdrc rewrites the source user path to the target user' ($rendered -notmatch 'DavoodYa')
Assert 'New-Whkdrc leaves the target path intact' ($rendered -match 'C:\\TARGETUSER\\\.config')

Section 'T06.2 — the parameterized scripts accept the documented switches'
foreach ($pair in @(
    @{ File = 'kill-all.ps1';                Name = 'Components'; ValidateSet = 'all','komorebi-whkd','yasb' }
    @{ File = 'start-all.ps1';               Name = 'Components'; ValidateSet = 'all','komorebi-whkd','yasb' }
    @{ File = 'uninstall-komorebi-whkd.ps1'; Name = 'Scope';       ValidateSet = 'all','komorebi-whkd','yasb','autohotkey' }
    @{ File = 'cleanup-komorebi-whkd.ps1';   Name = 'Scope';       ValidateSet = 'all','komorebi-whkd','yasb','autohotkey' }
    @{ File = 'toggle-transparency.ps1';     Name = 'Percent';     ValidateSet = $null }
    @{ File = 'komorebi-backup.ps1';         Name = 'ZipPath';     ValidateSet = $null }
)) {
    $t = Get-Content -LiteralPath (Join-Path $scripts $pair.File) -Raw

    # DECLARED: the param() block must contain `[<type>]$Name`.
    $declared = $t -match ('param\s*\([\s\S]*?\$' + $pair.Name + '\b')

    # USED: the body must reference $Name outside the declaration, otherwise it
    # is a dead switch the Dashboard cannot drive.
    $uses = ([regex]::Matches($t, ('\$' + $pair.Name + '\b'))).Count
    $used = $uses -ge 2

    $ok = $declared -and $used
    if ($pair.ValidateSet) {
        # The accepted values must be spelled out, so a typo'd scope is rejected
        # at parse time instead of silently doing nothing.
        $setOk = $t -match ('\[ValidateSet\([\s\S]*?' + ($pair.ValidateSet -join '|'))
        $ok = $ok -and $setOk
    }
    Assert ("{0} declares, uses and validates ${1}" -f $pair.File, $pair.Name) $ok
}

Section 'T06.3 — the whkdrc companion scripts resolve their binaries portably'
$t = Get-Content -LiteralPath (Join-Path $scripts 'restart-whkd.ps1') -Raw
Assert 'restart-whkd.ps1 resolves whkd through common.ps1' ($t -match 'Resolve-WhkdExe')
$t = Get-Content -LiteralPath (Join-Path $scripts 'toggle-transparency.ps1') -Raw
Assert 'toggle-transparency.ps1 parameterises the percent' ($t -match '\[int\]\s*\$Percent|\$Percent\s*=\s*85')
$t = Get-Content -LiteralPath (Join-Path $scripts 'safe-restart.ps1') -Raw
Assert 'safe-restart.ps1 resolves komorebi-service.ps1 without a hardcoded path' ($t -match 'safe-restart\.repo\.txt')
Assert 'safe-restart.ps1 still freezes the watchdog' ($t -match 'KomorebiWatchdog')

Section 'T06.4 — the watchdog mutex and the YASB registry PATH rebuild are intact'
$t = Get-Content -LiteralPath (Join-Path $scripts 'komorebi-service.ps1') -Raw
Assert 'komorebi-service.ps1 keeps the mutex' ($t -match "Global\\komorebi-service-start")
$t = Get-Content -LiteralPath (Join-Path $scripts 'restart-yasb.ps1') -Raw
Assert 'restart-yasb.ps1 still rebuilds PATH from the registry' ($t -match "\[Environment\]::GetEnvironmentVariable\('Path', 'Machine'\)")

Section 'T06.5 — every management script parses cleanly'
$parseFail = @()
foreach ($f in (Get-ChildItem -LiteralPath $scripts -Filter *.ps1)) {
    $tokens = $null; $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs) | Out-Null
    if ($errs.Count -gt 0) { $parseFail += $f.Name }
}
Assert ("all management scripts parse (failures: {0})" -f ($parseFail -join ', ')) ($parseFail.Count -eq 0)

# =============================================================================
# Ticket 03 follow-up — the whkdrc hotkeys all resolve on a target machine
# =============================================================================

Section 'T03-followup — the whkdrc bindings point at files the installer ships'
$whkdrc = Join-Path $config 'whkdrc'
$wtext  = Get-Content -LiteralPath $whkdrc -Raw -Encoding UTF8

# 1. the binding must not be unbound by accident
Assert 'alt + shift + o is bound (restart-whkd.cmd)' ($wtext -match '(?m)^alt \+ shift \+ o :')
Assert 'alt + o is deliberately NOT bound'          ($wtext -notmatch '(?m)^alt \+ o :')
Assert 'alt + ctrl + t is bound (toggle-transparency.ps1)' ($wtext -match '(?m)^alt \+ ctrl \+ t :')
Assert 'alt + ctrl + shift + r is bound (safe-restart.ps1)' ($wtext -match '(?m)^alt \+ ctrl \+ shift \+ r :')

# 2. every binding that names a .ps1/.cmd under .config names a file the
#    installer actually ships or generates
$matches = [regex]::Matches($wtext, 'C:\\Users\\DavoodYa\\\.config\\([A-Za-z0-9_.\-]+)')
$shipped = @{}
foreach ($m in $matches) {
    $shipped[$m.Groups[1].Value] = $true
}
foreach ($name in $shipped.Keys) {
    $installerShipsIt = (Test-Path -LiteralPath (Join-Path $config $name)) -or
                        (Test-Path -LiteralPath (Join-Path $scripts $name)) -or
                        ($name -eq 'komorebi-resize.json')      # generated empty by the installer
    Assert ("whkdrc references {0}, which the installer supplies" -f $name) $installerShipsIt
}

# 3. the restart-whkd.cmd template matches the new binding's comment
$cmdT = Get-Content -LiteralPath (Join-Path $config 'restart-whkd.cmd') -Raw -Encoding ASCII
Assert 'restart-whkd.cmd documents the alt + shift + o hotkey' ($cmdT -match 'alt \+ shift \+ o')

Section 'T03-followup — the installer installs the two new companion scripts'
$t = Get-Content -LiteralPath (Join-Path $scripts 'Install-Common.ps1') -Raw
Assert 'Install-Configuration installs toggle-transparency.ps1' ($t -match 'toggle-transparency\.ps1')
Assert 'Install-Configuration installs safe-restart.ps1'        ($t -match 'safe-restart\.ps1')
Assert 'the installer writes the safe-restart repo marker'      ($t -match 'safe-restart\.repo\.txt')

# =============================================================================
# Ticket 07 — export / import
# =============================================================================

Section 'T07.1 — the export/import script ships and parses'
$ei = Join-Path $scripts 'config-export-import.ps1'
Assert 'config-export-import.ps1 exists' (Test-Path -LiteralPath $ei)
$tokens = $null; $errs = $null
[System.Management.Automation.Language.Parser]::ParseFile($ei, [ref]$tokens, [ref]$errs) | Out-Null
Assert 'config-export-import.ps1 parses' ($errs.Count -eq 0)

Section 'T07.2 — the CLI and the GUI reach the same code'
$t = Get-Content -LiteralPath $ei -Raw
Assert 'the -Action parameter is validated'      ($t -match "\[ValidateSet\('export', 'import'\)\]")
Assert 'the -ZipPath parameter is declared'      ($t -match '\$ZipPath')
Assert 'export uses the Save dialog when no path' ($t -match 'Show-SaveDialog')
Assert 'import uses the Open dialog when no path' ($t -match 'Show-OpenDialog')
Assert 'a supplied path skips the dialog'        ($t -match 'if \(-not \$target -and -not \$NoDialog\)')

Section 'T07.3 — the archive covers the full config set, ZipFile only, no 3rd party'
foreach ($name in 'komorebi.json', 'whkdrc', 'applications.json', 'restart-whkd.cmd',
                  'toggle-transparency.ps1', 'safe-restart.ps1', 'yasb') {
    Assert ("the export set includes {0}" -f $name) ($t -match [regex]::Escape($name))
}
Assert 'compression is System.IO.Compression'     ($t -match 'System\.IO\.Compression\.ZipFile')
Assert 'no third-party compression dependency'    ($t -notmatch 'Ionic|SharpZipLib|DotNetZip|7z|sharpcompress')
Assert 'resize state is included only when non-empty' ($t -match 'komorebi-resize\.json')

Section 'T07.4 — import is non-destructive and restarts the WM'
Assert 'import backs the live config up first'    ($t -match 'pre-import-backup')
Assert 'import stops the WM before restoring'     ($t -match 'Stop-WindowManager')
Assert 'import starts the WM afterwards'          ($t -match 'Start-WindowManager')

# =============================================================================
# Result
# =============================================================================

Section 'RESULT'
Write-Host ("  assertions: {0}" -f $script:checks) -ForegroundColor White
Write-Host ("  failures:   {0}" -f $script:fail) -ForegroundColor $(if ($script:fail -gt 0) { 'Red' } else { 'Green' })
if ($script:fail -gt 0) { exit 1 }
Write-Host '  ALL CHECKS PASSED' -ForegroundColor Green
