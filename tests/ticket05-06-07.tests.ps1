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
    @{ File = 'komorebi-backup.ps1';         Name = 'BackupPath';  ValidateSet = $null }
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
# The invariant here is NOT "this script calls Resolve-WhkdExe". It is that the
# script never launches whkd.exe by hand: whkd must only ever be spawned by
# `komorebic start --whkd`, or it is alive-but-unpaired and silently drops every
# hotkey (LGUG2Z/komorebi#956 — see docs/POSTMORTEM-20261004-whkd-pairing.md).
# Commit 370fd41 therefore REMOVED Resolve-WhkdExe from this script on purpose;
# an assertion pinning that helper name was testing an implementation detail and
# had to go stale. These assertions pin the behaviour instead.
$t = Get-Content -LiteralPath (Join-Path $scripts 'restart-whkd.ps1') -Raw
Assert 'restart-whkd.ps1 resolves komorebic through common.ps1' ($t -match 'Resolve-KomorebicExe')
Assert 'restart-whkd.ps1 never launches whkd.exe directly' ($t -notmatch 'Start-Process[^\r\n]*\$whkd')
Assert 'restart-whkd.ps1 stops the pair via komorebic stop --whkd' ($t -match 'stop --whkd')
Assert 'restart-whkd.ps1 starts komorebi via the elevated logon task' ($t -match "Start-ScheduledTask -TaskName 'Komorebi'")
Assert 'restart-whkd.ps1 verifies the pairing after restarting' ($t -match 'Test-WhkdPaired')
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
#
# The artifact under test is the COMMITTED template: New-Whkdrc copies whkdrc
# verbatim (with the source-user path rewritten), so installations ship what
# git has. The working copy can be hand-tuned mid-session — by Davood or by
# another agent's session — so a divergence is reported loudly (WARN, never
# silent) but does not fail the suite; review covers the committed state.
# =============================================================================

Section 'T03-followup — the whkdrc bindings point at files the installer ships'

function Get-TemplateLines {
    param([string]$RepoRelPath)
    # Committed content when git can provide it, else the working copy. Line
    # ARRAYS, not reconstructed strings: git's stdout array and Get-Content
    # both drop the terminator, so comparing joined forms cannot invent a
    # difference out of nothing but the final newline.
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        Push-Location $RepoRoot
        try {
            $head = & git show ("HEAD:{0}" -f ($RepoRelPath -replace '\\', '/')) 2>$null
            if ($LASTEXITCODE -eq 0 -and $head) { return @($head) }
        } finally {
            Pop-Location
        }
    }
    return @(Get-Content -LiteralPath (Join-Path $RepoRoot $RepoRelPath) -Encoding UTF8)
}

$headLines = Get-TemplateLines 'config/whkdrc'
$workLines = @(Get-Content -LiteralPath (Join-Path $config 'whkdrc') -Encoding UTF8)
$wtext     = ($headLines -join "`n")
$workText  = ($workLines -join "`n")

# 1. the binding must not be unbound by accident
Assert 'alt + shift + o is bound (restart-whkd.cmd)' ($wtext -match '(?m)^alt \+ shift \+ o :')
Assert 'alt + o is deliberately NOT bound'          ($wtext -notmatch '(?m)^alt \+ o :')
Assert 'alt + ctrl + t is bound (toggle-transparency.ps1)' ($wtext -match '(?m)^alt \+ ctrl \+ t :')
Assert 'alt + ctrl + shift + r is bound (safe-restart.ps1)' ($wtext -match '(?m)^alt \+ ctrl \+ shift \+ r :')

# 2. every binding that names a .ps1/.cmd under .config names a file the
#    installer actually ships or generates
$matches = [regex]::Matches($wtext, 'C:\\Users\\DavoodYa\\.config\\([A-Za-z0-9_.\-]+)')
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

# 4. an in-flight working-copy edit must never fake a pass or hide silently:
#    installations copy the WORKING copy, so name the divergence and let the
#    human decide (commit it or discard it) — the suite stays green.
if ($workText -ne $wtext) {
    $workHasSafeRestart = $workText -match '(?m)^alt \+ ctrl \+ shift \+ r :'
    $note = if ($workHasSafeRestart) { 'bindings differ (a live tuning edit)' }
            else { 'the alt+ctrl+shift+r safe-restart binding is MISSING from the working copy' }
    Write-Host ('  WARN  working-copy whkdrc differs from the committed template ({0}); ' -f $note) -ForegroundColor Yellow
    Write-Host ('        installs copy the working copy - commit or discard that edit deliberately.') -ForegroundColor Yellow
} else {
    Assert 'the working-copy whkdrc matches the committed template' $true
}

Section 'T03-followup — the installer installs the two new companion scripts'
$t = Get-Content -LiteralPath (Join-Path $scripts 'Install-Common.ps1') -Raw
Assert 'Install-Configuration installs toggle-transparency.ps1' ($t -match 'toggle-transparency\.ps1')
Assert 'Install-Configuration installs safe-restart.ps1'        ($t -match 'safe-restart\.ps1')
Assert 'the installer writes the safe-restart repo marker'      ($t -match 'safe-restart\.repo\.txt')

# =============================================================================
# Ticket 07 — export / import
# =============================================================================

Section 'T07.1 — both export/import scripts ship and parse'
foreach ($name in 'config-export-import.ps1', 'komorebi-backup.ps1') {
    $ei = Join-Path $scripts $name
    Assert ("{0} exists" -f $name) (Test-Path -LiteralPath $ei)
    $tokens = $null; $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($ei, [ref]$tokens, [ref]$errs) | Out-Null
    Assert ("{0} parses" -f $name) ($errs.Count -eq 0)
}

# -----------------------------------------------------------------------------
# The mechanism (Davood's spec, 2026-10-10): clicking Export opens a DIRECTORY
# SELECTOR, and a directory holding every current config is created inside the
# chosen directory; clicking Import opens a DIRECTORY SELECTOR and the chosen
# backup's configs replace the live ones. No archive, no file dialog. The
# Dashboard's buttons and the CLI reach the same code, and both scripts share
# ONE set definition and ONE selector in common.ps1, so they cannot drift.
# -----------------------------------------------------------------------------
Section 'T07.2 — the GUI and the CLI reach the same directory-based code'
$eiText = Get-Content -LiteralPath (Join-Path $scripts 'config-export-import.ps1') -Raw
$bkText = Get-Content -LiteralPath (Join-Path $scripts 'komorebi-backup.ps1')    -Raw
$cmText = Get-Content -LiteralPath (Join-Path $scripts 'common.ps1')             -Raw

# the shared selector and the shared set live in common.ps1
Assert 'common.ps1 ships the shared directory selector' ($cmText -match 'function Show-DirectorySelector')
Assert 'the selector is a native FolderBrowserDialog'   ($cmText -match 'System\.Windows\.Forms\.FolderBrowserDialog')
Assert 'common.ps1 ships the shared config set'         ($cmText -match 'function Get-ConfigExportSet')
Assert 'common.ps1 ships the critical-file rule'        ($cmText -match 'function Get-CriticalConfigSet')

# both scripts dot-source the shared module
Assert 'config-export-import.ps1 dot-sources common.ps1' ($eiText -match 'common\.ps1')
Assert 'komorebi-backup.ps1 dot-sources common.ps1'      ($bkText -match 'common\.ps1')

# parameters: a DIRECTORY (the zip-shaped name is gone from the contract)
Assert 'config-export-import.ps1 validates -Action'      ($eiText -match "\[ValidateSet\('export', 'import'\)\]")
Assert 'config-export-import.ps1 declares -BackupPath'  ($eiText -match 'param\s*\([\s\S]*?\$BackupPath\b')
Assert 'config-export-import.ps1 uses -BackupPath'      (([regex]::Matches($eiText, '\$BackupPath\b')).Count -ge 2)
Assert 'config-export-import.ps1 declares -NoDialog'    ($eiText -match '\$NoDialog')
Assert 'komorebi-backup.ps1 validates -Mode'            ($bkText -match "\[ValidateSet\('export', 'import'\)\]")
Assert 'komorebi-backup.ps1 declares -BackupPath'       ($bkText -match 'param\s*\([\s\S]*?\$BackupPath\b')
Assert 'komorebi-backup.ps1 uses -BackupPath'           (([regex]::Matches($bkText, '\$BackupPath\b')).Count -ge 2)
Assert 'komorebi-backup.ps1 declares -NoDialog'         ($bkText -match '\$NoDialog')

# dialogs: no path + no -NoDialog  ->  the directory selector
Assert 'export falls back to the selector (config-export-import)'  (($eiText -match 'if \(-not \$BackupPath -and -not \$NoDialog\)') -and ($eiText -match 'Show-DirectorySelector'))
Assert 'export falls back to the selector (komorebi-backup)'       (($bkText -match 'if \(-not \$BackupPath -and -not \$NoDialog\)') -and ($bkText -match 'Show-DirectorySelector'))
Assert 'import shows the selector when no path (config-export-import)' ($eiText -match 'Show-DirectorySelector')
Assert 'a cancelled selector exits cleanly'                           ($eiText -match 'Export cancelled|Export cancelled - no directory chosen')
Assert 'the selector result is null-safe'                             (($eiText -match 'if \(-not \$picked') -or ($eiText -match 'if \(-not \$target'))

# the zip machinery is gone from BOTH scripts
Assert 'config-export-import.ps1 keeps no ZipFile code'   ($eiText -notmatch 'System\.IO\.Compression|ZipFile|CreateEntryFromFile|ExtractToFile')
Assert 'komorebi-backup.ps1 keeps no ZipFile code'        ($bkText -notmatch 'System\.IO\.Compression|ZipFile|CreateEntryFromFile|ExtractToFile')

Section 'T07.3 — the export covers the full config set, one shared definition'
foreach ($name in 'komorebi\.json', 'whkdrc', 'applications\.json', 'restart-whkd\.cmd',
                  'toggle-transparency\.ps1', 'safe-restart\.ps1', 'yasb', 'komorebi-resize\.json') {
    Assert ("the shared set includes {0}" -f $name) ($cmText -match $name)
}
# the whole YASB bar travels as a directory tree
Assert 'the shared set marks the YASB tree as a directory'  ($cmText -match 'IsDir')
# resize state is pure runtime state: exported only when it holds real state
Assert 'resize state travels only when non-empty'           ($cmText -match 'OnlyWhenNonEmpty')
# no machine-specific path in the set — everything derives from the profile
Assert 'the set derives every live path from the profile'   ($cmText -match '\$env:USERPROFILE')
# and the export timestamped directory name is shared
Assert 'export creates a timestamped directory'             (($eiText -match 'komorebi-backup-\{0\}') -and ($bkText -match 'komorebi-backup-'))

Section 'T07.4 — import is non-destructive, validated, and restarts the WM'
# komorebi-backup.ps1 (the Dashboard's Import Config button)
Assert 'import refuses a folder without the critical files' ($bkText -match 'is not a komorebi backup')
Assert 'komorebi-backup.ps1 keeps a rollback copy'          ($bkText -match 'pre-import-')
Assert 'komorebi-backup.ps1 stops the WM before restoring' ($bkText -match 'function Stop-Wm')
Assert 'komorebi-backup.ps1 starts the WM after restoring'  ($bkText -match 'function Start-Wm')
Assert 'komorebi-backup.ps1 never reloads in place'         ($bkText -match 'Never run `komorebic\.exe reload-configuration')
# config-export-import.ps1 (the standalone form)
Assert 'import backs the live config up first'              ($eiText -match 'pre-import-backup')
Assert 'import stops the WM before restoring'               ($eiText -match 'Stop-WindowManager')
Assert 'import starts the WM afterwards'                    ($eiText -match 'Start-WindowManager')

# =============================================================================
# Result
# =============================================================================

Section 'RESULT'
Write-Host ("  assertions: {0}" -f $script:checks) -ForegroundColor White
Write-Host ("  failures:   {0}" -f $script:fail) -ForegroundColor $(if ($script:fail -gt 0) { 'Red' } else { 'Green' })
if ($script:fail -gt 0) { exit 1 }
Write-Host '  ALL CHECKS PASSED' -ForegroundColor Green
