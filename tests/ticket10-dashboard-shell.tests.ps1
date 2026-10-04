#Requires -Version 5.1
<#
    Ticket 10 — Admin Dashboard shell (WPF .NET 8).

    WHY THESE TESTS EXIST
      ADR-0009 and ADR-0013 exist to make one guarantee: the GUI and the CLI can
      never drift apart, because both are GENERATED from a single verb registry.
      A registry that only half the app reads is worse than no registry at all,
      because it looks like the guarantee holds. So the load-bearing assertions
      here are cross-checks, not existence checks: the verb set is compared
      against ADR-0013 verbatim, every verb is required to have a button in
      EXACTLY ONE tab, and the CLI is required to resolve through the same table
      the GUI binds to.

      The suite really builds the project with `dotnet build`, so a green run is
      evidence the shell compiles, not merely that files exist.

    WHAT IS DELIBERATELY NOT TESTED HERE
      Launching the WPF window. That needs an interactive desktop and belongs to
      the Sandbox pass (ticket 14). What IS proven here: the XAML parses as
      valid markup and every View is free of logic.

    Sandbox note: `-SkipBuild` skips the slow build when you only want the
    structural assertions.
#>
[CmdletBinding()]
param([switch] $SkipBuild)

$ErrorActionPreference = 'Stop'
$script:passed = 0
$script:failed = 0

function Assert([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) {
        Write-Host "  PASS  $Name" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "        $Detail" -ForegroundColor DarkRed }
        $script:failed++
    }
}

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Src         = Join-Path $ProjectRoot 'src\KomorebiDashboard'

# The ADR-0013 verb set, transcribed. If this list and the registry disagree,
# one of them is wrong and the build should not be trusted until they match.
$AdrVerbs = @(
    'kill-all','kill-komorebi','kill-whkd','kill-yasb',
    'start-all','start-komorebi','start-whkd','start-yasb',
    'restart-all','restart-komorebi','restart-whkd','restart-yasb',
    'startup','export','import','set-transparency',
    'status','recover-monitors','display-diag','reset-workspaces','repair-whkdrc',
    'uninstall','cleanup',
    'ahk'
) | Sort-Object -Unique

Write-Host ''
Write-Host '=== Ticket 10 — Dashboard shell ===' -ForegroundColor Cyan
Write-Host "  project: $Src"

# ---------------------------------------------------------------------------
# 1. Project shape
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- project shape --' -ForegroundColor Cyan

$csproj = Join-Path $Src 'KomorebiDashboard.csproj'
Assert 'the csproj exists' (Test-Path $csproj) $csproj

if (Test-Path $csproj) {
    $proj = Get-Content $csproj -Raw

    Assert 'targets net8.0-windows'      ($proj -match '<TargetFramework>net8\.0-windows</TargetFramework>')
    Assert 'OutputType is WinExe'        ($proj -match '<OutputType>WinExe</OutputType>')
    Assert 'UseWPF is enabled'           ($proj -match '<UseWPF>true</UseWPF>')

    # Versions are pinned exactly. A floating range would let a restore pick a
    # different WPF-UI and change rendering with no code change at all.
    Assert 'CommunityToolkit.Mvvm pinned to 8.4.0' (
        $proj -match '<PackageReference\s+Include="CommunityToolkit\.Mvvm"\s+Version="8\.4\.0"'
    )
    Assert 'WPF-UI pinned to 4.3.0' (
        $proj -match '<PackageReference\s+Include="WPF-UI"\s+Version="4\.3\.0"'
    )
    Assert 'no floating version ranges'  ($proj -notmatch 'Version="\[\^')
}

# ---------------------------------------------------------------------------
# 2. Three tiers, and only three
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- three tiers --' -ForegroundColor Cyan

foreach ($tier in 'Models','Services','ViewModels','Views') {
    $d = Join-Path $Src $tier
    Assert "tier '$tier' exists" (Test-Path $d) $d
}

$views = @(Get-ChildItem (Join-Path $Src 'Views') -Filter '*.xaml' -EA SilentlyContinue)
Assert 'six tab views'                 ($views.Count -eq 6) "found $($views.Count): $(($views.Name) -join ', ')"
Assert 'six view models'               (@(Get-ChildItem (Join-Path $Src 'ViewModels') -Filter '*ViewModel.cs' -EA SilentlyContinue).Count -ge 6)

# ADR-0009 tab names, in order. Reused later as $TabNames.
$TabNames = @('KillStart','Restart','Settings','AutoHotkey','Debugging','Uninstall')
foreach ($tab in $TabNames) {
    Assert "tab '$tab' has a view"  (Test-Path (Join-Path $Src "Views\$tab`View.xaml"))
    Assert "tab '$tab' has a VM"    (Test-Path (Join-Path $Src "ViewModels\$tab`ViewModel.cs"))
}

# ---------------------------------------------------------------------------
# 3. ScriptService is the only process-aware layer
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- ScriptService --' -ForegroundColor Cyan

$svcPath = Join-Path $Src 'Services\ScriptService.cs'
$regPath = Join-Path $Src 'Services\VerbRegistry.cs'
Assert 'ScriptService.cs exists' (Test-Path $svcPath)
if (Test-Path $svcPath) {
    $svc = Get-Content $svcPath -Raw
    Assert 'ScriptService starts a process'            ($svc -match 'Process\.Start|new\s+Process')
    Assert 'ScriptService runs powershell'              ($svc -match 'powershell|pwsh')
    Assert 'ScriptService passes the registry FixedArguments' ($svc -match 'FixedArguments')
}

# ScriptResult has its own type file; asserting the fields inside ScriptService.cs
# would be wrong, since that file only ever CONSTRUCTS the record.
$resultFile = Join-Path $Src 'Models\ScriptResult.cs'
Assert 'ScriptResult has its own type file' (Test-Path $resultFile)
if (Test-Path $resultFile) {
    $result = Get-Content $resultFile -Raw
    Assert 'ScriptResult carries ExitCode, Output and Duration' (
        ($result -match 'record\s+ScriptResult' -or $result -match 'class\s+ScriptResult') -and
        $result -match 'ExitCode' -and $result -match 'Output' -and $result -match 'Duration'
    )
}

# The load-bearing assertion of this whole ticket: every script the registry
# names must actually exist. Six rows originally pointed at kill-komorebi.ps1,
# start-whkd.ps1 and friends, none of which had ever been written -- the
# dashboard would have shown "script not found" for every Kill/Start button.
if (Test-Path $regPath) {
    $regRaw = Get-Content $regPath -Raw
    $referenced = [regex]::Matches($regRaw, 'new\("[a-z0-9-]+",\s*"([\w.-]+\.ps1)"') |
                   ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    $missingScripts = @($referenced | Where-Object {
        -not (Test-Path (Join-Path $ProjectRoot "scripts\$_"))
    })
    Assert 'every script the registry names exists' ($missingScripts.Count -eq 0) `
           "missing from scripts\: $($missingScripts -join ', ')"
}

# ---------------------------------------------------------------------------
# 4. One registry, and the verb set matches ADR-0013
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- verb registry --' -ForegroundColor Cyan

$regPath = Join-Path $Src 'Services\VerbRegistry.cs'
Assert 'VerbRegistry.cs exists' (Test-Path $regPath)

if (Test-Path $regPath) {
    $reg = Get-Content $regPath -Raw

    # Every verb the ADR names must appear as a registry entry.
    $missing = @($AdrVerbs | Where-Object { $reg -notmatch "['`"]$([regex]::Escape($_))['`"]" })
    Assert 'every ADR-0013 verb has a registry row' ($missing.Count -eq 0) "missing: $($missing -join ', ')"

    # The registry row shape the ADR requires.
    Assert 'rows carry RequiresAdmin' ($reg -match 'RequiresAdmin')
    Assert 'rows carry help text'     ($reg -match 'Help')
    Assert 'rows carry an argument shape' ($reg -match 'Argument|ArgShape|Args')

    # kill-komorebi / start-komorebi must drag whkd along, and the row must say
    # so. Asserted on the registry itself because this is the one place the CLI
    # and the GUI could each "helpfully" mean something different. The mechanism
    # is the -Components komorebi-whkd flag on the shared script, not a
    # separate .ps1 (see FixedArguments in VerbDefinition).
    Assert 'kill-komorebi also acts on whkd' (
        $reg -match '"kill-komorebi".*komorebi-whkd' -and $reg -match 'also acts on whkd|which runs with it'
    )
    Assert 'start-komorebi also acts on whkd' (
        $reg -match '"start-komorebi".*komorebi-whkd'
    )
}

# ---------------------------------------------------------------------------
# 5. GUI and CLI both read the registry (the whole point of ADR-0013)
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- GUI and CLI share the registry --' -ForegroundColor Cyan

$cliPath = Join-Path $Src 'Services\Cli\CommandLineParser.cs'
if (-not (Test-Path $cliPath)) { $cliPath = Join-Path $Src 'Services\CommandLineParser.cs' }
Assert 'a CLI parser exists' (Test-Path $cliPath) $cliPath

if (Test-Path $cliPath) {
    $cli = Get-Content $cliPath -Raw
    Assert 'CLI resolves verbs through VerbRegistry' ($cli -match 'VerbRegistry')
}

if (Test-Path $regPath) {
    $reg = Get-Content $regPath -Raw
    Assert 'help text is generated from the registry' (
        $reg -match 'Help' -and ($reg -match 'BuildHelp|GenerateHelp|ToHelp')
    )
}

# Help must not be a second hand-maintained list: that is exactly the drift the
# ADR was written to prevent. Exclude bin\ and obj\, or the build's own
# GeneratedInternalTypeHelper.g.cs matches on the substring "Helper".
$helpFiles = @(Get-ChildItem $Src -Recurse -Filter '*.cs' -EA SilentlyContinue |
               Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } |
               Where-Object { $_.Name -match 'Help' })
Assert 'no separate hand-written help file' ($helpFiles.Count -eq 0) `
       "found: $(($helpFiles.Name) -join ', ')"

# ---------------------------------------------------------------------------
# 6. Views hold zero logic
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- Views hold zero logic --' -ForegroundColor Cyan

foreach ($v in $views) {
    $code = Join-Path $Src ('Views\' + $v.BaseName + '.xaml.cs')
    $codeText = if (Test-Path $code) { Get-Content $code -Raw } else { '' }
    $violation = ($v.FullName + "`n" + $codeText) -match 'Process\.Start|powershell\.exe|Invoke-Expression|\.ps1'
    Assert "view '$($v.BaseName)' contains no logic" (-not $violation)
}

# Every XAML must be parseable markup, not merely present. XDocument.Load
# THROWS on malformed XML, so a try/catch is the assertion: parse failure is the
# only thing that should land in $bad.
foreach ($v in $views) {
    $bad = $false
    try { [void][System.Xml.Linq.XDocument]::Load($v.FullName) }
    catch { $bad = $true; $xmlError = $_.Exception.Message }
    Assert "view '$($v.BaseName)' is valid XAML" (-not $bad) $(if ($bad) { $xmlError } else { '' })
}

# ---------------------------------------------------------------------------
# 7. Every verb belongs to EXACTLY ONE tab
# ---------------------------------------------------------------------------
# Asserted against the REGISTRY, not by grepping ViewModels for verb strings.
# The ViewModels deliberately contain no verb names -- they call
# VerbRegistry.ForTab(tab) -- so a grep found nothing and would keep finding
# nothing even if every verb were wired to the wrong tab. The real invariant is
# one registry row per verb, whose Tab field names exactly one existing tab.
Write-Host ''
Write-Host '-- every verb is reachable from exactly one tab --' -ForegroundColor Cyan

if (Test-Path $regPath) {
    $regRaw = Get-Content $regPath -Raw
    $rowMatches = [regex]::Matches($regRaw,
        'new\("(?<verb>[a-z0-9-]+)",\s*"[^"]+",\s*"[^"]*",\s*(?:true|false),\s*"[^"]*",\s*Tabs\.(?<tab>\w+)')

    $verbRows = $rowMatches | ForEach-Object {
        [pscustomobject]@{ Verb = $_.Groups['verb'].Value; Tab = $_.Groups['tab'].Value }
    }

    Assert 'the registry defines verbs' ($verbRows.Count -gt 0) "parsed $($verbRows.Count) rows"

    foreach ($row in $verbRows) {
        $dupes = @($verbRows | Where-Object { $_.Verb -eq $row.Verb })
        Assert "verb '$($row.Verb)' has exactly one registry row" ($dupes.Count -eq 1) "found $($dupes.Count)"
        Assert "verb '$($row.Verb)' names a real tab ('$($row.Tab)')" ($row.Tab -in $TabNames)
    }

    # Every ADR verb must be reachable, and every tab must have at least one
    # button -- an empty tab is a tab whose mechanisms went missing.
    $registryVerbs = @($verbRows | ForEach-Object { $_.Verb })
    $unreachable = @($AdrVerbs | Where-Object { $registryVerbs -notcontains $_ })
    Assert 'every ADR-0013 verb is reachable' ($unreachable.Count -eq 0) "unreachable: $($unreachable -join ', ')"

    foreach ($tab in $TabNames) {
        $count = @($verbRows | Where-Object { $_.Tab -eq $tab }).Count
        Assert "tab '$tab' has at least one button" ($count -gt 0) "0 verbs"
    }

    # Each ViewModel must ask the registry for its own tab, which is what makes
    # the button list appear without any per-verb wiring in the View.
    foreach ($tab in $TabNames) {
        $vm = Join-Path $Src "ViewModels\${tab}ViewModel.cs"
        if (Test-Path $vm) {
            Assert "tab '$tab' VM pulls its verbs from the registry" `
                   ((Get-Content $vm -Raw) -match "VerbRegistry\.Tabs\.$tab")
        }
    }
}

# ---------------------------------------------------------------------------
# 8. It really builds
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- dotnet build --' -ForegroundColor Cyan

if ($SkipBuild) {
    Write-Host '  SKIP  -SkipBuild given' -ForegroundColor DarkGray
} else {
    $dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue)
    if (-not $dotnet) {
        Assert 'dotnet SDK is available' $false 'dotnet not on PATH'
    } else {
        $buildOut = (& dotnet build $Src -c Release -v quiet --nologo 2>&1) -join "`n"
        $buildExit = $LASTEXITCODE
        Assert 'dotnet build exits 0' ($buildExit -eq 0) ($buildOut -split "`n" | Select-Object -Last 6) -join "`n"
        Assert 'build reports no errors' ($buildOut -notmatch ':\s*error\s')
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ''
$summaryColour = if ($script:failed) { 'Red' } else { 'Green' }
Write-Host ("  passed: {0}  failed: {1}" -f $script:passed, $script:failed) -ForegroundColor $summaryColour
if ($script:failed -eq 0) { Write-Host '  ALL GREEN' -ForegroundColor Green }

if ($script:failed -gt 0) { exit 1 }
exit 0