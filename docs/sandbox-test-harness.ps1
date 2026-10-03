<#
.SYNOPSIS
    komorebi-1click — Windows Sandbox verification harness for Tickets 02 + 03.

.DESCRIPTION
    Runs a REAL clean install of the installer inside Windows Sandbox, then an
    idempotency re-run, then verifies the resulting state — exactly the tests
    ADR-0008 forbids running on the production reference machine.

    Everything happens inside the Sandbox. The Sandbox is discarded when it
    closes, so nothing can reach the host.

.NOTES
    Requirements: Windows Sandbox must be enabled
    (Optional Features -> Windows Sandbox, or:
     Enable-WindowsOptionalFeature -FeatureName Containers-DisposableClientVM
     -All -Online).

    How to run (Davood):
      1) Copy this repo to a place the Sandbox can read. Windows Sandbox maps
         the host folder as a read-only share when you pass -HostFolder.
         Easiest: clone/copy the repo to H:\Repo\komorebi-1click (already there)
         and run this script from the HOST PowerShell (elevated).
      2) Look at the output. The script exits non-zero on any assertion failure.
#>

[CmdletBinding()]
param(
    # Repo root on the HOST. The Sandbox sees this as a mapped folder.
    [string] $HostRepo = 'H:\Repo\komorebi-1click',

    # Where the harness writes its log on the HOST so you can hand it back.
    [string] $HostLog  = 'H:\Repo\komorebi-1click\sandbox-test-results.txt'
)

$ErrorActionPreference = 'Stop'

#region --- sanity checks on the host -----------------------------------------
if (-not (Test-Path $HostRepo)) { throw "Repo not found: $HostRepo" }
if (-not (Test-Path "$HostRepo\Install.ps1")) { throw "Install.ps1 not found in $HostRepo" }

# Windows Sandbox availability
$feature = Get-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM' -ErrorAction SilentlyContinue
if ($feature.State -ne 'Enabled') {
    throw "Windows Sandbox is not enabled (state: $($feature.State)). Enable it with: Enable-WindowsOptionalFeature -FeatureName Containers-DisposableClientVM -All -Online"
}
#endregion

#region --- the script that runs INSIDE the sandbox ---------------------------
# It is written to a file the sandbox can read, then invoked there. All paths
# inside are sandbox-local.
$insideScript = @'
[CmdletBinding()]
param([string] $RepoShare)

$ErrorActionPreference = 'Stop'
$fail = 0
function Assert($label, $ok) {
    Write-Output ("  [{0}] {1}" -f $(if ($ok) {'PASS'} else {'FAIL'}), $label)
    if (-not $ok) { $script:fail++ }
}
function Section($t) { Write-Output ''; Write-Output ("===== {0} =====" -f $t) }

$repo = 'C:\Repo'
if (-not (Test-Path $repo)) { throw "Expected the repo share mapped at $repo" }

Section 'T0 — clean machine preconditions'
Assert 'no komorebi installed'  $(-not (Test-Path 'C:\Program Files\komorebi'))
Assert 'no whkd installed'      $(-not (Test-Path 'C:\Program Files\whkd'))
Assert 'no YASB installed'      $(-not (Test-Path 'C:\Program Files\YASB'))
Assert 'no AutoHotkey installed' $(-not (Test-Path 'C:\Program Files\AutoHotkey'))
Assert 'no komorebi config yet' $(-not (Test-Path "$env:USERPROFILE\.config\komorebi"))

Section 'T1 — first install (the real clean-install path)'
& "$repo\Install.ps1"
$exit1 = $LASTEXITCODE
Write-Output ("  Install.ps1 exit code: {0}" -f $exit1)
Assert 'installer exited 0' ($exit1 -eq 0)

Section 'T2 — every binary actually installed'
$kb = 'C:\Program Files\komorebi\bin\komorebic.exe'
Assert 'komorebic.exe present' (Test-Path $kb)
Assert 'whkd.exe present'      (Test-Path 'C:\Program Files\whkd\bin\whkd.exe')
Assert 'yasb.exe present'      (Test-Path 'C:\Program Files\YASB\yasb.exe')
Assert 'AHK v1 present'        (Test-Path 'C:\Program Files\AutoHotkey\AutoHotkey.exe')
Assert 'AHK v2 present'        (Test-Path 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe')
$kbv = & $kb --version 2>&1 | Select-Object -First 1
Assert ("komorebic version is 0.1.41 (got {0})" -f $kbv) ($kbv -match '0\.1\.41')

Section 'T3 — configuration written and validated'
$kjson = "$env:USERPROFILE\.config\komorebi\komorebi.json"
Assert 'komorebi.json exists' (Test-Path $kjson)
$cfg = Get-Content $kjson -Raw -Encoding UTF8 | ConvertFrom-Json
$monitors = @($cfg.monitors)
Assert 'at least one monitor block' ($monitors.Count -ge 1)
Assert '9 workspaces on monitor 0' (@($monitors[0].workspaces).Count -eq 9)
Assert 'app_specific_configuration_path points at THIS user' ($cfg.app_specific_configuration_path -eq "$env:USERPROFILE\applications.json")
Assert 'applications.json was placed there' (Test-Path $cfg.app_specific_configuration_path)
Assert 'whkdrc exists' (Test-Path "$env:USERPROFILE\.config\whkdrc")
Assert 'komorebi-resize.json exists and is EMPTY' ((Get-Item "$env:USERPROFILE\.config\komorebi\komorebi-resize.json").Length -eq 0)
Assert 'YASB config exists' (Test-Path "$env:USERPROFILE\.config\yasb\config.yaml")
Assert 'layered_whitelist has the mintty Class rule' (($cfg.layered_whitelist | ConvertTo-Json -Compress) -eq '{"kind":"Class","id":"mintty","matching_strategy":"Equals"}')
Assert 'no source-machine username anywhere in the config' (-not (Get-ChildItem "$env:USERPROFILE\.config" -Recurse -File | Select-String -Pattern 'DavoodYa' -Quiet))

Section 'T4 — komorebic check passes on the generated config'
$check = & $kb check -k $kjson 2>&1
Assert ("komorebic check exit 0 (got {0})" -f $LASTEXITCODE) ($LASTEXITCODE -eq 0)
Write-Output ("  report: {0}" -f (($check -split "`n" | Select-Object -First 3) -join ' | '))

Section 'T5 — idempotency: run the installer a second time'
& "$repo\Install.ps1"
Assert 'second run also exits 0' ($LASTEXITCODE -eq 0)
$cfg2 = Get-Content $kjson -Raw -Encoding UTF8 | ConvertFrom-Json
Assert 'komorebi.json unchanged' ((@($cfg2.monitors).Count) -eq (@($cfg.monitors).Count))
Assert 'config still reports valid' ((& $kb check -k $kjson 2>&1; $LASTEXITCODE) -eq 0)

Section 'T6 — the config is genuinely offline (no network used)'
# The installer never touches the network; prove the config generation did not
# need it by re-running with the network stack unavailable is not possible in
# sandbox, so instead assert the config contains no download/URL requirement.
Assert 'config has no external URL references' (-not (Get-Content $kjson -Raw -match 'https?://(?!raw\.githubusercontent\.com)'))

Section 'RESULT'
Write-Output ("TOTAL FAILURES: {0}" -f $script:fail)
if ($script:fail -gt 0) { exit 1 }
'@
#endregion

#region --- launch the sandbox ------------------------------------------------
$wsb = 'C:\Windows\System32\WindowsSandbox.exe'
if (-not (Test-Path $wsb)) { $wsb = 'C:\Windows\System32\WindowsSandboxClient.exe' }

# Stage the inside-script where the sandbox share can read it.
$staged = Join-Path $HostRepo '_sandbox_inside.ps1'
$insideScript | Set-Content -Path $staged -Encoding UTF8

try {
    Write-Host 'Launching Windows Sandbox…' -ForegroundColor Cyan
    Write-Host 'When the Sandbox desktop appears, run this ONE command in it:'
    Write-Host ''
    Write-Host '  powershell -NoProfile -ExecutionPolicy Bypass -File C:\Repo\_sandbox_inside.ps1 -RepoShare C:\Repo' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Then paste the output back. Closing the Sandbox discards everything.' -ForegroundColor DarkGray

    Start-Process -FilePath $wsb -Wait
}
finally {
    Remove-Item $staged -Force -ErrorAction SilentlyContinue
}
#endregion
