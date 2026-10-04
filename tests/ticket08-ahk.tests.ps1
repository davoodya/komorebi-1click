#Requires -Version 5.1
<#
    Ticket 08 — AutoHotkey lifecycle management.

    These tests exercise the enable/disable machinery against a SANDBOX copy
    of the repo, never the live machine. A sandbox is a throwaway directory
    with a copy of autohotkey\ and scripts\, so the real Startup folder and
    the real state file are never touched.

    Run:
      powershell -ExecutionPolicy Bypass -File tests/ticket08-ahk.tests.ps1 -Sandbox <dir>
#>

[CmdletBinding()]
param(
    [string] $Sandbox = (Join-Path $env:TEMP 'komorebi-1click-ticket08-test')
)

$ErrorActionPreference = 'Stop'

$here = Split-Path $MyInvocation.MyCommand.Path -Parent
$repo = Split-Path $here -Parent

. (Join-Path $repo 'scripts\Install-Common.ps1')

# ---------------------------------------------------------------------------
# A minimal sandbox: a copy of the repo's autohotkey\ + scripts\ trees in a
# throwaway directory, so the tests can write ahk-state.json and regenerate
# the VBS without ever touching the live repository or the real Startup
# folder.
# ---------------------------------------------------------------------------
function New-Sandbox {
    param([string]$Path)

    if (Test-Path $Path) { Remove-Item $Path -Recurse -Force }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null

    Copy-Item (Join-Path $repo 'autohotkey') (Join-Path $Path 'autohotkey') -Recurse -Force
    Copy-Item (Join-Path $repo 'scripts')    (Join-Path $Path 'scripts')    -Recurse -Force

    return $Path
}

# ---------------------------------------------------------------------------
# A tiny assertion helper. Prints PASS/FAIL and counts.
# ---------------------------------------------------------------------------
$script:passed = 0
$script:failed = 0

function Assert {
    param([string]$Label, $Condition)
    if ($Condition) {
        Write-Host ("  PASS  {0}" -f $Label) -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host ("  FAIL  {0}" -f $Label) -ForegroundColor Red
        $script:failed++
    }
}

# ===========================================================================
Write-Host ''
Write-Host '=== ticket 08: AutoHotkey lifecycle ===' -ForegroundColor Cyan

$sb = New-Sandbox -Path $Sandbox
$ahkDir = Join-Path $sb 'autohotkey'
$template = Join-Path $ahkDir 'AppRunner.vbs'
$outVbs = Join-Path $sb 'AppRunner.vbs'      # sandbox output, not the real Startup

Write-Host ''
Write-Host '--- 1. the state file defaults every script to enabled ---'
$state = Get-AhkEnabledState -RepoRoot $sb
Assert 'three scripts are known' ($state.Count -eq 3)
Assert 'autocorrect defaults to enabled'  ([bool]$state['autocorrect'])
Assert 'ChangeLangF3 defaults to enabled' ([bool]$state['ChangeLangF3'])
Assert 'NewFile defaults to enabled'      ([bool]$state['NewFile'])

Write-Host ''
Write-Host '--- 2. a disabled script renders as a commented-out VBS line ---'
# Flip one script off directly through the generator, via the manifest.
Apply-AhkEnabledState -RepoRoot $sb
for ($i = 0; $i -lt $script:AutoHotkeyScripts.Count; $i++) {
    if ($script:AutoHotkeyScripts[$i].Name -ieq 'NewFile') {
        $script:AutoHotkeyScripts[$i]['Enabled'] = $false
    }
}
New-AppRunnerVbs -TemplatePath $template -OutputPath $outVbs -AhkDir $ahkDir
$generated = Get-Content -LiteralPath $outVbs

$runNewFile  = @($generated | Where-Object { $_ -like '*NewFile.ahk*' -and $_ -notlike "'*" })
$disabledLine = @($generated | Where-Object { $_ -like "'*NewFile.ahk*" })

Assert 'NewFile is NOT emitted as a live RunHidden line' ($runNewFile.Count -eq 0)
Assert 'NewFile IS emitted as a commented-out line'       ($disabledLine.Count -eq 1)
Assert 'the disabled line carries the [disabled:NewFile] marker' (
    $disabledLine[0] -match '\[disabled:NewFile\]')
Assert 'the other two scripts are still live' (
    (@($generated | Where-Object { $_ -like 'RunHidden*autocorrect.ahk*' }).Count -eq 1) -and
    (@($generated | Where-Object { $_ -like 'RunHidden*ChangeLangF3.ahk*' }).Count -eq 1))

Write-Host ''
Write-Host '--- 3. Set-AhkEnabledState persists and regenerates together ---'
$state['autocorrect'] = $false
Set-AhkEnabledState -RepoRoot $sb -State $state -StartupDirOverride $sb

$stateFile = Join-Path $ahkDir 'ahk-state.json'
Assert 'ahk-state.json was written' (Test-Path -LiteralPath $stateFile)

# Set-AhkEnabledState regenerates into the REAL Startup folder. That is the
# wrong place for a sandbox test, so verify the persistence round-trip
# instead and regenerate into the sandbox explicitly.
$reloaded = Get-AhkEnabledState -RepoRoot $sb
Assert 'autocorrect stayed disabled after a reload' (-not [bool]$reloaded['autocorrect'])
Assert 'NewFile came back enabled (state file did not exist when it flipped)' (
    [bool]$reloaded['NewFile'])

Write-Host ''
Write-Host '--- 4. re-rendering from the persisted state keeps autocorrect off ---'
Apply-AhkEnabledState -RepoRoot $sb
New-AppRunnerVbs -TemplatePath $template -OutputPath $outVbs -AhkDir $ahkDir
$generated = Get-Content -LiteralPath $outVbs
Assert 'autocorrect is commented out after the round-trip' (
    (@($generated | Where-Object { $_ -like "'*autocorrect.ahk*" }).Count -eq 1))

Write-Host ''
Write-Host '--- 5. a corrupt state file degrades to defaults, never crashes ---'
Set-Content -LiteralPath $stateFile -Value 'this is not json{{' -Encoding UTF8
try {
    $corrupt = Get-AhkEnabledState -RepoRoot $sb
    Assert 'a corrupt state file returns the defaults' ($corrupt.Count -eq 3)
    Assert 'everything is enabled under a corrupt state file' (
        (-not [bool]$corrupt['autocorrect']) -eq $false)
} catch {
    Assert 'a corrupt state file did not throw' $false
}

Write-Host ''
Write-Host '--- 6. the new scripts are path-portable ---'
# No source-machine path may be baked into any shipped script. The repo
# directory changes per machine, so a literal path makes the script unusable.
$bad = @()
foreach ($f in 'ahk-toggle.ps1','ahk-script.ps1','ahk-cleanup.ps1','ahk-uninstall.ps1') {
    $src = Get-Content (Join-Path $repo "scripts\$f") -Raw
    if ($src -match 'H:\\Repo|C:\\Users\\DavoodYa|F:\\Backups') { $bad += $f }
}
Assert 'no shipped AHK script contains a source-machine path' ($bad.Count -eq 0)
if ($bad.Count) { Write-Host ("    offenders: $($bad -join ', ')") -ForegroundColor Red }

Write-Host ''
Write-Host '--- 7. the management scripts parse cleanly ---'
$parseBad = @()
foreach ($f in 'ahk-toggle.ps1','ahk-script.ps1','ahk-cleanup.ps1','ahk-uninstall.ps1') {
    $p = Join-Path $repo "scripts\$f"
    $tokens = $null; $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$tokens, [ref]$errs) | Out-Null
    if ($errs.Count -gt 0) { $parseBad += $f }
}
Assert 'all four new scripts parse without errors' ($parseBad.Count -eq 0)

Write-Host ''
Write-Host '--- 8. cleanup removes the leftovers ---'
# Run the SANDBOX COPY of the cleanup script, not the real one. The script
# derives its own repo root from $MyInvocation.MyCommand.Path, so invoking the
# copy under the sandbox makes every path it touches (the state file, the
# process match) resolve inside the sandbox and leaves the real machine alone.
$sandboxCleanup = Join-Path $sb 'scripts\ahk-cleanup.ps1'
& $sandboxCleanup -StartupDirOverride $sb | Out-Null
Assert 'ahk-cleanup removed ahk-state.json' (-not (Test-Path -LiteralPath $stateFile))

# ===========================================================================
Write-Host ''
if ($script:failed -eq 0) {
    Write-Host ("PASS  ticket 08: all {0} assertions green" -f $script:passed) -ForegroundColor Green
    exit 0
}
Write-Host ("FAIL  ticket 08: {0} assertion(s) failed of {1}" -f $script:failed, ($script:passed + $script:failed)) -ForegroundColor Red
exit 1
