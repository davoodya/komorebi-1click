<#
.SYNOPSIS
    komorebi-1click - Windows Sandbox verification harness (tickets 01 + 02 + 03 + 04).

.DESCRIPTION
    Runs the full test suite (tests/sandbox-test-suite.ps1) inside Windows Sandbox on a
    disposable clean Win11 - exactly the tests ADR-0008 forbids on the production
    reference machine. The Sandbox is discarded when it closes, so nothing reaches the host.

    The procedure is deliberately hands-off so a coding agent with no UI access can
    drive it: the .wsb config maps the repo into the guest read-only and runs the suite
    at logon, so the whole test is one file plus one launch. The only manual step is
    pasting the output back to the agent.

.NOTES
    Requirements: Windows Sandbox must be enabled
    (Optional Features -> Windows Sandbox, or:
     Enable-WindowsOptionalFeature -FeatureName Containers-DisposableClientVM
     -All -Online).

    How to run (Davood):
      1) Double-click sandbox.wsb (or: & 'H:\Repo\komorebi-1click\sandbox.wsb')
      2) In the Sandbox window the suite runs automatically at logon. If it does not,
         run this one command:
           powershell -NoProfile -ExecutionPolicy Bypass -File C:\Repo\tests\sandbox-test-suite.ps1 -Repo C:\Repo
      3) Paste the output back.
      Closing the Sandbox discards everything.
#>

[CmdletBinding()]
param(
    # Repo root on the HOST. The Sandbox sees this as the C:\Repo mapped folder.
    [string] $HostRepo = 'H:\Repo\komorebi-1click'
)

$ErrorActionPreference = 'Stop'

#region --- sanity checks on the host -----------------------------------------
if (-not (Test-Path $HostRepo)) { throw "Repo not found: $HostRepo" }
if (-not (Test-Path "$HostRepo\Install.ps1")) { throw "Install.ps1 not found in $HostRepo" }
if (-not (Test-Path "$HostRepo\tests\sandbox-test-suite.ps1")) {
    throw "tests/sandbox-test-suite.ps1 not found in $HostRepo"
}

# Windows Sandbox availability (Get-WindowsOptionalFeature needs elevation on the host;
# the actual Sandbox check happens inside the guest, so this is only a convenience check).
$feature = Get-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM' -ErrorAction SilentlyContinue
if (-not $feature) {
    Write-Warning 'Cannot check the Sandbox feature without elevation. Run elevated to verify it, or launch sandbox.wsb directly.'
} elseif ($feature.State -ne 'Enabled') {
    throw "Windows Sandbox is not enabled (state: $($feature.State)). Enable it with: Enable-WindowsOptionalFeature -FeatureName Containers-DisposableClientVM -All -Online"
}
#endregion

#region --- launch the sandbox ------------------------------------------------
$wsb = "$HostRepo\sandbox.wsb"
if (-not (Test-Path $wsb)) { throw "sandbox.wsb not found at $wsb" }

Write-Host 'Launching Windows Sandbox...' -ForegroundColor Cyan
Write-Host ''
Write-Host 'When the Sandbox desktop appears, the suite runs automatically at logon.' -ForegroundColor White
Write-Host 'If it does not, run this ONE command in the Sandbox window:' -ForegroundColor White
Write-Host ''
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File C:\Repo\tests\sandbox-test-suite.ps1 -Repo C:\Repo" -ForegroundColor Yellow
Write-Host ''
Write-Host 'Then paste the output back. Closing the Sandbox discards everything.' -ForegroundColor DarkGray

Start-Process -FilePath $wsb -Wait
#endregion
