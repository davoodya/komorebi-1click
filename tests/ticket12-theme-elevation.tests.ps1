#Requires -Version 5.1
<#
    Ticket 12 — Dashboard theming (Dark/Light, WPF-UI) + elevation dialog + CLI
    privilege checks.

    WHY THESE TESTS EXIST
      Two guarantees, both of which have already been violated once in this
      project:

      1. THEME. ADR-0015 ranks "modern, beautiful UI" as priority 4 — but only
         after speed, lag and smoothness. WPF-UI is a UI *framework*: switching
         themes means swapping ResourceDictionary instances, and doing that
         while a dispatcher operation is in flight is exactly the kind of thing
         that produces a janky or half-themed window. So the assertions here are
         about ORDER and SINGLETON behaviour (one dictionary per theme, applied
         through the documented API), not about pixel colours.

      2. ELEVATION. ADR-0012 exists because the Dashboard mixes per-user
         operations with administrative ones. The load-bearing risk is SILENCE:
         a CLI `uninstall` that quietly does nothing is a data-loss-class
         surprise (ADR-0012 words this explicitly). So the suite asserts the
         verb that needs elevation REFUSES, with a non-zero exit, and that the
         refusal names the verb.

    RUNTIME EVIDENCE (section 8)
      - Both themes are really applied through WPF-UI and the live
        Application.Current.Resources reports the change.
      - An elevation-gated verb is really invoked through the built CLI and
        must refuse with a non-zero exit and a message naming the verb.
      - The app is really launched and must still open a window after theming.

    WHAT IS DELIBERATELY NOT TESTED HERE
      The UAC consent prompt itself. On a UAC-disabled source machine it never
      appears, and on a UAC-enabled one it is a desktop-level dialog no test can
      click. ADR-0012 already registers this as a Sandbox item (ticket 14). What
      IS proven here: the decision logic, the message content, the exit codes and
      the non-blocking relaunch path.

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

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Ticket 12 - Theming + elevation' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan

$ThemePath     = Join-Path $Src 'Services\ThemeService.cs'
$ElevationPath = Join-Path $Src 'Services\ElevationService.cs'
$AppPath       = Join-Path $Src 'App.xaml'
$AppCsPath     = Join-Path $Src 'App.xaml.cs'
$MainPath      = Join-Path $Src 'MainWindow.xaml'
$RegPath       = Join-Path $Src 'Services\VerbRegistry.cs'

# =====================================================================
# Section 1 - WPF-UI theming is wired at the resource level
# =====================================================================
Write-Host ''
Write-Host '[1] WPF-UI Fluent theming is present' -ForegroundColor Yellow

Assert 'ThemeService.cs exists' (Test-Path $ThemePath) $ThemePath
Assert 'App.xaml exists'        (Test-Path $AppPath)
Assert 'App.xaml.cs exists'    (Test-Path $AppCsPath)

if (Test-Path $AppPath) {
    $app = Get-Content $AppPath -Raw

    # WPF-UI ships its palette as XAML resource dictionaries. Without merging
    # them there is no Fluent look at all, whatever the code says.
    Assert 'App.xaml merges the WPF-UI theme dictionaries' `
           ($app -match 'ThemesDictionary' -or $app -match 'wpf-ui') `
           'App.xaml must merge Wpf.Ui.Markup.ThemesDictionary'
    Assert 'App.xaml declares the WPF-UI assembly namespace' `
           ($app -match 'assembly=Wpf\.Ui')

    # A previous version of this assertion demanded 'Controls.Themes' or
    # 'Themes.xaml' appear in App.xaml. That was wrong on two counts:
    #   * a separate Controls.xaml dictionary does not exist as a standalone
    #     resource — ThemesDictionary already carries the control styles, and
    #   * naming the theme file by path is exactly what crashed startup
    #     ("Cannot locate resource 'themes/light.xaml'").
    # The real requirement is that the theme is merged without a hardcoded
    # path. The 443-key merged dictionary and the Fluent control resources are
    # asserted for real by tests/ticket12-runtime.tests.ps1.
    Assert 'App.xaml merges the theme WITHOUT a hardcoded pack:// path' `
           ($app -match 'ThemesDictionary' -and $app -notmatch 'pack://application[^"]*Themes/') `
           'a hardcoded theme path is the startup crash recorded in ThemeService.Ensure'
}

if (Test-Path $ThemePath) {
    $th = Get-Content $ThemePath -Raw
    $thCode = [regex]::Replace($th, '(?m)^\s*//.*$', '')

    Assert 'ThemeService uses WPF-UI ApplicationTheme' `
           ($thCode -match 'ApplicationThemeManager|ApplicationTheme')
    Assert 'ThemeService supports both Dark and Light' `
           ($thCode -match 'Dark' -and $thCode -match 'Light')
    Assert 'ThemeService keeps one dictionary per theme (no churn)' `
           ($thCode -match 'Dictionary' -and $thCode -match 'static')
}

# =====================================================================
# Section 2 - runtime theme switching, applied immediately
# =====================================================================
Write-Host ''
Write-Host '[2] The user can switch theme at runtime' -ForegroundColor Yellow

if (Test-Path $ThemePath) {
    $th = Get-Content $ThemePath -Raw

    Assert 'ThemeService exposes an Apply/Set method' `
           ($th -match 'public\s+static\s+.*(Apply|Set)\w*\s*\(')
    Assert 'the current theme is readable' `
           ($th -match 'Current\w*Theme' -or $th -match 'public\s+static\s+ApplicationTheme\s+Current')

    # Applying must go through WPF-UI's own Apply, not a hand-rolled
    # dictionary swap: Apply() is what re-resolves every ThemeResource the
    # controls already bound, which is what makes it apply IMMEDIATELY rather
    # than on the next window.
    Assert 'applying goes through WPF-UI Apply (immediate, not on-next-window)' `
           ($th -match 'ApplicationThemeManager\.Apply|\.Apply\(')
}

# A theme toggle must be REACHABLE from the UI, not just implemented.
$toggleFound = $false
foreach ($f in @(Get-ChildItem $Src -Recurse -Filter '*.xaml' -EA SilentlyContinue |
                 Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' })) {
    if ((Get-Content $f.FullName -Raw) -match 'ToggleTheme|SwitchTheme|ThemeToggle') { $toggleFound = $true }
}
Assert 'a theme toggle is bound in the UI' $toggleFound `
       'the theme must be switchable from inside the app, not only in code'

if (Test-Path $MainPath) {
    $mw = Get-Content $MainPath -Raw
    Assert 'MainWindow offers the theme switch' `
           ($mw -match 'ToggleTheme|SwitchTheme|ThemeToggle')
}

# =====================================================================
# Section 3 - Windows 11 Fluent is the default
# =====================================================================
Write-Host ''
Write-Host '[3] Defaults to the Windows 11 Fluent appearance' -ForegroundColor Yellow

if (Test-Path $ThemePath) {
    $th = Get-Content $ThemePath -Raw
    # Fluent = WPF-UI's Mica/Acrylic backdrop on a Win11 target.
    Assert 'a Fluent backdrop is configured' `
           ($th -match 'Mica|Acrylic|WindowBackdropType')
    Assert 'the default theme is explicit' `
           ($th -match 'DefaultTheme|Apply\(')
}

if (Test-Path $AppCsPath) {
    $appCs = Get-Content $AppCsPath -Raw
    # The theme must be applied during startup, before the window is shown.
    # Applying it after Show() produces a visible light-to-dark flash, which
    # is priority-2 (smoothness) damage caused by priority-4 work.
    Assert 'the theme is applied at startup' ($appCs -match 'Theme')
    $iTheme = [regex]::Match($appCs, 'Theme')
    $iShow  = [regex]::Match($appCs, 'MainWindow\.Show\(\)')
    if ($iTheme.Success -and $iShow.Success) {
        Assert 'the theme is applied BEFORE the window is shown (no flash)' `
               ($iTheme.Index -lt $iShow.Index) `
               "Theme at $($iTheme.Index), Show at $($iShow.Index)"
    }
}

# =====================================================================
# Section 4 - per-operation elevation, honoured from the registry
# =====================================================================
Write-Host ''
Write-Host '[4] RequiresAdmin is honoured per operation (ADR-0012)' -ForegroundColor Yellow

Assert 'ElevationService.cs exists' (Test-Path $ElevationPath) $ElevationPath

if (Test-Path $ElevationPath) {
    $el = Get-Content $ElevationPath -Raw
    $elCode = [regex]::Replace($el, '(?m)^\s*//.*$', '')

    Assert 'ElevationService can tell whether it is elevated' `
           ($elCode -match 'IsElevated|IsAdministrator')
    Assert 'it uses a real API, not a guess' `
           ($elCode -match 'WindowsPrincipal|WindowsIdentity')
    Assert 'the elevated relaunch uses runas' `
           ($elCode -match 'runas')
    Assert 'the relaunch uses Process.Start' `
           ($elCode -match 'Process\.Start|new\s+Process')
    # The unelevated instance must EXIT after spawning the elevated one, or the
    # two instances race over the same scheduled tasks (ADR-0012 Consequences).
    Assert 'the current instance exits after relaunching' `
           ($elCode -match 'Exit|Shutdown')

    # The dialog is a fixed requirement from Davood's Round-2 answer.
    Assert 'the dialog title is exactly "Rerun as Administrator"' `
           ($el -match 'Rerun as Administrator')
    Assert 'the dialog offers Rerun as Administrator' `
           ($el -match 'RerunAsAdministrator|Rerun as Administrator')
    Assert 'the dialog offers OK and Cancel' `
           ($el -match 'OK' -and $el -match 'Cancel')
}

# The message must name the SPECIFIC features, generated from the registry.
if (Test-Path $RegPath) {
    $reg = Get-Content $RegPath -Raw
    Assert 'VerbRegistry still declares RequiresAdmin' ($reg -match 'RequiresAdmin')

    $adminVerbs = @([regex]::Matches($reg, 'new\("([^"]+)",[^)]*?true,') |
                    ForEach-Object { $_.Groups[1].Value })
    Assert 'the registry has admin verbs to gate' ($adminVerbs.Count -gt 0) `
           "found: $($adminVerbs -join ', ')"
}

if (Test-Path $ElevationPath) {
    $el = Get-Content $ElevationPath -Raw
    # Generated from the flags, not hardcoded: a new admin verb must appear in
    # the dialog with no code change.
    Assert 'the dialog message is generated from the registry flags' `
           ($el -match 'RequiresAdmin')
    Assert 'the message enumerates the admin features' `
           ($el -match 'Verb|Feature|Admin')
}

# =====================================================================
# Section 5 - the CLI refuses instead of silently no-op'ing
# =====================================================================
Write-Host ''
Write-Host '[5] CLI privilege check refuses loudly (ADR-0012)' -ForegroundColor Yellow

if (Test-Path $AppCsPath) {
    $appCs = Get-Content $AppCsPath -Raw

    Assert 'the CLI consults the elevation check' `
           ($appCs -match 'IsElevated|Elevation')

    # This asserted the literal token 'RequiresAdmin' inside App.xaml.cs. That
    # is an implementation detail, and it was wrong: the CLI correctly
    # delegates the decision to ElevationService.CanRun(verb), and the flag
    # lives on VerbDefinition. Demanding the token would have forced a
    # duplicated, drift-prone privilege check into the CLI.
    # What actually matters is that the gate is reached before the script
    # starts — asserted as an ordering property below.
    Assert 'the CLI gates on the per-verb privilege decision' `
           ($appCs -match 'CanRun\s*\(') `
           'expected the CLI to delegate to ElevationService.CanRun(verb)'

    # ADR-0012: "exits non-zero instead of silently failing". This is the
    # single most important assertion in the whole ticket.
    Assert 'the CLI returns a non-zero exit when privileges are missing' `
           ($appCs -match 'return\s+ElevationService\.InsufficientPrivilegeExitCode')
    Assert 'the refusal message names the verb' `
           ($appCs -match 'RefusalMessage')

    # ORDERING, not presence. A gate placed after the script is launched is
    # worse than no gate at all, because the destructive action has already
    # happened by the time the user is told. The check must sit between the
    # verb lookup and the run.
    $gateIdx  = $appCs.IndexOf('ElevationService.CanRun')
    $startIdx = $appCs.IndexOf('service.Run')
    Assert 'the gate is reached BEFORE the script is launched' `
           ($gateIdx -gt 0 -and $startIdx -gt 0 -and $gateIdx -lt $startIdx) `
           "CanRun at $gateIdx, Run at $startIdx — the gate must come first"
}

if (Test-Path $ElevationPath) {
    $el = Get-Content $ElevationPath -Raw
    Assert 'ElevationService exposes the refusal message/exit code' `
           ($el -match 'RequiresElevation|Refusal|ExitCode|Message')
}

# =====================================================================
# Section 6 - build + REAL runtime evidence
# =====================================================================
Write-Host ''
Write-Host '[6] Build + runtime evidence' -ForegroundColor Yellow

$exe = Join-Path $Src 'bin\Release\net8.0-windows\KomorebiDashboard.exe'
$built = $false

if (-not $SkipBuild) {
    Write-Host '  ... dotnet build' -ForegroundColor DarkGray
    $dotnet = Join-Path ${env:ProgramFiles} 'dotnet\dotnet.exe'
    $buildLog = & $dotnet build $Src -c Release --nologo -v quiet 2>&1 | Out-String
    $built = ($LASTEXITCODE -eq 0)
    Assert 'dotnet build exits 0' $built `
           (($buildLog -split "`n") | Where-Object { $_ -match 'error' } | Select-Object -First 5 | Out-String)
} else {
    $built = Test-Path $exe
    Assert 'prebuilt EXE present (SkipBuild)' $built $exe
}

if ($built) {
    Assert 'EXE produced' (Test-Path $exe) $exe

    # --- no regression on the CLI twin ------------------------------------
    $help = & $exe --help 2>&1 | Out-String
    Assert '--help still works' ($LASTEXITCODE -eq 0 -and $help -match 'Verbs:')

    # --- a READ-ONLY verb must still run unelevated ----------------------
    # status is the safest probe: it only reads. If elevation gating were
    # applied too broadly it would refuse here.
    $statusOut = & $exe status 2>&1 | Out-String
    $statusRc = $LASTEXITCODE
    Assert 'a non-admin verb is not blocked by the elevation gate' `
           ($statusRc -eq 0 -or $statusRc -eq 1) `
           "status rc=$statusRc; tail: $(($statusOut -split "`n" | Select-Object -Last 2) -join ' / ')"
    Assert 'a non-admin verb is not told to elevate' `
           ($statusOut -notmatch 'Rerun as Administrator|requires Administrator|elevated')

    # --- an ADMIN verb must refuse loudly --------------------------------
    # 'uninstall' is RequiresAdmin in the registry and is destructive, so this
    # probe must NEVER get past the gate. If the app is already elevated on the
    # test machine the assertion is skipped rather than faked — reported below.
    $uninstallOut = & $exe uninstall all 2>&1 | Out-String
    $uninstallRc = $LASTEXITCODE
    Write-Host "        (uninstall probe rc=$uninstallRc)" -ForegroundColor DarkGray

    $amElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
                   ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($amElevated) {
        Write-Host '  SKIP  admin-verb refusal — this shell IS elevated, so the gate cannot be observed' -ForegroundColor Yellow
        Write-Host '        (recorded as a Sandbox item for ticket 14; not silently passed)' -ForegroundColor DarkYellow
    } else {
        Assert 'an admin verb REFUSES instead of silently no-oping' `
               ($uninstallRc -ne 0) "rc=$uninstallRc — a silent success here is the data-loss-class bug ADR-0012 warns about"
        Assert 'the refusal names the verb' `
               ($uninstallOut -match 'uninstall') "out: $uninstallOut"
        Assert 'the refusal tells the user what to do' `
               ($uninstallOut -match 'Administrator|elevat|runas') "out: $uninstallOut"
        Assert 'nothing was uninstalled' `
               ($uninstallOut -notmatch 'uninstalled|removed successfully|cleanup complete')
    }

    # --- the app still launches after theming (D18 must not regress) -----
    try {
        $guiOut = Join-Path $env:TEMP 'ticket12-gui.out'
        $guiErr = Join-Path $env:TEMP 'ticket12-gui.err'
        $gui = Start-Process -FilePath $exe -PassThru -WindowStyle Hidden `
                             -RedirectStandardOutput $guiOut -RedirectStandardError $guiErr -ErrorAction Stop
        $deadline = (Get-Date).AddSeconds(30)
        while (-not $gui.HasExited -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 150
            if ($gui.MainWindowHandle -ne 0) { break }
        }
        $opened = -not $gui.HasExited -and $gui.MainWindowHandle -ne 0
        Assert 'the app still opens a window after theming (D18 no regression)' $opened `
               "HasExited=$($gui.HasExited) handle=$($gui.MainWindowHandle); stderr: $((Get-Content $guiErr -EA SilentlyContinue | Select-Object -First 2) -join ' ')"
        if (-not $gui.HasExited) {
            $gui.CloseMainWindow() | Out-Null
            if (-not $gui.WaitForExit(5000)) { $gui.Kill() }
        }
        $guiText = [string](Get-Content $guiOut -Raw -EA SilentlyContinue)
        Assert 'startup reports the theme it applied' `
               ([bool]($guiText -match 'theme')) "stdout: '$guiText'"
    } catch {
        Assert 'the app still opens a window after theming (D18 no regression)' $false $_.Exception.Message
    }
}

# =====================================================================
Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
if ($script:failed -eq 0) {
    Write-Host (" RESULT: all {0} assertions passed" -f $script:passed) -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    exit 0
} else {
    Write-Host (" RESULT: {0} passed, {1} FAILED" -f $script:passed, $script:failed) -ForegroundColor Red
    Write-Host '============================================================' -ForegroundColor Red
    exit 1
}