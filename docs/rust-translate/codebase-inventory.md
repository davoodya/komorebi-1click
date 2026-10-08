# komorebi-1click — C# WPF Codebase Inventory (source of truth for the Rust + Tauri rewrite)

**Purpose:** every file that must be understood, translated, replaced or deliberately dropped.
Read this before writing `spec.md`, so the specification covers the real code and not a summary of it.

**Measured:** 2026-10-08 · 53 source files · **~6,300 lines** (excluding `obj/`, `bin/`).
Location: `/mnt/h/Repo/komorebi-1click/src/KomorebiDashboard` = `H:\Repo\komorebi-1click\src\KomorebiDashboard`

---

## 1. Architecture as built (three tiers, script-first)

```
Views (zero logic)  →  ViewModels (one per tab)  →  ScriptService (only process-aware layer)
                                                          ↓
                                                   VerbRegistry (single table)
                                                          ↓
                                                   PowerShell scripts/*.ps1 (62 files)
```

Governing invariant (ADR-0009 / ADR-0015): **the Dashboard owns NO system-management logic.**
Every button resolves a verb through the registry and runs an existing `.ps1`. The GUI and the CLI
twin are the same executable and dispatch through the same code path (ADR-0013).

---

## 2. File inventory by tier

### 2.1 Backend / Services — 1,413 lines

| File | Lines | Role | Rust + Tauri destination |
|---|---:|---|---|
| `Services/ThemeService.cs` | 530 | Theme, 8-swatch accent palette + custom HEX, app typography, console typography, UI scale, `K1c*` brush publication, full-window repaint walk | **Split.** Palette + hex + scheme state → Rust `theme.rs` (state of record). Brush application → frontend CSS variables. The visual-tree invalidation walk has no Tauri equivalent and is deleted. |
| `Services/SettingsStore.cs` | 303 | `DashboardSettings` POCO, defaults, `Normalize` clamping, atomic tmp-then-rename save, corrupt-file quarantine, `Toggles`/`AhkScriptStates` maps, `Changed` event | Rust `settings.rs` — serde JSON at `dirs::data_dir()/KomorebiDashboard/settings.json`. Same defaults, same clamps, same quarantine behaviour. |
| `Services/ScriptService.cs` | 286 | The ONLY process layer: verb → script path → `pwsh.exe`/`powershell.exe` with `-NoProfile -ExecutionPolicy Bypass -File`, fixed args then user args, stdout/stderr capture, cancellation, 300 s default timeout, **process-tree kill**, structured `ScriptResult` | Rust `scripts.rs` — `tokio::process::Command`, `kill_on_drop` + Windows Job Object (or `taskkill /F /T`) for tree kill, `CancellationToken`, `tokio::time::timeout`. |
| `Services/VerbRegistry.cs` | 188 | **The single table**: 28 verbs, tab assignment, script, argument shape, `RequiresAdmin`, `FixedArguments`, `RenderInGui`, labels, hints, `NumericOnly`, plus `--help` generation | Rust `registry.rs` — a `static [VerbDefinition; 28]` (or `LazyLock`), serde-serializable so the frontend fetches it over IPC. `build_help()` generated, never hand-written. |
| `Services/ElevationService.cs` | 151 | `IsElevated` (Windows token), `CanRun(verb)`, CLI refusal message (exit **740**), `BuildElevationPrompt()` generated from `RequiresAdmin`, `RelaunchElevated()` via `runas`, UAC-cancel (1223) handled as a choice not a failure | Rust `elevation.rs` — `windows-sys`: `OpenProcessToken` + `TokenElevation`, `ShellExecuteExW` with `runas`. |
| `Services/FontCatalog.cs` | 129 | Two-tier font list: fixed standard faces (cheap) vs full enumeration (expensive, cached, off-thread, sentinel entry) | Rust `fonts.rs` — Windows font enumeration via `directwrite`/registry `HKLM\...\Fonts`, or drop tier 2. See Open Question Q6. |
| `Services/AhkScriptCatalog.cs` | 110 | Transcribed installer manifest (3 scripts) + `ahk-state.json` read, repo-root derivation | Rust `ahk.rs` — same manifest table, same state-file read. |
| `Services/ScriptsLocator.cs` | 77 | Walks up from the exe to find `scripts/` marked by `kill-all.ps1`, `MaxDepth=10`, shipped layout checked first, non-existent fallback on purpose | Rust `locate.rs` — identical algorithm. |
| `Services/CommandLineParser.cs` | 74 | First token = verb, rest forwarded; `ahk enable/disable <name>` folded onto its row; bare verb whose shape contains `<` → help | Rust in `main.rs` (clap or hand-rolled parser preserving these exact rules). |

### 2.2 Models — 205 lines

| File | Lines | Role | Rust destination |
|---|---:|---|---|
| `Models/VerbDefinition.cs` | 84 | Immutable record + computed `Usage`, `AcceptsUserArguments` (derives from `<`/`[`), `IsNumeric` | `#[derive(Serialize)] struct VerbDefinition` + `impl` for the computed fields. |
| `Models/VerbRow.cs` | 76 | Per-row user-typed value wrapper; **numeric filtering happens here, not in the view** (covers paste/IME/drag-drop) | Frontend row state with the same filter rule (value-level, not keydown-level). |
| `Models/ScriptResult.cs` | 45 | `ExitCode, Output, Duration, Verb, StandardError, Cancelled, TimedOut` + `Succeeded`, `Interrupted`, `Summary` | `#[derive(Serialize)] struct ScriptResult` — same fields, same `Summary` wording. |

### 2.3 ViewModels — 1,141 lines

| File | Lines | Role | Rust / frontend destination |
|---|---:|---|---|
| `ViewModels/TabViewModelBase.cs` | 489 | **The no-lag contract.** 50 ms flush interval, lock-guarded pending buffer, **ONE dispatcher hop per flush** (never per line), 200,000-char cap trimmed on a line boundary, per-run `CancellationTokenSource`, elevation gate before launch, `OnVerbCompleted` hook, `SplitArguments` (quote-aware), global `RefreshConsoleShare`/`PersistConsoleShare` over weak references | Frontend store + Rust command. The batching rule must be preserved: lines accumulate in the backend, one `event` emit per ~50 ms carrying the whole batch. |
| `ViewModels/CustomizationViewModel.cs` | 454 | Preview-now / persist-on-Apply; sentinel handling for accent + two font lists; accent-sync loop guard (`_syncingAccent`); console share live push | Frontend component + settings IPC. |
| `ViewModels/AutoHotkeyViewModel.cs` | 265 | `AhkScriptRow` (applied vs pending selection, dirty tracking), **serial** Apply (three scripts rewrite one `AppRunner.vbs`), stop-at-first-failure, state re-read in `OnVerbCompleted` | Frontend + Rust command. Serial order is load-bearing. |
| `ViewModels/AboutViewModel.cs` | 145 | Version (informational first), exe path, scripts path, settings path, runtime desc, URL/clipboard/explorer commands | Rust `about.rs` command returning a struct. |
| `ViewModels/SettingsViewModel.cs` | 129 | Rows sliced from the registry, Factory Reset (confirm → defaults → theme/typography/scale), Open Settings Folder | Frontend + 2 Rust commands. |
| `ViewModels/KillStartViewModel.cs` | 16 | Thin: registry tab + one-line description | Frontend, no backend. |
| `ViewModels/RestartViewModel.cs` | 16 | same | same |
| `ViewModels/DebuggingViewModel.cs` | 16 | same | same |
| `ViewModels/UninstallViewModel.cs` | 16 | same + description | same |

### 2.4 Views / XAML — ~1,900 lines (see §4 for what does not translate)

| File | Lines | Role |
|---|---:|---|
| `App.xaml` | 438 | **The whole visual system**: 21 `K1c*` resource keys (typography, row scaffolding, 5 button variants, toggle switch, value box, grip, console, verb-row DataTemplate, tab strip template) + 3 converters. No literal colors — every brush is a `DynamicResource`. |
| `Views/CustomizationView.xaml` | 246 | Accent swatches, theme toggle, font combos, sliders, Apply/Reset |
| `Views/AboutView.xaml` | 132 | Identity, paths, author links |
| `Views/ColorPickerDialog.xaml(.cs)` | 230 | RGB/Hex picker, returns `Color` |
| `Views/ConsolePane.xaml(.cs)` | 218 | Auto-scroll **only when the reader is at the end** (18 px threshold), drag-to-resize grip writing 10–60 % back to settings |
| `Views/SettingsView.xaml` | 107 | Registry-sliced rows + hand-written Settings file / Ignore Dashboard / Factory Reset / Cancel rows |
| `Views/TabLayout.xaml(.cs)` | 183 | The shared tab body (ContentControl + ControlTemplate): heading, scrollable rows, console pane; `ShowConsole=false` opts out and pins the console row to 0 |
| `Views/AutoHotkeyView.xaml` | 84 | Script radio rows + all/diagnostic row groups |
| `Views/ConfirmDialog.xaml(.cs)` | 122 | Themed confirm (never `MessageBox` — it ignores the theme) |
| `Views/ElevationPromptWindow.xaml(.cs)` | 159 | The ADR-0012 three-button dialog (`OK / Rerun as Administrator / Cancel`), title fixed by the ADR |
| `MainWindow.xaml(.cs)` | 293 | Header (logo, version, Toggle Theme, Toggle Color), 8 tabs, eager VM construction, DWM rounded corners, `PersistAppearance`, `ConsoleWrite` to the active tab |
| `Views/{KillStart,Restart,Debugging}View.xaml` | 27 | Trivial `TabLayout` + `ItemsControl` over `Rows` |
| `Views/UninstallView.xaml` | 17 | Registry rows + a "Available scopes" note |
| `Converters/BoolToVisibilityConverter.cs` | 51 | 3 converters |

### 2.5 Entry point & project

| File | Lines | Role |
|---|---:|---|
| `App.xaml.cs` | 270 | **Dual entry**: CLI mode (verb present → `RunCliAsync` → `Shutdown(code)`, `ShutdownMode=OnExplicitShutdown`, no `AttachConsole`) vs GUI mode (load settings → apply theme → show). Crash logging installed first: writes `KomorebiDashboard.crash.log` beside the exe, walks `InnerException` chain, extracts `XamlParseException` line/position. Startup time **measured** from `Process.StartTime`, not from a static initializer. |
| `KomorebiDashboard.csproj` | 113 | `net8.0-windows`, `WinExe`, pins `CommunityToolkit.Mvvm 8.4.0` + `WPF-UI 4.3.0` (exact), publish block: `win-x64`, `SelfContained`, `PublishSingleFile`, `IncludeNativeLibrariesForSelfExtract`, `PublishReadyToRun`, `PublishTrimmed=false` (reason recorded inline), `PublishDir=..\..\releases\` |

---

## 3. Behaviour that must survive the rewrite (a checklist, not prose)

These are the parts that are invisible in a screenshot and are exactly what a rewrite breaks.

1. **One dispatcher hop per flush, never per line.** 50 ms batch window; 10,000 lines cost the UI the
   same handful of updates as 10.
2. **Process-tree kill on cancel AND on timeout** — killing only the direct child leaves grandchildren
   holding the pipe handles, so the "cancelled" run still hangs the UI.
3. **Cancellation vs timeout are different facts** and are reported differently
   (`TIMED OUT after 3.1s` vs `cancelled after 1.2s`).
4. **Elevation gate is checked BEFORE the process starts**, and the gate's position is asserted by a
   test, because a gate after launch is worse than no gate.
5. **CLI exit code 740** (`ERROR_ELEVATION_REQUIRED`) for a missing privilege; 2 for a parse error;
   the script's own exit code otherwise. Ctrl+C cancels the child rather than orphaning it.
6. **`FixedArguments` come before user arguments** (PowerShell takes the last occurrence of a
   parameter).
7. **Argument order `-Name` before `-State`** for `ahk-script.ps1` — PowerShell binds positionally in
   declaration order and `-State` has a `ValidateSet`.
8. **Numeric filtering happens on the value, not on the keystroke** (paste, IME, drag-drop).
9. **Settings: defaults live on the type**; every field has one so an old file upgrades silently;
   atomic tmp-then-rename; a corrupt file is **moved aside**, never overwritten; values are clamped
   on load and before save.
10. **The console share is global** (one `ConsolePercent`, applied to every tab) and clamped 10–60 %.
11. **AHK Apply is serial and stops at the first failure** — three scripts rewrite one
    `AppRunner.vbs`.
12. **Sentinels are actions, not values** (`Custom...`, `Custom (All Fonts)...`) and must never stay
    selected; the accent sync has an explicit loop guard.
13. **Auto-scroll only when the reader is at the end** of the console.
14. **Output cap 200,000 chars, trimmed on a line boundary.**
15. **Read-only verbs are badged** so a diagnostic is never mistaken for an action.
16. **A missing script is a result, not an exception** (exit 127 with the offending path shown).
17. **Registry rows are the only source for help text, labels and elevation requirements** — the
    dialog message and the `--help` output are generated, so they cannot go stale.
18. **`ignore-dashboard` writes a real `komorebi.json` `ignore_rules` entry for the executable name** —
    this must be re-pointed at the new binary name (see Open Question Q3).

---

## 4. What does NOT translate (delete, do not port)

| WPF-specific thing | Why it dies |
|---|---|
| `Dispatcher`, `Dispatcher.BeginInvoke`, `DispatcherPriority` | Replaced by one Tauri event emit per flush |
| `WeakReference` list for `RefreshConsoleShare` | Replaced by a single frontend store: one `ConsolePercent`, every tab reads it |
| `ThemeService.RepaintAllWindows` + `InvalidateProperty` walk | CSS variables re-resolve natively; no tree walk needed |
| `K1c*` `DynamicResource` brush publication | CSS custom properties set on `:root` |
| The D21 history (no `FluentWindow`, no Mica/Acrylic, `WindowBackdropType.None`) | Tauri/Webview2 owns compositing. **Do not** adopt `window-vibrancy` unconditionally — bugs-fixing.md §2.1 says effects must be conditional with graceful fallback. |
| `Pack URI` / `App.g.cs` entry-point constraints / `XamlParseException` line capture | Tauri assets are normal frontend paths; Rust panics go to a log |
| `ColorPickerDialog` returning `System.Windows.Media.Color` | Frontend color picker |
| `ConfirmDialog` because `MessageBox` ignores the theme | Web dialogs are themed by construction — but the **three-button elevation dialog stays** because the ADR fixes its title and labels |
| The 175 MB publish flag block | Replaced by `tauri build` MSI/NSIS + a single portable `.exe` |

---

## 5. Assets and consumers outside `src/`

- `scripts/` — **62 PowerShell files**. Untouched by this rewrite. They are the contract.
- `releases/KomorebiDashboard.exe` — 170,176,020 bytes, the current shipping artefact.
- `releases/rust/` — **exists and is empty**; the natural landing place for the Rust build output.
- `tests/*.tests.ps1` — 12+ suites. The dashboard ones (`ticket10`, `ticket11`, `ticket12-runtime`,
  `ticket12-theme-elevation`, `ticket13-publish`, `ticket15-shell-resources`) **statically scan the C#
  source** for the contracts in §3. A Rust rewrite either needs translated assertions or the loss of
  that regression net must be accepted explicitly. See Open Question Q5.
- `autohotkey/ahk-state.json`, `config/whkdrc` — read/written only through scripts; no direct touch.
- The installer (`Install.ps1`) and `ignore-dashboard.ps1` reference the executable **by name**.
