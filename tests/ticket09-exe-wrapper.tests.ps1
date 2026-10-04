#Requires -Version 5.1
<#
    Ticket 09 — EXE install wrapper + irm install path.

    WHY THESE TESTS EXIST
      Three entry points must reach the SAME installed end state:
        1. double-clicking a single small EXE,
        2. running Install.ps1 directly,
        3. `irm <url>/install.ps1 | iex`.

      The EXE is a THIN wrapper (ADR-0004): its only jobs are to locate
      Install.ps1 next to itself, relaunch elevated when it is not already
      elevated (the MSIs need Admin), run the installer, and forward the exit
      code. Every real decision stays in Install.ps1, so the wrapper rarely
      changes and can never disagree with the .ps1 path.

      Two historical defects make several of these assertions load-bearing:

      * The wrapper originally SWALLOWED the installer's exit code. An install
        that failed with exit 10 ("usable but incomplete") reported success to
        whoever double-clicked it. `install.exitcode` is forwarded verbatim.

      * `irm | iex` runs the script from memory, so $PSScriptRoot is EMPTY. The
        original bootstrap took RepoRoot straight from $PSScriptRoot, which
        silently resolved to nothing and the installer died on the first
        Join-Path. The bootstrap now has an explicit in-memory branch that
        fetches the repository archive and re-execs the real Install.ps1.

      The EXE is genuinely compiled here with csc.exe, because building a
      wrapper is not an install: it touches no process, no task and no
      registry. Only the *build* runs; the installer is never launched.

    Run:
      powershell -ExecutionPolicy Bypass -File tests/ticket09-exe-wrapper.tests.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$here = Split-Path $MyInvocation.MyCommand.Path -Parent
$repo = Split-Path $here -Parent

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

$csPath   = Join-Path $repo 'scripts\komorebi-install.cs'
$buildPs1 = Join-Path $repo 'scripts\build-exe.ps1'
$instPs1  = Join-Path $repo 'Install.ps1'
$csc      = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'

# ---------------------------------------------------------------------------
# The C# wrapper source and its build script exist
# ---------------------------------------------------------------------------
Assert 'wrapper source scripts\komorebi-install.cs exists'      (Test-Path $csPath)
Assert 'build script scripts\build-exe.ps1 exists'              (Test-Path $buildPs1)
Assert 'Install.ps1 exists'                                     (Test-Path $instPs1)

$src = if (Test-Path $csPath) { Get-Content -LiteralPath $csPath -Raw } else { '' }

# ---------------------------------------------------------------------------
# The wrapper does the four things ADR-0004 says it does
# ---------------------------------------------------------------------------
Assert 'locates Install.ps1 next to itself'      ($src -match 'Install\.ps1')
Assert 'relaunches elevated via "runas"'         ($src -match '"runas"')
Assert 'runs with -NoProfile'                    ($src -match '-NoProfile')
Assert 'runs with -ExecutionPolicy Bypass'       ($src -match '-ExecutionPolicy Bypass')
Assert 'passes -File for the installer script'   ($src -match '-File')
Assert 'forwards the child exit code'            ($src -match 'ExitCode')
Assert 'passes -SkipElevationCheck (it already elevated)' ($src -match '-SkipElevationCheck')

# ---------------------------------------------------------------------------
# It is a THIN wrapper: no installer logic leaked into C#.
# A wrapper that grew payload verification or MSI logic would drift from the
# .ps1 path, which is exactly what ADR-0004 forbids.
# ---------------------------------------------------------------------------
Assert 'no payload/SHA logic in the wrapper'  ($src -notmatch 'SHA256|payloads\.sha256')
Assert 'no MSI logic in the wrapper'          ($src -notmatch 'msiexec')
Assert 'no config-generation logic in wrapper' ($src -notmatch 'komorebi\.json|whkdrc')

# ---------------------------------------------------------------------------
# ADR-0004 rejected ps2exe and Inno Setup. A ps2exe-built binary would be a
# DIFFERENT artifact with different elevation behaviour, so the BUILD step must
# not reference either. Scoped to the build inputs on purpose: the ADRs and the
# docs legitimately *discuss* ps2exe and Inno by name when recording why they
# were rejected, and grepping the whole tree would flag those as failures.
# ---------------------------------------------------------------------------
$buildInputs = @()
foreach ($p in @($csPath, $buildPs1)) {
    if (Test-Path $p) { $buildInputs += (Get-Content -LiteralPath $p -Raw) }
}
$buildText = $buildInputs -join "`n"

# The source and the build script both *document* these rejections in prose (the
# build script's header explains why ps2exe and Inno were refused), so a naive
# whole-text grep flags the explanation as if it were a use. What matters is
# whether anything is EXECUTED, not whether the name is mentioned.
#
# Comments are stripped in two passes, and both are needed. Dropping only lines
# that START with '#' is not enough: a PowerShell <# ... #> block comment has
# continuation lines that begin with prose, not '#', so "ps2exe and Inno Setup
# were both rejected..." survived and still matched. The block form is removed
# first, then the line forms.
# The PowerShell -replace operator is used rather than the static
# [regex]::Replace because only the instance form takes two arguments; the
# static class form needs three and fails overload resolution here. The (?s)
# flag lets the pattern span newlines, which a block comment requires.
$blockless = $buildText -replace '(?s)<#.*?#>', ''
$codeOnly = ($blockless -split "`r?`n" |
             ForEach-Object { ($_ -replace '//.*$', '') -replace '^\s*#.*$', '' }) -join "`n"

Assert 'the build step does not invoke ps2exe'    ($codeOnly -notmatch 'ps2exe')
Assert 'the build step does not invoke Inno'      ($codeOnly -notmatch 'Inno')
Assert 'the build step compiles with csc.exe'     ($codeOnly -match 'csc\.exe')

# ---------------------------------------------------------------------------
# It really compiles. This is the assertion that would catch a wrapper that
# looks right and does not build.
# ---------------------------------------------------------------------------
Assert 'csc.exe is present on this machine' (Test-Path $csc)

$builtExe = Join-Path $env:TEMP 'komorebi-install-wrapper-test.exe'
$buildOut = ''
if (Test-Path $csc) {
    if (Test-Path $builtExe) { Remove-Item $builtExe -Force -ErrorAction SilentlyContinue }
    $buildOut = (& $csc /nologo /target:winexe /optimize+ '/reference:System.Windows.Forms.dll' "/out:$builtExe" $csPath 2>&1) -join "`n"
}
Assert 'csc.exe compiles the wrapper with no errors' (
    (Test-Path $builtExe) -and ($LASTEXITCODE -eq 0) -and ($buildOut -notmatch 'error CS')
)

if (Test-Path $builtExe) {
    # A GUI-subsystem binary has PE subsystem == 2. A console build would flash
    # a window every time the user double-clicks it.
    $bytes = [System.IO.File]::ReadAllBytes($builtExe)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    $subsystem = [BitConverter]::ToUInt16($bytes, $peOffset + 0x5c)
    Assert 'wrapper is GUI-subsystem (no console flash)' ($subsystem -eq 2)
    Assert 'wrapper is a real PE binary'                 ($bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A)
    Assert 'wrapper is small (under 100 KB)'              ($bytes.Length -lt 100KB)
}

# ---------------------------------------------------------------------------
# Install.ps1 must still work STANDALONE (entry point 2)
# ---------------------------------------------------------------------------
$inst = Get-Content -LiteralPath $instPs1 -Raw
Assert 'Install.ps1 exposes -SkipElevationCheck' ($inst -match '\$SkipElevationCheck')
Assert 'Install.ps1 still holds the real logic'   ($inst -match 'Test-PayloadIntegrity')

# ---------------------------------------------------------------------------
# irm | iex (entry point 3). $PSScriptRoot is empty under `iex`, so the
# bootstrap must detect that and fetch the repo instead.
# ---------------------------------------------------------------------------
Assert 'Install.ps1 detects the in-memory (iex) case' ($inst -match '\$PSScriptRoot')
Assert 'Install.ps1 has a bootstrap branch for irm|iex' (
    $inst -match 'KOMOREBI_1CLICK_ROOT|KOMOREBI_1CLICK_URL|Invoke-RestMethod|Invoke-WebRequest'
)
$usesCwdAsRepo = ($inst -match '\$RepoRoot\s*=\s*\(Get-Location\)') -or ($inst -match '\$RepoRoot\s*=\s*\$PWD')
Assert 'Install.ps1 never uses the CWD as the repo root' (-not $usesCwdAsRepo)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ''
$summaryColour = if ($script:failed) { 'Red' } else { 'Green' }
Write-Host ('  passed: {0}   failed: {1}' -f $script:passed, $script:failed) -ForegroundColor $summaryColour

if ($script:failed) {
    Write-Host '  TICKET 09: SOME CHECKS FAILED' -ForegroundColor Red
    exit 1
}
Write-Host '  ticket 09: all checks green' -ForegroundColor Green
exit 0
