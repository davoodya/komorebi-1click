#Requires -Version 5.1
<#
    Ticket 12 — Dashboard theming (Rust/Tauri twin) + the elevation contract.

    WHY THIS SUITE EXISTS
      Ticket 12's original suite (ticket12-theme-elevation.tests.ps1) proves
      the WPF build: ThemeService.cs, the WPF-UI dictionary swap, the dialog in
      the WPF folder. This build (src\KomorebiDashboardRust) is a separate shell for the same
 ticket, and it now implements the same contract: Dark/Light at runtime,
 and an elevation gate that names the specific features needing
 Administrator.

      The load-bearing assertions are the same shape as ticket 10's: not
      existence, but CONSISTENCY. The dialog's feature list must be generated
      from the registry's RequiresAdmin flags (not a hardcoded string), the
      backend's refusal message must name those same features, and the theme
      toggle must apply the exact selectors the CSS declares.

      What is deliberately NOT tested here: rendered behaviour. That is the
      vitest suite (src\tests\elevation.spec.ts, theme.spec.ts) and the cargo
      suite (tests\elevation.rs) plus the Sandbox UIA pass. This suite pins
      the shipped artifacts so a refactor cannot quietly drop the contract.

      Usage:
        pwsh -File tests\ticket12-rust-elevation.tests.ps1
      Exit codes: 0 green, 1 at least one failed.
#>
[CmdletBinding()]
param()

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
$Rust        = Join-Path $ProjectRoot 'src\KomorebiDashboardRust'
$Core        = Join-Path $Rust 'src-tauri\src\lib.rs'
$Main        = Join-Path $Rust 'src-tauri\src\main.rs'
$Registry    = Join-Path $Rust 'src-tauri\src\registry.rs'
$Css         = Join-Path $Rust 'src\app.css'
$Dialog      = Join-Path $Rust 'src\components\ElevationDialog.svelte'
$VerbRow     = Join-Path $Rust 'src\components\VerbRow.svelte'
$AppSvelte   = Join-Path $Rust 'src\App.svelte'
$ElevStore   = Join-Path $Rust 'src\lib\elevation.svelte.ts'
$ElevLib     = Join-Path $Rust 'src\lib\elevation.ts'
$ThemeLib    = Join-Path $Rust 'src\lib\theme.ts'
$ThemeStore  = Join-Path $Rust 'src\lib\theme.svelte.ts'

$coreCode   = Get-Content -Raw $Core
$mainCode   = Get-Content -Raw $Main
$dialogCode = Get-Content -Raw $Dialog
$rowCode    = Get-Content -Raw $VerbRow
$appCode    = Get-Content -Raw $AppSvelte
$storeCode  = Get-Content -Raw $ElevStore
$elevLib    = Get-Content -Raw $ElevLib
$themeLib   = Get-Content -Raw $ThemeLib
$cssCode    = Get-Content -Raw $Css

Write-Host ''
Write-Host '=== Ticket 12 (Rust twin) — theming + elevation ===' -ForegroundColor Cyan

# --- The core gate (the one seam both consumers run through) -----------------
Assert 'the gate module exists in the core lib' `
    ($coreCode -match 'pub fn elevation_gate' -and $coreCode -match 'pub const EXIT_NEEDS_ELEVATION')

Assert 'the gate decides on the flag, not on window state' `
    ($coreCode -match 'verb\.requires_admin && !elevated')

Assert 'the feature list is generated from the registry, never hardcoded' `
    ($coreCode -match 'fn admin_feature_labels' -and
     $coreCode -match 'for verb in registry::registry\(\)' -and
     $coreCode -match 'verb\.requires_admin' -and
     $coreCode -notmatch 'fn admin_feature_labels[\s\S]{0,200}vec!\[\s*"')

Assert 'the refusal is a structured result naming the way out' `
    ($coreCode -match 'pub fn needs_elevation_result' -and
     $coreCode -match 'needs Administrator and this instance is not elevated' -and
     $coreCode -match 'Rerun the dashboard as Administrator')

Assert 'the gate is wired into run() and returns before any launch' `
    ($coreCode -match 'if let ElevationGate::NeedsRelaunch[\s\S]{0,400}return needs_elevation_result')

# The platform probe is a measurement, not a guess.
Assert 'the elevation probe asks the OS for the token' `
    ($coreCode -match 'OpenProcessToken' -and $coreCode -match 'GetTokenInformation')

# --- The Tauri layer ----------------------------------------------------------
Assert 'app_info carries the elevation state' `
    ($mainCode -match '"elevated":\s*dashboard_core::is_elevated\(\)')

Assert 'relaunch_elevated launches the verb runas and exits' `
    ($mainCode -match 'fn relaunch_elevated' -and
     $mainCode -match '"runas"' -and
     $mainCode -match 'ShellExecuteW' -and
     ($mainCode -match 'std::process::exit\(0\)' -or $mainCode -match 'app_exit'))

Assert 'the relaunch command is registered in the handler' `
    ($mainCode -match 'relaunch_elevated\s*\]')

# --- The dialog (the ticket's exact wording) ---------------------------------
Assert 'the dialog file exists' (Test-Path $Dialog) $Dialog

# The title and the three buttons are ONE contract: elevation.ts holds the
# strings, the dialog renders the constants, and the WPF-era suite asserts
# the same wording against the WPF build. A dialog that renamed itself would
# be a second contract nobody knows about.
Assert 'the dialog renders the title and buttons from the shared constants' `
    ($dialogCode -match '\{ELEVATION_DIALOG_TITLE\}' -and
     $dialogCode -match '\{ELEVATION_DIALOG_BUTTONS\[0\]\}' -and
     $dialogCode -match '\{ELEVATION_DIALOG_BUTTONS\[1\]\}' -and
     $dialogCode -match '\{ELEVATION_DIALOG_BUTTONS\[2\]\}')

Assert 'the constants carry the ticket''s exact wording: title plus OK / Rerun as Administrator / Cancel' `
    ($elevLib -match "ELEVATION_DIALOG_TITLE = 'Rerun as Administrator'" -and
     $elevLib -match "'OK',\s*'Rerun as Administrator',\s*'Cancel'")

Assert 'the dialog names the features from the registry, not a generic message' `
    ($appCode -match 'features=\{adminFeatures\(registry\.verbs\)\}' -and
     $dialogCode -match '\{#each features as feature')

Assert 'the relaunch button goes through the backend, not a re-spawn hack' `
    ($dialogCode -match 'elevation\.relaunchElevated\(\)' -and
     $elevLib -notmatch 'spawn\(' -and
     $mainCode -match 'ShellExecuteW')

# --- The rows ----------------------------------------------------------------
Assert 'every administrative row carries a visible badge' `
    ($rowCode -match 'verb\.requiresAdmin' -and $rowCode -match 'badge-admin')

Assert 'the badge is not styled with the read-only accent' `
    ($cssCode -match '\.badge-admin[\s\S]{0,200}--danger' -and
     -not ($cssCode -match '\.badge-admin[\s\S]{0,120}background:\s*var\(--accent\)'))

# --- The gate in the shell ----------------------------------------------------
Assert 'the shell closes over the button instead of duplicating the gate' `
    ($storeCode -match 'request\(verb: VerbDefinition' -and
     $storeCode -match 'elevationGate\(verb\.requiresAdmin' -and
     $elevLib -match 'export function elevationGate' -and
     $elevLib -match 'export function adminFeatures')

Assert 'an administrative verb while unelevated opens the dialog instead of running' `
    ($storeCode -match "elevationGate\(verb\.requiresAdmin, this\.elevated === true\) === 'offer-relaunch'")

Assert 'the run only starts when the gate allows it' `
    ($storeCode -match 'void dispatchVerb\(verb, args\)')

# Ticket 05's contract, pinned against regression: a declined UAC returns
# cleanly (no error box in the dialog), and OK acknowledges rather than
# dispatching a verb the backend would refuse.
Assert 'a declined UAC returns cleanly — no error state in the dialog' `
    ($storeCode -match 'acknowledge\(\): void' -and
     $dialogCode -match 'elevation\.acknowledge\(\)' -and
     $dialogCode -notmatch 'relaunchError' -and
     $dialogCode -notmatch 'dialog-error')

Assert 'the gate exit code is the spec''s 740, not the installer wrapper''s 5' `
    ($coreCode -match 'EXIT_NEEDS_ELEVATION: i32 = 740' -and
     $coreCode -notmatch 'EXIT_NEEDS_ELEVATION: i32 = 5;')

Assert 'a failed elevation read retries once before the conservative answer' `
    ($storeCode -match 'attempt < 2')

# --- The theme switch ---------------------------------------------------------
Assert 'the theme lib parses, applies, and flips' `
    ($themeLib -match 'export function parseStoredTheme' -and
     $themeLib -match 'export function applyAppearance' -and
     $themeLib -match 'export function resolveTheme')

Assert 'the stored choice is remembered under one key' `
    ($themeLib -match "komorebi-dashboard-theme")

Assert 'a corrupted stored value falls back to the default instead of breaking the shell' `
    ($themeLib -match 'theme \?\? DEFAULTS\.theme' -and $themeLib -match 'accent \?\? DEFAULTS\.accent')

Assert 'the toggle lives in the header and applies both selectors' `
    ($appCode -match 'theme\.toggle\(\)' -and
     $themeLib -match 'root\.dataset\.theme = theme' -and
     $themeLib -match 'root\.dataset\.accent = accent')

Assert 'the CSS really declares both themes the toggle applies' `
    ($cssCode -match '\[data-theme="dark"\]' -and $cssCode -match '\[data-theme="light"\]')

Assert 'the elevation chip shows before a dialog can explain it' `
    ($appCode -match 'chip-warning' -and $appCode -match 'Not elevated')

# --- Report -------------------------------------------------------------------
Write-Host ''
if ($script:failed -eq 0) {
    Write-Host "ticket 12 (Rust twin): all $script:passed checks green" -ForegroundColor Green
    exit 0
}
Write-Host "ticket 12 (Rust twin): $script:failed of $($script:passed + $script:failed) FAILED" -ForegroundColor Red
exit 1
