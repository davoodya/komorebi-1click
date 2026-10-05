#Requires -Version 5.1
<#
=============================================================================================
komorebi-1click — SANDBOX BOOTSTRAP (runs INSIDE Windows Sandbox)

Launched automatically by the LogonCommand in the generated .wsb. Its only job is
to run the destructive suite and leave a report in the mapped repo folder, which is
the only channel back to the host.

It is deliberately separate from sandbox-verify-install.ps1 so the bootstrap stays
tiny: if the suite hangs or crashes, this file is still readable from inside the
sandbox and says which step died.

The results land at  <repo>\test-results\verification-result.{json,txt}
=============================================================================================
#>

$ErrorActionPreference = 'Continue'

$Repo  = 'C:\komorebi-src'
$Suite = Join-Path $Repo 'tests\sandbox-verify-install.ps1'
$Stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')

# Roll previous runs aside instead of overwriting: a failing run and the run
# before it are both worth keeping, and the plain path always holds the newest.
$ResultDir = Join-Path $Repo 'test-results'
if (-not (Test-Path $ResultDir)) { New-Item -ItemType Directory -Path $ResultDir -Force | Out-Null }

Write-Host ''
Write-Host '=======================================================' -ForegroundColor Cyan
Write-Host ' komorebi-1click — sandbox bootstrap' -ForegroundColor Cyan
Write-Host '=======================================================' -ForegroundColor Cyan
Write-Host (" repo:  {0}" -f $Repo)
Write-Host (" suite: {0}" -f $Suite)
Write-Host (" time:  {0}" -f (Get-Date))
Write-Host ''

# Write the positive marker the suite's guard requires.
#
# This is the signal that cannot be spoofed: it exists only if THIS bootstrap ran,
# which only happens as the LogonCommand of a generated .wsb. Detecting the sandbox
# by the presence of WindowsSandbox.exe was wrong -- that file is also on the host
# whenever the optional feature is merely installed, and that mistake let the
# suite run the installer against the reference machine.
$Marker = Join-Path $Repo 'test-results\.sandbox-marker'
$ResultDir0 = Join-Path $Repo 'test-results'
if (-not (Test-Path $ResultDir0)) { New-Item -ItemType Directory -Path $ResultDir0 -Force | Out-Null }
@{
    marker   = 'komorebi-1click sandbox'
    written  = (Get-Date).ToUniversalTime().ToString('o')
    computer = $env:COMPUTERNAME
    user     = $env:USERNAME
} | ConvertTo-Json | Set-Content -Path $Marker -Encoding UTF8
Write-Host "Wrote sandbox marker: $Marker" -ForegroundColor DarkGray

if (-not (Test-Path $Suite)) {
    Write-Host "The suite is missing: $Suite" -ForegroundColor Red
    Write-Host 'The repo did not mount at C:\komorebi-src. Check the .wsb HostFolder.' -ForegroundColor Red
    exit 2
}

# Announce on the sandbox console so it is obvious the run started.
Write-Host 'Starting the destructive verification suite...' -ForegroundColor Yellow
Write-Host 'This installs and uninstalls software INSIDE the sandbox.' -ForegroundColor Yellow
Write-Host ''

$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $Suite -Repo $Repo -LogDir $ResultDir -ContinueOnFailure
$suiteRc = $LASTEXITCODE
$sw.Stop()

Write-Host ''
Write-Host ("Suite finished in {0}s (exit {1})" -f [math]::Round($sw.Elapsed.TotalSeconds, 1), $suiteRc)

# --- archive this run, then make it the current one -------------------------------
$json = Join-Path $ResultDir 'verification-result.json'
$txt  = Join-Path $ResultDir 'verification-result.txt'

if (Test-Path $json) {
    foreach ($pair in @(@($json, 'json'), @($txt, 'txt'))) {
        $src = $pair[0]; $ext = $pair[1]
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $ResultDir "verification-result.$Stamp.$ext") -Force
        }
    }
    Write-Host "Report archived as verification-result.$Stamp.{json,txt}" -ForegroundColor Cyan
    Write-Host "Current report: $ResultDir" -ForegroundColor Cyan
} else {
    # No report at all means the suite died before Save-Report. Say so on the
    # console too, otherwise the host is left guessing whether it never ran.
    Write-Host ''
    Write-Host 'NO REPORT WAS WRITTEN — the suite failed before it could save.' -ForegroundColor Red
    @{
        error      = 'sandbox-bootstrap: no report produced'
        repo       = $Repo
        exitCode   = $suiteRc
        durationSec= [math]::Round($sw.Elapsed.TotalSeconds, 1)
        timestamp  = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json | Set-Content (Join-Path $ResultDir 'bootstrap-failure.json') -Encoding UTF8
}

Write-Host ''
Write-Host 'You can close this sandbox window now — everything it wrote is already gone.' -ForegroundColor Cyan
Write-Host 'Press Enter to close automatically.'
$null = Read-Host