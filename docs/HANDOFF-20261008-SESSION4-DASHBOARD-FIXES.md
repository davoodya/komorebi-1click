# HANDOFF — Session 4: Dashboard fix pass (buttons, console, About, ignore rule)

**Date:** 2026-10-08
**Repo:** `H:\Repo\komorebi-1click` (publish tree — source of truth)
**Baseline commit:** `fe4f8ed` (the build the user reported as "nothing shipped")
**Status:** all requested items implemented, built, published, and verified at runtime

---

## 1. Why the previous session appeared to ship nothing

The prior session's edits were real but **never published**. Two compounding
causes:

1. No `dotnet publish` was run, so `releases/KomorebiDashboard.exe` was still the
   `fe4f8ed` build. Source changes do not reach that file by themselves.
2. The working tree was **left broken**: `SettingsView.xaml` had a `Border`
   opening tag removed at line 89, so the XAML was not well-formed. 

The lesson applied here: the deliverable is the verified EXE, not the source
diff. Every change in this session ends at a run of the published binary.

---

## 2. What was implemented

### 2.1 Button appearance and naming
- `ActionLabel` on `VerbDefinition` gives every registry row its own verb-named
  button ("Export", "Import", "Enable", "Disable", "Add Rule", ...). No button
  in a generated row says "Run" any more — the label comes from the registry, so
  it cannot drift from the verb.
- Modern `ui:Button` styling (`K1cRunButton`, `K1cSecondaryButton`) that
  re-resolves on theme change and follows the accent.

### 2.2 Console
- **Default size up ~35%**: `DashboardSettings.DefaultConsolePercent` is now 35
  (was 25).
- **Console Font Family** and **Console Font Size** rows added to Customization.
  The family list is **monospaced-only** (`FontCatalog.Monospaced`), because a
  proportional face makes script output columns drift.
- **Console resize** by drag grip (`ConsolePane.OnResizeStart/Move/End`), which
  persists once at the end of the drag rather than per mouse-move.
- **Console hidden on Customization and About** via `TabLayout.ShowConsole`
  (see §3).

### 2.3 Console Pane Height — the reported bug
Symptom: moving the slider changed nothing on screen.

Cause: the setting was **read only at ViewModel construction**, so a change was
stored and every already-open tab kept its old star weight until the next
launch.

Fix: `TabViewModelBase.RefreshConsoleShare(percent)` sweeps a weak-reference list
of every live tab and re-applies the share. Both sliders (and the drag grip) now
go through it.

Also, as requested, the row now exists **only in Customization** — it was removed
from Settings along with the now-dead `SettingsViewModel.ConsolePercent`.

### 2.4 Factory Reset
Removed from the header; it lives only in Settings. The dead
`MainWindow.OnFactoryReset` handler was deleted too.

### 2.5 Accent color
- **Toggle Color** button in the header, next to Toggle Theme, cycling the
  palettes (`ThemeService.CycleAccent`).
- **Custom** entry in the Customization accent list, plus an explicit
  **Custom Color** button, both opening `ColorPickerDialog`.
  `ColorPickerDialog` is built from primitives: **WPF-UI 4.3.0's
  `ColorPicker` exposes neither a color property nor an event** (verified by
  reflection), so using it would have produced a dead dialog.
- The header's gradient is driven by the accent, so the accent is visible in the
  window chrome rather than only in the content.

### 2.6 Icon
`Resources/logo.ico` is both the application icon (taskbar, Explorer) and the
window icon (title bar / Alt-Tab).

### 2.7 About tab
New tab: logo, product name and description, version, executable and scripts
paths, author, and clickable GitHub + website links. Layout is logo left,
description right. `ShowConsole="False"`.

### 2.8 Ignore KomorebiDashboard
- New verb `ignore-dashboard` → `scripts/ignore-dashboard.ps1`, which writes an
  `ignore_rules` entry for `KomorebiDashboard.exe` into `komorebi.json` and
  hot-reloads. Idempotent; preserves the file's structure.
- Surfaced in Settings as a full-width row whose explanation is **bound from the
  registry**, so the GUI text and the CLI help cannot drift.

---

## 3. The one architectural change worth knowing

`TabLayout` gained `ShowConsole`. It is handled on the control (collapse the
console element, pin its row height to 0, give the content row the full star)
rather than by a binding, because **Customization and About are not
`TabViewModelBase`** and have no `ConsoleRowHeight` to bind: the binding would
fail silently and leave the row at its default `1*`, which renders as an empty
console panel. That is exactly the "empty console on a tab that runs nothing"
the request described.

---

## 4. Verified at runtime, not from the diff

Two verification scripts were added; both drive the **real window** through UI
Automation.

`scripts/verify-console-per-tab.ps1` — starts one process **per tab** (WPF keeps
a previously-selected tab realized, so walking tabs in one process reports false
positives), selects the tab, and checks for the console's Clear button and any
Edit control:

```
Kill and Start         want=console  PASS
Restart and Reloading  want=console  PASS
Settings               want=console  PASS
Customization          want=none     PASS
AutoHotkey Scripts     want=console  PASS
Debugging              want=console  PASS
Uninstall and Cleanup  want=console  PASS
About                  want=none     PASS
failures: 0
```

`scripts/verify-console.ps1` — proves the height slider moves the console in
another tab, which is the exact bug reported:

```
console top at 10%  = 495
console top at 60%  = -97
height change moves console = True
```

Both scripts were run against `releases/KomorebiDashboard.exe`, not the source
tree.

### Test suites

| Suite | Result |
|---|---|
| ticket10-dashboard-shell | 155 passed, 0 failed |
| ticket12-theme-elevation | 48 passed |
| ticket15-shell-resources | 12 passed, 0 failed |
| ticket11-threading | 67 passed |
| ticket12-runtime | 16 passed, 0 failed |
| ticket13-runtime | 24 passed |
| ticket13-publish (full, with publish) | 16 passed, 0 skipped |
| ticket05-06-07 | 0 failures |
| ticket08-ahk | 17 passed |
| ticket09-exe-wrapper | 26 passed, 0 failed |
| ticket-monitor | 12 passed |

### A real XAML fault found and fixed

The first published build **crashed on launch** (`0xE0434352`) with
`XamlParseException: Type 'Setter' cannot be initialized from text`. The cause
was a `Setter Property="InputScope"` inside a `DataTrigger`. A fault inside a
template is **deferred to the moment the template is instantiated**, so it is
invisible to the compiler and to every static check — only launching the binary
finds it.

Crash logging (`KomorebiDashboard.crash.log` beside the executable, installed
before startup in `App.xaml.cs`) was added as part of fixing this; it reports the
exception, its inner exceptions, and the XAML line/position when available.

---

## 5. Honest limitations

- **No automated assertion covers the new UI behaviour yet.** The verification is
  the two `scripts/verify-console*.ps1` runs above; folding their checks into a
  `tests/ticket*.tests.ps1` suite is the obvious follow-up.
- **The `ignore-dashboard` rule has not been applied to the live machine.** It
  was exercised against a copy of the config with `-DryRun` only. Applying it is
  a one-time action for the multi-monitor host, and it is the user's call.
- **Console Font Family has no "full list" expansion off the standard
  monospaced set** in this build; the app typeface row has one. Adding it is a
  small follow-up, and the sentinel is already wired in the ViewModel.
- The EXE is 162.3 MB (self-contained + R2R, untrimmed by design; WPF is not
  trim-safe). Unchanged from before.

---

## 6. Reproduce

```powershell
# build + publish
dotnet publish src\KomorebiDashboard\KomorebiDashboard.csproj `
  -c Release -r win-x64 --self-contained true

# runtime verification
pwsh -File scripts\verify-console-per-tab.ps1 `
  -ExePath releases\KomorebiDashboard.exe
pwsh -File scripts\verify-console.ps1 `
  -ExePath releases\KomorebiDashboard.exe

# suites
pwsh -File tests\ticket10-dashboard-shell.tests.ps1
pwsh -File tests\ticket13-publish.tests.ps1
```