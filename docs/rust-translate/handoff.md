# komorebi-1click: Handoff & Translation Strategy (Rust + Tauri)

> **This file is the continuation point for the next agent.** Read sections 6–8 first; sections 1–5
> are background. Last updated: **2026-10-08, after the Ticket stage.**

---

## 1. Project Background & Baseline State

Up to Session 4, the `komorebi-1click` Admin Dashboard was built using C# (.NET 8.0 Windows) and
`WPF-UI 4.3.0`. While functionally complete and verified:
- The compiled self-contained single-file binary is relatively heavy (~162–170 MB due to bundled CLR +
  ReadyToRun WPF dependencies).
- Memory consumption sits around 60–120 MB; time-to-live-window measured ~553 ms.
- WPF-UI's native Windows backdrops (Mica/Acrylic) caused rendering and driver incompatibilities on
  various setups (Defect D21).
- XAML styling faults escape the compiler and surface only at render, which is how D21 happened.
- Cross-platform tooling and modern web-based UI styling (Tailwind CSS, animations,
  micro-interactions) are cumbersome in XAML.

### Target Architecture: Rust + Tauri v2
Rewriting the Admin Dashboard into **Rust + Tauri** achieves:
1. **Ultra-lightweight footprint**: Binary size ~10–18 MB (over 90% reduction).
2. **Minimal memory footprint**: Typical RAM usage under 30–45 MB.
3. **Instant Startup**: Zero CLR cold-start latency; native execution.
4. **Modern UI Aesthetics**: High-DPI crisp styling using modern web standards (Tailwind, Lucide
   icons, Fluent-inspired design) without XAML template hazards.
5. **Rock-solid Concurrency**: Rust `tokio` asynchronous runtime with zero-cost memory safety,
   guaranteed process-tree termination, and strict type safety.

---

## 2. Comprehensive Inventory of Current C# Codebase

The C# codebase in `/mnt/h/Repo/komorebi-1click/src/KomorebiDashboard` consists of:

### 2.1 Backend / Services
1. `App.xaml.cs`: Dual entry-point logic (CLI mode vs GUI mode), crash logging initialization,
   command-line argument dispatching.
2. `Services/VerbRegistry.cs`: The central dictionary defining all 28 verbs, tab assignments,
   descriptions, script paths, admin requirements, and CLI help generator.
3. `Services/ScriptService.cs`: Asynchronous process manager; resolves `pwsh.exe`/`powershell.exe`,
   sets `-ExecutionPolicy Bypass -NoProfile`, streams stdout/stderr, handles cancellation and
   process-tree termination.
4. `Services/SettingsStore.cs`: JSON serialization and management of
   `%APPDATA%\KomorebiDashboard\settings.json`.
5. `Services/ThemeService.cs`: Theme (Dark/Light) and 8-accent color palette management.
6. `Services/FontCatalog.cs`: Enumeration of installed system fonts (tiered: fast monospaced standard
   vs full list).
7. `Services/AhkScriptCatalog.cs`: Parser and state manager for AutoHotkey scripts
   (`ahk-state.json` & `AppRunner.vbs`).
8. `Services/ElevationService.cs`: Token elevation probe (`OpenProcess 0x1000`) and elevated
   relauncher (`runas`).

### 2.2 ViewModels & Models
1. `Models/VerbDefinition.cs`: Immutable record defining an action/verb.
2. `Models/VerbRow.cs`: Mutable UI row model holding current parameter values.
3. `Models/ScriptResult.cs`: Structured execution outcome (ExitCode, Output, Duration, TimedOut,
   Cancelled).
4. `ViewModels/TabViewModelBase.cs`: Base ViewModel providing console output buffering, status lines,
   and execution commands.
5. `ViewModels/KillStartViewModel.cs`, `RestartViewModel.cs`, `SettingsViewModel.cs`,
   `CustomizationViewModel.cs`, `AutoHotkeyViewModel.cs`, `DebuggingViewModel.cs`,
   `UninstallViewModel.cs`, `AboutViewModel.cs`.

### 2.3 Views & Controls
1. `MainWindow.xaml`: Main chrome, logo, title, theme toggle, accent toggle, tab container.
2. `Views/TabLayout.xaml`: Standardized template for tabs (header, scrollable rows, console pane slot).
3. `Views/ConsolePane.xaml`: Standardized console pane with drag-to-resize grip, Clear button, and
   status indicator.
4. `Views/ColorPickerDialog.xaml`: Custom RGB/Hex color picker dialog.
5. `Views/ConfirmDialog.xaml`: Modal dialog for dangerous operations (Uninstall, Cleanup, Factory
   Reset).
6. Individual views for each tab.

> A per-file, line-counted map of every source file to its Rust/TypeScript destination lives in
> `codebase-inventory.md` (this directory). Read it before touching code.

---

## 3. Mapping C# Concepts to Rust + Tauri Architecture

**Stack is now decided — see `spec/ADR-0017-rust-tauri-dashboard.md`.**

| C# WPF Concept | Rust + Tauri Architecture |
|---|---|
| `App.xaml.cs` (Dual CLI/GUI) | Rust `main.rs`: args present → headless CLI + exit; no args → Tauri webview |
| `Services/VerbRegistry.cs` | Rust `registry.rs`: single table of the 28 verbs, feeds rows, CLI, `--help`, elevation dialog |
| `Services/ScriptService.cs` | Rust `scripts.rs`: `tokio::process`, ~50 ms batching, cancel vs timeout, process-tree kill |
| `Services/SettingsStore.cs` | Rust `settings.rs`: serde JSON at the app-data dir, defaults on the type, atomic save, quarantine |
| `Services/ElevationService.cs` | Rust `elevation.rs`: token probe + `ShellExecuteExW` `runas` |
| `Services/FontCatalog.cs` | Rust `fonts.rs`: tiered enumeration, cached, off-thread sentinel trigger |
| `Services/AhkScriptCatalog.cs` | Rust `ahk.rs`: manifest metadata + on-disk state + staging |
| `Services/ThemeService.cs` | Frontend: CSS custom properties (dark/light + 8 accents + custom hex), no literal colours |
| ViewModels & data binding | Svelte 5 stores + Tauri `invoke`/`emit` over a narrow IPC contract |
| `MainWindow.xaml` / `TabLayout.xaml` | Header + tab shell + shared row component (Svelte) |
| `ConsolePane.xaml` | Reusable console component: splitter, autoscroll-at-end, 200k cap, global share |
| `ColorPickerDialog` / `ConfirmDialog` | Small hand-built Svelte dialogs |

**Locked decisions:** Svelte 5 + TypeScript + Vite · **Tailwind CSS** · **Lucide Icons** ·
**hand-built components (no component library)** · `tokio` · `windows-sys`/`windows` · English-only
shipped text · no component library.

---

## 4. Work Breakdown & Phase Status

| Phase | State | Where |
|---|---|---|
| 1 — Specification (`spec.md`, ADR-0017) | ✅ **done 2026-10-08** | `spec/spec.md`, `spec/ADR-0017-…` |
| 2 — Tickets (`tickets/`) | ✅ **done 2026-10-08** | `tickets/NN-*.md` (13 tickets) |
| 3 — Implementation by coding agent | ⏳ **not started** | consumes `tickets/` one by one |

---

## 5. Current State (what exists on disk right now)

**Publish tree — `H:\Repo\komorebi-1click\docs\rust-translate\`:**

| File | Lines | What it is |
|---|---:|---|
| `handoff.md` | this file | continuation point for the next agent |
| `knowledges.md` | ~200 | 28 verbs / 8 tabs, invariants, host facts — read before coding |
| `bugs-fixing.md` | ~200 | defects that must not return (D21, WHKD panic, UIPI, …) |
| `codebase-inventory.md` | 158 | per-file C# → Rust map, 17 behaviours that must survive |
| `environment.md` | ~165 | toolchain probe, WSL guard bypass, build strategy |
| `roadmap.md` | 154 | phases, risk register, definition of done |
| `spec/spec.md` | 456 | **the specification** (84 user stories, IPC contract, seams) |
| `spec/ADR-0017-rust-tauri-dashboard.md` | 107 | the architectural decision record |
| `spec/tickets-draft.md` | ~135 | approved breakdown summary + blocking graph |
| `spec/README.md` | ~45 | index of the spec stage |
| `tickets/01…13-*.md` | — | **the 13 implementation tickets** |

**Dev tree — `~/projects/komorebi-1click/`:**
- `.scratch/rust-translate/spec.md` — tracker spec, `Status: ready-for-agent`, byte-identical to
  `spec/spec.md`.
- `.scratch/rust-translate/issues/NN-*.md` — the same 13 tickets, byte-identical to `tickets/`.
- `docs/adr/` — ADR 0001–0016 (unchanged). ADR-0017 lives in the spec stage folder; promote it to
  `docs/adr/` when this effort merges into the main doc tree.
- `tests/` — the existing PowerShell suites (**do not delete them**; their load-bearing assertions
  must be re-expressed as external-behaviour tests, ticket 13).

**No code has been written yet.** `releases/rust/` does not exist yet. Nothing in `scripts/`,
`tests/`, `src/`, `Install.ps1` or `docs/adr/` was modified by the planning sessions (verified by
mtime).

**Stage log (append here after every stage):**

- **2026-10-08 — Ticket stage complete.** 13 tickets written to `tickets/` and mirrored
  byte-identically to `.scratch/rust-translate/issues/`. Verified programmatically: every ticket is
  `Status: ready-for-agent`; only ticket **01** has no blockers; every blocker resolves to an earlier
  ticket; the graph is acyclic; topological order equals `01 … 13`. `environment.md` updated —
  `tauri-cli 2.12.1` is installed on both Windows and WSL, and the build-host ruling is *develop on
  Windows*. Nothing under `scripts/`, `tests/` or `src/` was touched.
- **2026-10-08 — Spec stage complete.** `spec/spec.md` (456 lines, 84 user stories),
  `spec/ADR-0017-rust-tauri-dashboard.md`, `spec/README.md`; tracker copy at
  `.scratch/rust-translate/spec.md` with `Status: ready-for-agent`.

---

## 6. Decisions locked by Davood (binding)

1. **Frontend:** Svelte 5 + Tailwind CSS + Lucide Icons; **hand-built components**, no library.
2. **Output:** one single EXE at `H:\Repo\komorebi-1click\releases\rust\`.
3. **Executable name stays `KomorebiDashboard.exe`** so `ignore-dashboard`, shortcuts and docs keep
   working — therefore **zero changes to the 62 `.ps1` scripts**.
4. **Identity assets:** `src\KomorebiDashboard\Resources\logo.ico` for app icon, window icon, favicon
   and the About image.
5. **Priority order (ADR-0015, unchanged):** maximum speed → lag near zero → smoothness → modern
   beautiful UI. Lower never trades against higher.
6. **Feature parity:** everything the WPF build does, plus optimized versions of it.
7. **Test strategy:** hybrid — `cargo test` for platform-independent logic, runtime probes for
   streaming/elevation/size/startup, **CLI twin as the primary seam**.
8. **Documents** for this effort live on the publish side only; dev tree gets the tracker files.
9. **Development happens on Windows**, not WSL (no WSL2/WSLg constraints).

## 7. Environment facts (verified 2026-10-08)

- **`tauri-cli 2.12.1` is installed on BOTH Windows and WSL** — `cargo tauri --version` → `tauri-cli 2.12.1`.
  Prefer the **Windows** one.
- Windows toolchain ready: `cargo 1.95` MSVC, target `x86_64-pc-windows-msvc`, VS 18 Enterprise
  (for `link.exe`), WebView2 154.x, node v24.
- WSL→Windows access needs `export ALLOW_WINDOWS=1` (see `~/.hermes/scripts/mnt-guard.sh`); binaries
  run through `~/.hermes/scripts/win-exec.sh`. Details in the `wsl-isolation` skill.
- WSL has `cargo-tauri` too, but Windows-side builds are preferred.

## 8. What the next agent should do

1. Take **ticket 01** from `tickets/` — it is the only ticket with no blockers.
2. Read `spec/spec.md` (contract) + `spec/ADR-0017-…` (decisions) + `knowledges.md` (domain) +
   `codebase-inventory.md` (what to translate) **before writing code**.
3. Work one ticket at a time; check off its acceptance criteria; do not start a ticket whose
   "Blocked by" is unsatisfied.
4. After **each ticket**: add its safe tests to `~/projects/komorebi-1click/tests/` per
   `tests/TESTING.md`, and append a dated line to §5 of this handoff so an interrupted session can
   resume. Risky/VM tests stay in the tests directory and run only after all tickets are done.
5. Ticket 12 produces the deliverable EXE; ticket 13 closes the definition of done in `roadmap.md`.

---
