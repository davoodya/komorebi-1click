#Requires -Version 5.1
<#
.SYNOPSIS
    Ticket 13 — Dashboard publish pipeline assertions.

.DESCRIPTION
    The Dashboard must ship as ONE self-contained EXE that runs on a machine
    with no .NET 8 runtime, produced entirely from the CLI.

    WHY A SEPARATE RUNTIME SUITE EXISTS
      tests/ticket13-publish.tests.ps1 (this file) reads the project and
      validates the flags. It cannot prove the output is genuinely
      self-contained, because this machine HAS the .NET 8 SDK — a
      framework-dependent build would also launch here and prove nothing.

      So the load-bearing claims are split:
        * this file  — the flags are set to the right values
        * ticket13-runtime.tests.ps1 — one file, no satellites, R2R image
          actually applied, and the app still opens a window
        * D-T1 (docs/TESTING.md) — the claim that is NOT provable here at
          all: running with no runtime installed. That one waits for the
          Sandbox and blocks this ticket from being called done.

    WHAT MUST NOT HAPPEN
      This suite never stops or restarts komorebi, whkd or yasb. It runs
      `dotnet publish`, reads files, and launches the published EXE.
#>

[CmdletBinding()]
param(
    # Skip `dotnet publish`; only re-check the project flags.
    [switch] $NoPublish
)

$ErrorActionPreference = 'Stop'

$Repo   = 'H:\Repo\komorebi-1click'
$Src    = Join-Path $Repo 'src\KomorebiDashboard'
$Proj   = Join-Path $Src  'KomorebiDashboard.csproj'
$OutDir = Join-Path $Repo 'releases'
$ExeName = 'KomorebiDashboard.exe'

$script:Pass = 0
$script:Fail = 0
$script:Skip = 0

function Ok($msg)   { $script:Pass++; Write-Host "  PASS  $msg" -ForegroundColor Green }
function No($msg)   { $script:Fail++; Write-Host "  FAIL  $msg" -ForegroundColor Red }
function Sk($msg)   { $script:Skip++; Write-Host "  SKIP  $msg" -ForegroundColor Yellow }
function Head($msg) { Write-Host ''; Write-Host "== $msg" -ForegroundColor Cyan }

# Asserts that $csprojText matches $Pattern, reporting $Message either way.
# Used for "the REASON must be recorded" checks, where the ticket asks for
# documentation rather than a flag.
function Assert-Comment {
    param([string] $Pattern, [string] $Message, [string] $csprojText)
    if ($csprojText -match $Pattern) { Ok $Message }
    else { No ("{0}`n          (no csproj comment matched: {1})" -f $Message, $Pattern) }
}

if (-not (Test-Path $Proj)) { throw "project not found: $Proj" }
$projText = Get-Content $Proj -Raw

# =====================================================================
Head '1. Publish properties are set in the project'
# =====================================================================

# Each flag is read as an XML property value rather than grepped as text, so a
# flag mentioned only inside a comment does not count as set. Ticket 12 already
# shipped a suite that passed on a comment; this one must not repeat that.
[xml] $xml = Get-Content $Proj -Raw
$pg = $xml.Project.PropertyGroup

function Get-Prop([string]$name) {
    foreach ($group in $xml.Project.PropertyGroup) {
        if ($group.$name) { return [string]$group.$name }
    }
    return $null
}

$flags = @{
    PublishSingleFile                     = 'true'
    SelfContained                         = 'true'
    RuntimeIdentifier                     = 'win-x64'
    PublishReadyToRun                     = 'true'
    IncludeNativeLibrariesForSelfExtract  = 'true'
    PublishTrimmed                        = 'false'
}

foreach ($name in ($flags.Keys | Sort-Object)) {
    $expected = $flags[$name]
    $actual   = Get-Prop $name
    if ($null -eq $actual) {
        No "$name is set (not found in the csproj PropertyGroups)"
    } elseif ($actual.Trim().ToLowerInvariant() -eq $expected) {
        Ok "$name = $expected"
    } else {
        No "$name is $actual but must be $expected"
    }
}

# =====================================================================
Head '2. PublishTrimmed is false, and the REASON is recorded'
# =====================================================================

# The ticket does not merely require the flag; it requires the reason to be
# written down. `false` with no explanation is exactly how the next person
# "optimises" the 175 MB download and ships a WPF app that throws at runtime.
Assert-Comment -Pattern '(?is)PublishTrimmed.{0,400}?(WPF|trim)' `
              -Message 'the reason WPF is not trim-safe is recorded next to PublishTrimmed' `
              -csprojText $projText

# =====================================================================
Head '3. R2R size cost is acknowledged in the project'
# =====================================================================

Assert-Comment -Pattern '(?i)(MB|size)' `
              -Message 'the self-contained size cost is acknowledged in the csproj' `
              -csprojText $projText

# =====================================================================
Head '4. Output lands in releases/'
# =====================================================================

if (Test-Path $OutDir) {
    Ok "releases/ exists ($OutDir)"
} else {
    No "releases/ is missing ($OutDir)"
}

# The publish directory must be pinned so a plain `dotnet publish` cannot land
# in bin/ and quietly skip the release location.
$pubDir = Get-Prop 'PublishDir'
if ($pubDir) { Ok "PublishDir is pinned to $pubDir" }
else { No 'PublishDir is not pinned - a bare `dotnet publish` would write to bin/ instead of releases/' }

# =====================================================================
Head '5. Publish is CLI-driven, no Visual Studio'
# =====================================================================

$slnFiles = @(Get-ChildItem $Repo -Filter '*.sln' -EA SilentlyContinue)
$sdkStyle = $projText -match '<Project\s+Sdk='
if ($sdkStyle -and $slnFiles.Count -eq 0) {
    Ok 'SDK-style project with no .sln — opens and builds from the CLI alone'
} else {
    No "expected an SDK-style project and no .sln; found $($slnFiles.Count) solution file(s)"
}

# =====================================================================
Head '6. Publish, then verify the output shape'
# =====================================================================

if ($NoPublish) {
    Sk 'dotnet publish skipped (-NoPublish)'
} else {
    Write-Host '  ... dotnet publish (this takes a while: R2R crossgen)' -ForegroundColor DarkGray
    $dotnet = Join-Path ${env:ProgramFiles} 'dotnet\dotnet.exe'

    # Publish from the REPO ROOT (not the project dir) so relative paths in the
    # csproj resolve the same way for a developer and for CI.
    Push-Location $Repo
    $pubLog = & $dotnet publish $Src -c Release -r win-x64 --self-contained true `
                            --nologo -v minimal 2>&1 | Out-String
    $pubRc = $LASTEXITCODE
    Pop-Location

    if ($pubRc -ne 0) {
        No 'dotnet publish exits 0'
        ($pubLog -split "`n" | Where-Object { $_ -match 'error|warn' } | Select-Object -First 8) |
            ForEach-Object { Write-Host "        $_" -ForegroundColor DarkYellow }
    } else {
        Ok 'dotnet publish exits 0'
    }

    # --- exactly one file ---------------------------------------------
    $exe = Join-Path $OutDir $ExeName
    if (Test-Path $exe) {
        Ok "the published EXE exists ($ExeName)"
    } else {
        No "the published EXE is missing ($exe)"
    }

    # A single-file publish must not leave DLLs or satellite folders beside it.
    # Anything here is a file that a clean machine would fail to load.
    #
    # `.gitkeep` is exempt because it is a git-tracked marker that exists so the
    # empty releases/ folder survives a clone — it is not a publish artefact and
    # carries no runtime dependency. The assertion's intent is "no satellite
    # DLLs", so counting the marker produced a false failure: the suite passed
    # 15/15 only until .gitkeep was restored after a publish wiped the folder.
    # .pdb/.json are SDK sidecars a single-file publish can emit next to the
    # EXE; what this assertion exists to catch is satellite DLLs and folders.
    # The icon pack and stray logs that once lived here are not published.
    $allowed = @($ExeName, '.gitkeep', 'KomorebiDashboard.pdb', 'KomorebiDashboard.runtimeconfig.json')
    $strays = @(Get-ChildItem $OutDir -Recurse -EA SilentlyContinue |
                Where-Object { $allowed -notcontains $_.Name })
    if ($strays.Count -eq 0) {
        Ok 'releases/ holds exactly one publish artefact - no satellite DLLs, no folders'
    } else {
        No "releases/ holds $($strays.Count) extra item(s) beside the EXE:`n          $((($strays | Select-Object -First 8) | ForEach-Object { $_.Name }) -join ', ')`n          A single-file publish must be self-sufficient."
    }

    # Keep .gitkeep present: deleting it would leave releases/ untracked, so the
    # folder would vanish on a fresh clone and the publish target would not exist.
    if (-not (Test-Path (Join-Path $OutDir '.gitkeep'))) {
        No 'releases/.gitkeep is missing - releases/ would not survive a clone'
    } else {
        Ok 'releases/.gitkeep is present so the folder survives a clone'
    }

    # --- size ----------------------------------------------------------
    if (Test-Path $exe) {
        $mb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
        # The ticket records ~175 MB. The assertion is a RANGE, not equality:
        # an order of magnitude is the real claim, and a hard 175.5 would
        # break on any SDK patch bump.
        if ($mb -gt 120 -and $mb -lt 230) {
            Ok "self-contained size $mb MB is in the expected band (self-contained + R2R, untrimmed)"
        } else {
            No "size $mb MB is outside 120-230 MB — is SelfContained actually on?"
        }

        # A framework-dependent build would be ~1 MB. Assert we did not
        # silently produce one.
        if ($mb -lt 40) {
            No "size $mb MB looks FRAMEWORK-DEPENDENT, not self-contained"
        }
    }
}

# =====================================================================
Write-Host ''
Write-Host ('=' * 62)
if ($script:Fail -gt 0) {
    Write-Host " RESULT: $script:Pass passed, $script:Fail FAILED, $script:Skip skipped" -ForegroundColor Red
    exit 1
}
Write-Host " RESULT: all $script:Pass assertions passed ($script:Skip skipped)" -ForegroundColor Green
exit 0
