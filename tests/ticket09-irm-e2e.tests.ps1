# Ticket 09 E2E - entry point 3: `irm | iex`.
#
# The two on-disk entry points (the EXE and `.\\Install.ps1`) are covered by
# tests/ticket09-exe-wrapper.tests.ps1. The third one is special: irm fetches
# the script CONTENT and iex (Invoke-Expression) runs that text in the current
# session with NO file behind it - which is exactly the in-memory case that
# made the installer die on its first Join-Path before the bootstrap existed.
#
# This file reproduces that faithfully: the installer's text is piped into
# Invoke-Expression inside a CHILD pwsh (that child is the "shell" the user's
# irm|iex ran in), with KOMOREBI_1CLICK_ROOT pointing at a sandbox whose
# Install.ps1 is a RECORDING STUB (embedded below). No real installer logic
# runs, so the live machine is untouched - the same stub pattern the wrapper
# suite uses for the EXE.
#
# Control-flow note: the bootstrap's handover ends with `exit $LASTEXITCODE`,
# which terminates the session iex ran in - exactly what a real irm|iex user
# session experiences. So the stub exits with a sentinel code (7) and the
# assertions here verify that sentinel arrived, instead of pretending the
# driver continues past the handover. Exit 0 = all checks passed.

$ErrorActionPreference = 'Stop'
Set-Location 'H:\Repo\komorebi-1click'

$fail = 0
function Check($name, $ok) {
    if ($ok) { Write-Host ("  PASS  {0}" -f $name) -ForegroundColor Green }
    else { Write-Host ("  FAIL  {0}" -f $name) -ForegroundColor Red; $script:fail++ }
}

$sandbox = Join-Path $env:TEMP 'k1c-irm-sandbox'
if (Test-Path $sandbox) { Remove-Item $sandbox -Recurse -Force }
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

$record = Join-Path $sandbox 'handover-record.txt'
$stub = @'
param([switch]$DryRun, [switch]$SkipElevationCheck)
$rec = "repo={0} dryrun={1} skip={2}" -f (Split-Path -Parent $MyInvocation.MyCommand.Path), $PSBoundParameters.ContainsKey('DryRun'), $PSBoundParameters.ContainsKey('SkipElevationCheck')
Set-Content -LiteralPath '__RECORD_PATH__' -Value $rec -Encoding ascii
exit 7
'@
$stub = $stub.Replace('__RECORD_PATH__', $record)
Set-Content -LiteralPath (Join-Path $sandbox 'Install.ps1') -Value $stub -Encoding UTF8

# The child "user shell": reads the installer text and pipes it into
# Invoke-Expression, iex-style, then reports how the session ended.
$childScript = @"
`$ErrorActionPreference = 'Stop'
`$installPs1 = Get-Content -LiteralPath 'H:\Repo\komorebi-1click\Install.ps1' -Raw
try { `$installPs1 | Invoke-Expression } catch { Write-Host ('EXCEPTION: {0}' -f `$_.Exception.Message) }
Write-Host ('SESSION-ENDED code={0}' -f `$LASTEXITCODE)
"@
$childFile = Join-Path $sandbox 'child.ps1'
Set-Content -LiteralPath $childFile -Value $childScript -Encoding UTF8

$pwshExe = (Get-Process -Id $PID).Path

Write-Host '== 1. in-memory run (irm | iex) with the local-repo override ==' -ForegroundColor Cyan
$env:KOMOREBI_1CLICK_ROOT = $sandbox
$out = & $pwshExe -NoProfile -ExecutionPolicy Bypass -File $childFile 2>&1
$childExit = $LASTEXITCODE
$env:KOMOREBI_1CLICK_ROOT = $null
$text = ($out | Out-String)
Write-Host ("    {0}" -f (($text -split "`n" | Where-Object { $_ -match 'handing over|SESSION-ENDED|EXCEPTION' }) -join ' | ')) -ForegroundColor DarkGray
Check 'the bootstrap detected the in-memory case and handed over' ($text -match 'handing over')
Check 'the override was honoured (no archive download attempted)' ($text -notmatch 'bootstrap\] fetching')
Check 'no exception left the bootstrap' ($text -notmatch 'EXCEPTION')
Check 'the session ended with the stub sentinel exit (7), not an error' ($childExit -eq 7)
Check 'the handover actually ran the sandbox Install.ps1' (Test-Path -LiteralPath $record)
if (Test-Path -LiteralPath $record) {
    $rec = (Get-Content -LiteralPath $record -Raw).Trim()
    Write-Host "    stub record: $rec" -ForegroundColor DarkGray
    Check 'the handover ran from the override repo' ($rec -match [regex]::Escape($sandbox))
} else {
    Check 'the handover ran from the override repo' $false
}

Write-Host '== 2. without the override the release-URL branch attempts the fetch ==' -ForegroundColor Cyan
if (Test-Path $record) { Remove-Item $record -Force }
# The URL points at a directory that has no release zip, so the fetch must
# fail - we only assert the branch TRIES (the message prints before the fetch
# is attempted). No network is contacted and no install can start.
$env:KOMOREBI_1CLICK_URL = 'file:///C|/Windows/Temp'
$out2 = & $pwshExe -NoProfile -ExecutionPolicy Bypass -File $childFile 2>&1
$env:KOMOREBI_1CLICK_URL = $null
$text2 = ($out2 | Out-String)
Check 'the default branch tries to fetch the release archive' ($text2 -match 'bootstrap\] fetching')
($text2 -split "`n" | Where-Object { $_ -match 'fetching|EXCEPTION|Unable' } | Select-Object -First 2) | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

Write-Host ''
Write-Host ("TICKET09 IRM E2E: {0}" -f $(if ($fail -eq 0) { 'ALL PASSED' } else { "$fail FAILURE(S)" })) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($fail -eq 0) { 0 } else { 1 })
