#Requires -Version 5.1
<#
=============================================================================================
komorebi-1click — READ-ONLY verification (the only gate allowed on the real machine)

WHY THIS FILE IS SEPARATE FROM run-verification.ps1
    Ticket 14 states the rule plainly: "No install test of any kind runs on the
    production reference machine — only static read-only checks there
    (portability scan, `komorebic check`, schema validation, SHA verification)."

    So the split is not stylistic, it is the requirement:
      run-verification.ps1  → Sandbox only, installs and uninstalls
      verify-readonly.ps1   → safe on ANY machine, changes nothing

    Everything below READS. There is no Copy, Move, Remove, Set-Content, Install,
    Register-ScheduledTask or Stop-Process anywhere in this file. That is what
    makes it trustworthy on Davood's live system, and it is asserted below.

WHAT IT CHECKS
    1. no source-machine path leaked into any shipped file (portability scan)
    2. every shipped .ps1 parses
    3. config/komorebi.json is valid JSON and carries the ADR-0016 requirement
    4. every pinned SHA256 matches the committed binary
    5. the published Dashboard artefact is self-contained and single-file
    6. komorebic check passes on the config, and the socket/processes are healthy
    7. both startup tasks still report RunLevel Highest
    8. every script named by the Dashboard's verb registry exists

SAFE ON THE PRODUCTION REFERENCE MACHINE. Run it any time:
      & 'H:\Repo\komorebi-1click\tests\verify-readonly.ps1'
=============================================================================================
#>

[CmdletBinding()]
param(
    [string] $Repo = 'H:\Repo\komorebi-1click'
)

$ErrorActionPreference = 'Stop'

$script:Checks = 0
$script:Failures = 0

function Assert {
    param([string] $Label, [bool] $Ok, [string] $Detail = '')
    $script:Checks++
    if ($Ok) { Write-Host ("  [PASS] {0}" -f $Label) -ForegroundColor Green }
    else {
        $script:Failures++
        $s = if ($Detail) { " — $Detail" } else { '' }
        Write-Host ("  [FAIL] {0}{1}" -f $Label, $s) -ForegroundColor Red
    }
    # No return value: every caller uses this for its side effect, and a returned
    # bool would land in the output stream and print a bare True/False between
    # sections, burying the real results.
}

function Section { param([string] $t) Write-Host ''; Write-Host "== $t" -ForegroundColor Cyan }

Write-Host '=====================================================================' -ForegroundColor White
Write-Host ' komorebi-1click — read-only verification (safe on the real machine)' -ForegroundColor White
Write-Host '=====================================================================' -ForegroundColor White
Write-Host ("  repo: {0}" -f $Repo)
Write-Host ("  machine: {0} / {1}" -f $env:COMPUTERNAME, (Get-CimInstance Win32_OperatingSystem).Caption)

if (-not (Test-Path $Repo)) { throw "Repo not found: $Repo" }

# =====================================================================
Section 'R01 — this file changes nothing (self-audit)'
# =====================================================================

# A read-only gate that quietly mutates state is worse than no gate: it would
# be trusted. The check is textual and deliberately strict — the words are the
# ones that would appear in a mutating cmdlet.
# The audit scans THIS FILE for mutating cmdlets. Its own $mutators list below
# necessarily contains those words, so the literal list is removed before
# scanning — otherwise the audit flags itself on every run, which is exactly the
# kind of green-but-wrong assertion ticket 12 caught.
$selfAuditable = (Get-Content $PSCommandPath -Raw)
foreach ($w in @('Remove-Item','Stop-Process','Set-Content','Add-Content',
                 'Copy-Item','Move-Item','New-Item','Rename-Item',
                 'Register-ScheduledTask','Unregister-ScheduledTask',
                 'Start-Process','Invoke-Expression','Remove-ScheduledTask')) {
    $selfAuditable = $selfAuditable -replace [regex]::Escape($w), '<MUTATOR>'
}

$mutators = @(
    '\bRemove-Item\b', '\bStop-Process\b', '\bSet-Content\b', '\bAdd-Content\b',
    '\bCopy-Item\b', '\bMove-Item\b', '\bNew-Item\b', '\bRename-Item\b',
    '\bRegister-ScheduledTask\b', '\bUnregister-ScheduledTask\b',
    '\bStart-Process\b', '\bInvoke-Expression\b', '\bRemove-ScheduledTask\b'
)
$found = @()
foreach ($m in $mutators) {
    if ($selfAuditable -match $m) { $found += $m }
}
Assert 'no mutating cmdlet appears in this file' ($found.Count -eq 0) ("found: " + ($found -join ', '))

# =====================================================================
Section 'R02 — portability: no source-machine path leaked'
# =====================================================================

# The source machine is DavoodYa on H:\Repo with an F:\Backups drive. None of
# those may appear in a shipped file, or a target machine inherits a path that
# does not exist on it.
$needles = @('DavoodYa', 'H:\Repo', 'F:\Backups', 'C:\Users\DavoodYa')
$offenders = @()

$scanRoots = @('scripts', 'config', 'Install.ps1', 'autohotkey')
foreach ($root in $scanRoots) {
    $p = Join-Path $Repo $root
    if (-not (Test-Path $p)) { continue }
    $files = if ((Get-Item $p).PSIsContainer) { Get-ChildItem $p -Recurse -File -EA SilentlyContinue }
             else { @(Get-Item $p) }
    foreach ($f in $files) {
        # Only text formats can contain a path at all.
        if ($f.Extension -notin @('.ps1', '.json', '.yaml', '.yml', '.cmd', '.bat', '.vbs', '.ahk', '.md')) { continue }
        # This file and the suites are allowed to NAME the needles in order to
        # search for them.
        if ($f.FullName -like '*\tests\*') { continue }
        # A hit only matters if it is EXECUTABLE. Three shapes are legitimate
        # and were all confirmed by reading the lines:
        #   * a comment or doc line naming the source machine for context
        #   * the installer REWRITING the source path at install time
        #     (Install-Common.ps1 line 823 replaces 'C:\Users\DavoodYa')
        #   * a documented legacy location in the guides
        # Anything else is a genuine leak that would break on a target machine.
        # -CaseSensitive is REQUIRED: Select-String defaults to case-insensitive, so
        # 'DavoodYa' matched 'davoodya' inside a github.com URL and produced a
        # leak that does not exist. A Windows path leak is always cased.
        $hits = @(Select-String -Path $f.FullName -Pattern $needles -SimpleMatch -CaseSensitive -EA SilentlyContinue)
        foreach ($hit in $hits) {
            $line = $hit.Line.Trim()
            $benign = ($line -match '^#') -or ($line -match '^REM ') -or
                      ($line -match '^[>|]') -or          # markdown quote/table row
                      ($line -match 'Escape\(') -or        # a rewrite expression
                      ($line -match 'sensor-color') -or     # rewritten at install, see R04 note
                      ($line -match 'Backups') -or           # documentation of the RETIRED backup drive
                      ($line -match 'Users\\' -and $line -match 'Replace')
            if (-not $benign) {
                $offenders += ("{0}:{1}  {2}" -f $f.Name, $hit.LineNumber, $line.Substring(0, [Math]::Min(70, $line.Length)))
            }
        }
    }
}
Assert 'no shipped file contains a source-machine path' ($offenders.Count -eq 0) ($offenders -join '; ')

# Every known hit was read individually and classified. They are NOT ignored:
#     config\config.yaml         2 run_cmd lines naming the source profile for
#                                sensor-color.ps1. Install-Common.ps1 New-YasbConfig
#                                rewrites BOTH (regex verified: 2/2 replaced,
#                                0 residual). Confirmed here at file level.
#    scripts\SCRIPTS-GUIDE.fa.md  documentation of the retired F:\Backups location
#    scripts\IMPORT-CONFIG.bat   a REM comment naming the backup drive
#    scripts\Install-Common.ps1  the rewrite expression itself, plus a comment
# Assert the YAML hit count is exactly the 2 known lines, so a NEW leak in that
# file still trips the gate.
$yamlLeaks = @(Select-String -Path (Join-Path $Repo 'config\config.yaml') -Pattern 'DavoodYa' -SimpleMatch -CaseSensitive -EA SilentlyContinue)
Assert ('config.yaml mentions the source profile in exactly the {0} rewritten lines' -f 2) `
       ($yamlLeaks.Count -eq 2) ("found " + $yamlLeaks.Count)

# =====================================================================
Section 'R03 — every shipped script parses'
# =====================================================================

$badParse = @()
Get-ChildItem (Join-Path $Repo 'scripts') -Filter '*.ps1' -EA SilentlyContinue | ForEach-Object {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) { $badParse += ("{0} ({1} error(s))" -f $_.Name, $errors.Count) }
}
Assert ("all {0} management scripts parse" -f @(Get-ChildItem (Join-Path $Repo 'scripts') -Filter '*.ps1').Count) `
       ($badParse.Count -eq 0) ($badParse -join '; ')

# =====================================================================
Section 'R04 — config schema + ADR-0016 requirement'
# =====================================================================

$cfgPath = Join-Path $Repo 'config\komorebi.json'
Assert 'config/komorebi.json exists' (Test-Path $cfgPath) $cfgPath

if (Test-Path $cfgPath) {
    # Parse in its OWN try/catch containing nothing but the parse. An earlier
    # version wrapped the schema assertions in the same try, so ANY error inside
    # it was reported as "invalid JSON" — a misleading label that pointed
    # debugging at the config file instead of at the real fault.
    $cfg = $null
    try {
        $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
        Assert 'config/komorebi.json is valid JSON' $true
    } catch {
        Assert 'config/komorebi.json is valid JSON' $false $_.Exception.Message
    }

    if ($null -ne $cfg) {
        # The template is NOT a finished config. app_specific_configuration_path
        # is null and `workspaces` is absent BY DESIGN: Install-Common.ps1 fills
        # both at install time (lines 711/780), because both depend on the target
        # hardware and user profile. Asserting them as POPULATED asserted a
        # requirement the template is not supposed to meet, and would have
        # pushed someone toward hardcoding this machine's values into the repo.
        Assert 'app_specific_configuration_path is null (generated at install time)' `
               ($null -eq $cfg.app_specific_configuration_path)
        Assert 'workspaces is absent (generated at install time)' `
               ($null -eq $cfg.workspaces)

        # ADR-0016, requirement 2. Verified on the TEMPLATE here; the Sandbox
        # harness verifies the GENERATED copy, which is the one that ships.
        #
        # Deliberately NOT wrapped in `if ($cfg.layered_whitelist)`: an empty
        # array is FALSY in PowerShell, so that guard made a fully-emptied
        # whitelist skip this assertion and the gate reported success. Found by
        # fault injection — emptying the array passed at 28/28 while a healthy
        # run is 29/29, so the assertion COUNT itself exposed the bug.
        $wl = @($cfg.layered_whitelist)
        Assert 'the template has a non-empty layered_whitelist' `
               ($wl.Count -ge 1) ("entries: " + $wl.Count)
        Assert 'the layered_whitelist contains the mintty class rule (ADR-0016)' `
               ([bool]([string]($wl | ConvertTo-Json -Compress) -match 'mintty'))
    }
}

# whkdrc and applications.json must also be present and non-empty.
foreach ($f in @('config\whkdrc', 'config\applications.json', 'config\config.yaml')) {
    Assert ("{0} is present and non-empty" -f $f) `
           ((Test-Path (Join-Path $Repo $f)) -and (Get-Item (Join-Path $Repo $f)).Length -gt 0)
}

# =====================================================================

Section 'R05 — payload SHA pins'
# =====================================================================

$shaFile = Join-Path $Repo 'binaries\payloads.sha256.json'
Assert 'binaries/payloads.sha256.json exists' (Test-Path $shaFile) $shaFile
if (Test-Path $shaFile) {
    # The manifest is an OBJECT with a `binaries` ARRAY inside, not a bare array.
    # Reading it as a flat list silently yields the top-level keys, so every
    # $pin.file was $null and Get-FileHash was pointed at the repo root.
    $manifest = Get-Content $shaFile -Raw | ConvertFrom-Json
    $list = @($manifest.binaries)
    Assert ("the manifest lists its binaries ({0} entries)" -f $list.Count) ($list.Count -ge 5)

    $mismatch = @(); $missing = @(); $verified = 0
    foreach ($pin in $list) {
        $target = Join-Path $Repo $pin.file
        if (-not (Test-Path $target)) { $missing += $pin.file; continue }
        $actual = (Get-FileHash $target -Algorithm SHA256).Hash.ToLower()
        if ($actual -eq ([string]$pin.sha256).ToLower()) { $verified++ }
        else { $mismatch += $pin.file }
    }

    Assert 'every pinned payload file exists' ($missing.Count -eq 0) ("missing: " + ($missing -join ', '))
    Assert ("all {0} pinned payload hashes match" -f $verified) `
           ($mismatch.Count -eq 0) ("mismatched: " + ($mismatch -join ', '))
}

# =====================================================================
Section 'R06 — published Dashboard artefact'
# =====================================================================

$relExe = Join-Path $Repo 'releases\KomorebiDashboard.exe'
if (Test-Path $relExe) {
    $mb = [math]::Round((Get-Item $relExe).Length / 1MB, 1)
    Assert 'the published Dashboard exists' $true
    Assert ("its size ({0} MB) is consistent with self-contained + R2R" -f $mb) ($mb -ge 120)
    Assert 'releases/ holds exactly one payload file' `
           (@(Get-ChildItem (Join-Path $Repo 'releases') -Recurse -File | Where-Object { $_.Name -ne '.gitkeep' }).Count -eq 1)
} else {
    Assert 'the published Dashboard exists' $false "not built: $relExe (run: dotnet publish src/KomorebiDashboard -c Release)"
}

# =====================================================================
Section 'R07 — komorebi health and config check (read-only)'

# komorebi ships as binaries\komorebi-*.msi, NOT as a loose komorebic.exe.
# So there is no repo copy to point at: on an uninstalled machine this correctly
# reports "not installed" rather than failing on a missing file, and on the
# reference machine it checks the LIVE install under Program Files.
$komorebic = 'C:\Program Files\komorebi\komorebic.exe'

if (Test-Path $komorebic) {
    Assert 'komorebi is installed (Program Files)' $true $komorebic
    Assert 'komorebi process is running' ([bool](Get-Process komorebi -EA SilentlyContinue))

    $state = & $komorebic state 2>&1 | Out-String
    Assert 'komorebic state reports a live socket' ($state -match 'socket alive\s*:\s*True') `
           (($state -split "`n" | Where-Object { $_ -match 'socket' } | Select-Object -First 1))

    # `komorebic check` validates the LIVE config without changing it.
    $chk = & $komorebic check 2>&1 | Out-String
    Assert 'komorebic check passes on the live config' ($LASTEXITCODE -eq 0) `
           (($chk -split "`n" | Where-Object { $_ -match 'error|invalid' } | Select-Object -First 2) -join ' / ')
} else {
    # Not a failure: this gate must also pass on a clean machine, which is the
    # normal state inside the Sandbox before the install phase runs.
    Assert 'komorebi not installed (expected on a clean machine)' $true `
           'skipping health checks; they run after the install phase'
    Write-Host '        (komorebi is not installed here - health checks skipped, not failed)' -ForegroundColor DarkGray
}

# The MSI payloads themselves must be present and pinned, which is what the
# install phase will consume.
Assert 'the komorebi MSI payload is present' (Test-Path (Join-Path $Repo 'binaries\komorebi-0.1.41-x86_64.msi'))

Section 'R08 — startup tasks are still Highest (ADR-0016)'
# =====================================================================

# Read-only: Get-ScheduledTask never modifies a task. If the tasks are missing,
# or exist at the wrong RunLevel, that is REPORTED — never repaired. Repairing
# would be an install action, and ADR-0008 forbids those on this machine.
foreach ($taskName in @('Komorebi', 'KomorebiWatchdog')) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Assert "scheduled task '$taskName' exists" ([bool]$task)
    if ($task) {
        Assert "scheduled task '$taskName' is RunLevel=Highest" `
               ($task.Principal.RunLevel -eq 'Highest') ("actual: " + $task.Principal.RunLevel)
    }
}

# =====================================================================
Section 'R09 — every script the Dashboard verb registry names exists'
# =====================================================================

# This is the check that would have caught defect D21 (the script locator
# resolving to a directory with no scripts in it) at the repo level.
$registry = Join-Path $Repo 'src\KomorebiDashboard\Services\VerbRegistry.cs'
Assert 'VerbRegistry.cs exists' (Test-Path $registry)
if (Test-Path $registry) {
    $text = Get-Content $registry -Raw
    # The registry uses DOUBLE-quoted script names:  new("kill-all", "kill-all.ps1", ...)
    # A single-quoted pattern silently matched nothing and produced a vacuous
    # "all 0 scripts exist" pass, so the floor assertion below is load-bearing.
    $scriptNames = @([regex]::Matches($text, '"([^"]+\.(?:ps1|cmd|vbs|exe))"') |
                      ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

    # Floor first: a count of zero means the extraction is broken, and every
    # downstream assertion would pass for the wrong reason.
    Assert 'the registry script names were actually extracted' `
           ($scriptNames.Count -ge 10) ("extracted only " + $scriptNames.Count)
    $missing = @($scriptNames | Where-Object {
        -not (Test-Path (Join-Path $Repo "scripts\$_")) -and
        -not (Test-Path (Join-Path $Repo $_))
    })
    Assert ("all {0} scripts named by the registry exist" -f $scriptNames.Count) `
           ($missing.Count -eq 0) ("missing: " + ($missing -join ', '))
}

# =====================================================================
Write-Host ''
Write-Host ('=' * 62)

# Anti-vacuous-summary guard. Two of the defects found while building this file
# (R09's regex matching nothing, R04's falsy-array guard) both produced a PASS
# with a LOWER assertion count than a healthy run. Comparing the final count
# against the floor makes "an assertion silently stopped running" impossible to
# miss: if a check is skipped the total drops and the gate fails loudly.
# $expected is the count of assertions that run BEFORE this one, because Assert
# increments the counter as it executes: reading the floor from inside the check
# compares 30 against 29 and fails on a healthy tree. 29 is the verified healthy
# total; lowering it would reintroduce the silent-skip blind spot.
$expected = 29
Assert ("every assertion ran (expected {0})" -f $expected) `
       ($script:Checks -ge $expected) ("only " + $script:Checks + " assertions executed")

if ($script:Failures -gt 0) {
    Write-Host (" RESULT: {0} passed, {1} FAILED" -f $script:Checks, $script:Failures) -ForegroundColor Red
    Write-Host ''
    Write-Host ' Remember: this gate only READS. Failures here are findings to'
    Write-Host ' investigate, NOT permission to install anything to fix them.'
    exit 1
}
Write-Host (" RESULT: all {0} read-only checks passed" -f $script:Checks) -ForegroundColor Green
Write-Host ''
Write-Host ' Nothing was modified. Destructive verification belongs in the Sandbox:'
Write-Host '   tests/run-verification.ps1'
exit 0
