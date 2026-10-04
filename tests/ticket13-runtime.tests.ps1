#Requires -Version 5.1
<#
.SYNOPSIS
    Ticket 13 runtime proof: the published EXE really is one self-contained file.

.DESCRIPTION
    tests/ticket13-publish.tests.ps1 checks the FLAGS. This checks the
    ARTEFACT, which is the part that actually ships.

    WHY THIS CANNOT BE MERGED INTO THE FLAG SUITE
      A framework-dependent build would pass every flag assertion if someone
      set SelfContained=true but the runtime packs failed to resolve, and it
      would launch perfectly on THIS machine because the .NET 8 SDK is
      installed. So "it starts here" proves nothing about self-containment.

      These assertions read the binary instead:
        * the runtime packs are embedded (Microsoft.NETCore.App AND
          Microsoft.WindowsDesktop.App) — a framework-dependent build has
          neither;
        * no DLL or satellite folder sits beside it, so the machine has
          nothing to supply;
        * the R2R native-code marker is present, which is the precompiled-start
          claim ADR-0015 makes;
        * it still launches and opens a window, because a bundle that cannot
          resolve its own payload is self-contained in name only.

    IT DOES NOT STOP KOMOREBI, WHKD OR YASB. It launches the published app,
    reads the file, and terminates only the process it started itself.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$Repo    = 'H:\Repo\komorebi-1click'
$OutDir  = Join-Path $Repo 'releases'
$ExeName = 'KomorebiDashboard.exe'
$exe     = Join-Path $OutDir $ExeName

$script:Pass = 0
$script:Fail = 0
function Ok($msg)   { $script:Pass++; Write-Host "  PASS  $msg" -ForegroundColor Green }
function No($msg)   { $script:Fail++; Write-Host "  FAIL  $msg" -ForegroundColor Red }
function Head($msg) { Write-Host ''; Write-Host "== $msg" -ForegroundColor Cyan }

if (-not (Test-Path $exe)) {
    throw "not published: $exe - run tests/ticket13-publish.tests.ps1 first"
}

# =====================================================================
Head '1. Exactly one file, nothing for the machine to supply'
# =====================================================================

# .gitkeep is version-control bookkeeping, not a payload.
$payload = @(Get-ChildItem $OutDir -Recurse -File -EA SilentlyContinue |
             Where-Object { $_.Name -ne '.gitkeep' })
$dirs    = @(Get-ChildItem $OutDir -Recurse -Directory -EA SilentlyContinue)

if ($payload.Count -eq 1 -and $payload[0].Name -eq $ExeName) {
    Ok "releases/ contains exactly one payload file ($ExeName)"
} else {
    No "expected exactly one payload file, found $($payload.Count): $((($payload).Name) -join ', ')"
}

if ($dirs.Count -eq 0) {
    Ok 'no satellite folders beside the EXE'
} else {
    No "found $($dirs.Count) folder(s) in releases/: $((($dirs).Name) -join ', ')"
}

# A missing satellite runtime folder is the classic framework-dependent tell.
# English-only is declared in the csproj, so no culture folders may ship.
$cultures = @(Get-ChildItem $OutDir -Recurse -Directory -EA SilentlyContinue |
              Where-Object { $_.Name -match '^[a-z]{2}(-[A-Za-z]+)?$' })
if ($cultures.Count -eq 0) {
    Ok 'no satellite culture directories'
} else {
    No "unexpected satellite cultures: $((($cultures).Name) -join ', ')"
}

# =====================================================================
Head '2. The runtime is INSIDE the file (self-contained, not framework-dependent)'
# =====================================================================

# Reading the whole 161 MB as a string is the honest way to do this: the
# bundle manifest lives in an appended trailer, so a scan of the first few MB
# finds nothing and would wrongly look like a failure.
$bytes = [IO.File]::ReadAllBytes($exe)
$all   = [Text.Encoding]::ASCII.GetString($bytes)
$mb    = [math]::Round($bytes.Length / 1MB, 1)

Write-Host "        (scanning $([math]::Round($bytes.Length/1MB,0)) MB)"
Write-Host ''

# Each of these is a REAL dependency. If any is absent the app resolves it
# from the machine, which is exactly what "self-contained" must prevent.
$required = [ordered]@{
    'coreclr (the runtime)'                        = 'coreclr'
    'System.Private.CoreLib'                      = 'System.Private.CoreLib'
    'PresentationFramework (WPF)'                  = 'PresentationFramework'
    'PresentationCore (WPF)'                       = 'PresentationCore'
    'PresentationUI (WPF)'                         = 'PresentationUI'
    'WindowsBase (WPF)'                            = 'WindowsBase'
    'the app itself'                               = 'KomorebiDashboard'
    'WPF-UI'                                       = 'Wpf.Ui'
    'CommunityToolkit.Mvvm'                        = 'CommunityToolkit.Mvvm'
    'the NETCore runtime pack'                     = 'Microsoft.NETCore.App'
    'the WindowsDesktop runtime pack'              = 'Microsoft.WindowsDesktop.App'
}

$absent = @()
foreach ($kv in $required.GetEnumerator()) {
    $found = $all.Contains($kv.Value)
    if ($found) { Ok "embedded: $($kv.Key)" }
    else { $absent += $kv.Key }
}
if ($absent.Count -gt 0) {
    No "NOT embedded (would come from the machine): $($absent -join ', ')"
}

# The RID decides whether this EXE can run on a given machine at all.
if ($all.Contains('win-x64')) { Ok 'bundle targets win-x64' }
else { No 'no win-x64 marker in the bundle' }

if ($all.Contains('.NETCoreApp,Version=v8.0')) { Ok 'bundle targets .NET 8 (v8.0)' }
else { No 'no .NETCoreApp v8.0 marker in the bundle' }

# =====================================================================
Head '3. ReadyToRun actually applied (the priority-1 startup claim)'
# =====================================================================

# R2R precompiles IL to native code. Without it the framework is JITted on
# every start, which is the cost ADR-0015 says R2R exists to avoid.
if ($all.Contains('RTR')) {
    Ok 'ReadyToRun native-code marker present in the bundle'
} else {
    No 'no R2R marker — was PublishReadyToRun actually honoured?'
}

# A size sanity check catches a silent fallback to framework-dependent far more
# clearly than any single marker can.
if ($mb -ge 120) {
    Ok "size $mb MB is consistent with self-contained + R2R"
} else {
    No "size $mb MB is too small for a self-contained R2R build (expected 120+ MB)"
}

# =====================================================================
Head '4. It still launches from the published location'
# =====================================================================

$help = & $exe --help 2>&1 | Out-String
$helpRc = $LASTEXITCODE
if ($helpRc -eq 0 -and $help -match 'Verbs:') {
    Ok 'the CLI twin runs from the published EXE'
} else {
    No "the CLI twin failed (rc=$helpRc)"
}

# Copy it somewhere with NO other files. If the bundle secretly needs a
# neighbour, this is where it shows. A clean temp dir is the closest thing to
# a clean machine this host can produce.
$iso = Join-Path $env:TEMP ('t13-isolated-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item $iso -ItemType Directory -Force | Out-Null
Copy-Item $exe (Join-Path $iso $ExeName) -Force

$p = $null
try {
    $p = Start-Process -FilePath (Join-Path $iso $ExeName) -PassThru `
         -RedirectStandardOutput (Join-Path $env:TEMP 't13iso.out') `
         -RedirectStandardError  (Join-Path $env:TEMP 't13iso.err')

    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt 90000) {
        $p.Refresh()
        if ($p.HasExited) { break }
        if ($p.MainWindowHandle -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 100
    }

    if ($p.HasExited) {
        No "the isolated copy exited early (rc=$($p.ExitCode)) - it needs a file that was not copied"
        Get-Content (Join-Path $env:TEMP 't13iso.err') -EA SilentlyContinue |
            Select-Object -First 10 | ForEach-Object { Write-Host "          $_" -ForegroundColor DarkYellow }
    } else {
        $pr = Get-Process -Id $p.Id
        Ok "the isolated copy opens a window (hwnd $($p.MainWindowHandle))"
        if ($pr.MainWindowTitle -match 'Komorebi') { Ok "window title is '$($pr.MainWindowTitle)'" }
        else { No "unexpected window title '$($pr.MainWindowTitle)'" }
        if ($pr.Responding) { Ok 'UI thread is responding' }
        else { No 'UI thread is hung' }
        Ok "time-to-window: $($sw.ElapsedMilliseconds) ms"
    }

    # A self-contained app must not print the runtime-missing dialog. On a
    # machine without .NET, a framework-dependent build fails with 0x80008096;
    # detecting that string is the cheapest early warning available here.
    $isoErr = Get-Content (Join-Path $env:TEMP 't13iso.err') -Raw -EA SilentlyContinue
    if ($isoErr -match 'You must install|0x80008096|requires \.NET') {
        No "the app reported a missing .NET runtime: $isoErr"
    } else {
        Ok 'no missing-.NET-runtime message'
    }
}
finally {
    if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
    Remove-Item $iso -Recurse -Force -EA SilentlyContinue
}

Write-Host ''
Write-Host ('=' * 62)
if ($script:Fail -gt 0) {
    Write-Host " RESULT: $script:Pass passed, $script:Fail FAILED" -ForegroundColor Red
    Write-Host ''
    Write-Host ' NOTE: this still does NOT prove D-T1 (running with no .NET runtime installed).'
    Write-Host '       That remains deferred to the Sandbox - see docs/TESTING.md.'
    exit 1
}
Write-Host " RESULT: all $script:Pass runtime assertions passed" -ForegroundColor Green
Write-Host ''
Write-Host ' REMINDER: D-T1 (no .NET runtime installed) is still unproven and blocks'
Write-Host '          ticket 13 from being fully closed. See docs/TESTING.md.'
exit 0
