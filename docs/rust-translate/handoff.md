# KomorebiDashboard — Rust Translation · Handoff

> **This is the single continuation document for the next agent.**
> Read sections 6–9 first; sections 1–5 are background. Last updated: **2026-10-10, after ticket 03.**

---

## 0. One-line status

Tickets `01`, `02`, `03` are **implemented and verified**. The next ticket is
**`04-eight-tabs`**. Nothing is mid-edit; the tree compiles, every suite is green,
and the only known gap is a host capability (ConPTY), not a code defect.

If your connection drops, this document alone is enough to continue.

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

## 2. Comprehensive Inventory of the C# Codebase (the thing being translated)

The C# codebase in `H:\Repo\komorebi-1click\src\KomorebiDashboard`:

### 2.1 Backend / Services
1. `App.xaml.cs`: Dual entry-point logic (CLI mode vs GUI mode), crash logging initialization,
   command-line argument dispatching.
2. `Services/VerbRegistry.cs`: The central dictionary defining all 35 verbs, tab assignments,
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
> `codebase-inventory.md` (same directory). **Read it before touching code.**

---

## 3. Mapping C# Concepts to Rust + Tauri

**Stack is decided — see `spec/ADR-0017-rust-tauri-dashboard.md`.**

| C# WPF Concept | Rust + Tauri Architecture |
|---|---|
| `App.xaml.cs` (Dual CLI/GUI) | Rust `main.rs`: args present → headless CLI + exit; no args → Tauri webview |
| `Services/VerbRegistry.cs` | Rust `registry.rs`: single table of the 35 verbs, feeds rows, CLI, `--help`, elevation dialog |
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
shipped text.

---

## 4. Ticket status

| Ticket | Status | Notes |
|---|---|---|
| `01-scaffold-first-verb` | **done**, committed, pushed | commits `b6b0a2f`, `d8d9906`, `c23ea8c` |
| `02-execution-contract` | **done**, verified | stop path, cancel-by-run-id, tree kill, timeouts; probe has dual-mode thresholds (ADR-0019) |
| `03-registry-cli-twin` | **done**, verified | registry of 35 verbs + CLI twin + US 55 wired; see §8 for the one unprovable item |
| **`04-eight-tabs`** | **next** | the real eight-tab strip; §9 tells you what is already in place |
| 05–13 | not started | 05 (elevation) is the first one with a live parity gap — see §8 |

Artefact: `releases/rust/KomorebiDashboard.exe` — **13,852,672 bytes**, debug profile.
The WPF `releases/KomorebiDashboard.exe` (170,176,020 bytes) was never touched.

**Implementation phase status:**
- Phase 1 — Specification (`spec.md`, ADR-0017) — ✅ done 2026-10-08
- Phase 2 — Tickets (`tickets/`) — ✅ done 2026-10-08 (13 tickets)
- Phase 3 — Implementation by coding agent — ⏳ **in progress** (tickets 01–03 done)

---

## 5. The registry — the single source of truth

`src/KomorebiDashboardRust/src-tauri/src/registry.rs` is the whole table:
35 verbs carrying `verb`, `script`, `arguments` (the shape string), `requires_admin`,
`help`, `tab`, `label`, `is_read_only`, `fixed_arguments`, `render_in_gui`, `hint`,
`action_label`, `numeric_only`; the 8-entry `TABS` table; and `render_help`, which
generates `--help` from the rows — grouped by tab, `[admin]` suffix, fixed-width
usage column, and the same four "Notes" lines the WPF `BuildHelp` emitted.

The table was **generated by parsing `VerbRegistry.cs`**, not hand-typed, so the
translation cannot drift from the source it replaces.

| Measure | Count (asserted by test, from the table) |
|---|---:|
| Registered verbs | **35** |
| GUI rows (`render_in_gui: true`) | 31 |
| CLI-only rows | 4 |
| Requiring Administrator | 10 |
| Read-only | 6 |
| Distinct `.ps1` files | 22 |
| Tabs carrying verbs | 6 of 8 (Customization, About are hand-built) |

The verb count is **35, not 28.** The 28 was a transcription error copied forward
instead of measured; ADR-0018 records the error and the checks that now pin the
correct number. Never re-derive the count by hand — the test
`the_documented_counts_are_the_counts_the_table_actually_has` derives it from the
table.

### Backend wiring (tickets 02–03)

* `src-tauri/src/lib.rs` — `run()` resolves through `registry::find` instead of the
  two-verb stub; `help()` is generated; two refusals are decided **before** anything
  launches; `strip_timeout_option` consumes the caller's `-TimeoutSeconds`; the
  two-part `ahk enable <key>` / `ahk disable <key>` spelling folds onto its own rows
  (ADR-0013); `execute()` now takes the budget as an explicit parameter.
* `src-tauri/src/main.rs` — `list_tabs` command; the CLI path became
  `run_cli`, which `select!`s on `tokio::signal::ctrl_c()` and calls the existing
  `request_cancel("cli")`, so the tree kill and exit 130 still come from the one
  stop path the window's Cancel button uses; `console::ensure_console` attaches the
  parent console **only** when stdout is a real terminal.

### Frontend

* `src/lib/ipc.ts` — `TabDefinition` + `listTabs()`; the four fields that were
  optional (`tab`, `requiresAdmin`, `numericOnly`, `renderInGui`) are now
  **required**, so a row missing its tab is a type error rather than a row drawn in
  the wrong place.
* `src/lib/registry.svelte.ts` — `tabs` state loaded alongside verbs;
  `rowsForTab(verbs, tab)` filters by tab **and** `renderInGui`.
* `src/App.svelte` — the rendered tab's heading comes from the backend's tab list.

### Tests

* `src-tauri/tests/registry.rs` — 11 tests, including
  `adding_a_verb_is_one_registry_entry_and_nothing_else` (the extension rule, proven
  by pushing a synthetic verb through the real render path) and
  `the_documented_counts_are_the_counts_the_table_actually_has`.
* `src-tauri/tests/dispatch.rs` — the ticket-01 tracer assertions were **retired**
  into the registry suite (their old contract — "exactly two verbs" — is false by
  design now) and replaced with the ticket-03 refusals.
* `src/tests/registry.spec.ts` — 5 frontend tests: a tab renders only its
  own rows, a read-only tab can never contain an admin verb, a CLI-only verb draws
  no row, registry order is preserved (not sorted), an empty tab stays empty.
* `tests/rust-ticket02-probe.ps1` — 26 execution-contract probes, dual-mode
  thresholds (ADR-0019).
* `tests/rust-ticket03-interrupt.mjs` — the US 55 + CLI-contract harness.

---

## 6. Verification — the baseline you must confirm before starting

Run this first. Any red means something changed since this document was written —
find out what before building on it.

```powershell
cd H:\Repo\komorebi-1click\src\KomorebiDashboardRust\src-tauri
cargo test --locked --no-default-features
cd ..\src\KomorebiDashboardRust
npm run check ; npm test
cd H:\Repo\komorebi-1click
node tests\rust-ticket03-interrupt.mjs
.\tests\rust-ticket02-probe.ps1
```

The full set as last measured, all green:

```text
cargo fmt --check                               exit 0
cargo clippy --locked --all-targets -D warnings exit 0   no warnings
cargo test --locked --no-default-features       exit 0   24 passed / 0 failed
npm run check                                   exit 0   0 errors, 0 warnings
npm test                                        exit 0   49 passed / 0 failed
tests/rust-ticket03-interrupt.mjs               exit 0   8 passed, 1 skipped, 0 failed
tests/rust-ticket01-cli.mjs                     exit 0   6/6 (regression)
tests/check-shipped-text.mjs                    exit 0   190 files, no foreign script
tests/rust-ticket02-probe.ps1                   exit 0   26/26 strict (dual-mode, ADR-0019)
```

The one `SKIP` is `delivered-interrupt`. That is the honest result, and §8 explains
why it is a skip and not a failure or a fake pass.

### The four build phases

`src/KomorebiDashboardRust/build.ps1` is the build contract — run it, do not
emulate it:

```
pwsh -File H:\Repo\komorebi-1click\src\KomorebiDashboardRust\build.ps1
pwsh -File ...\build.ps1 -SkipRestore     # phases 2-4 only, for a fast re-rerun
```

| Phase | Command it runs | What passing proves |
|---|---|---|
| 1 — Reproducible restore | `npm ci` then `cargo fetch --locked` | dependency sets resolve from the committed locks alone |
| 2 — Static checks | `npm run check` then `cargo fmt --check` | zero type errors / diagnostics; canonical formatting |
| 3 — Safe behaviour tests | `npm test` then `cargo test --locked --no-default-features` | the pure rules and the registry/runner contract hold; no state-changing verb is executed |
| 4 — Windows release build and promotion | `cargo tauri build --no-bundle -- --locked`, copy to `releases\rust\` | MSVC link succeeds, frontend embedded, one executable lands |

Runtime verification is a **separate** step and is never inferred from a successful
link. Details: `implement/BUILD-CHECKLIST.md`.

---

## 7. Decisions locked by Davood (binding)

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
10. **Timing thresholds are dual-mode** (ADR-0019): **strict** is the default and the only mode a
    release may use; **relaxed** is opt-in for a busy local machine and is always recorded as such.
11. **Cheatsheets are bilingual** (ADR-0020): a Persian version and an English version of each,
    cross-linked, with hotkeys and commands copied verbatim.

### ADRs

| ADR | Decides |
|---|---|
| `spec/ADR-0017-rust-tauri-dashboard.md` | the Rust + Tauri stack |
| `spec/ADR-0018-stabilization-decisions.md` | the 35-verb count, settings compatibility, stale-prose corrections |
| `spec/ADR-0019-dual-mode-thresholds.md` | strict/relaxed timing thresholds |
| `spec/ADR-0020-bilingual-cheatsheets.md` | FA + EN cheatsheet split |

---

## 8. Known gaps and defects (read before you touch anything)

### Two defects found while implementing ticket 03 (both fixed, both pinned by tests)

**R1 — the caller's timeout was silently ignored.** `strip_timeout_option` removes
`-TimeoutSeconds` before dispatch, but `execute()` read the budget from that same
vector — so stripping first always fell back to the 300 s default with no error.
The timeout tests caught it immediately. Fix: resolve the budget from the
**original** arguments, pass it into `execute` explicitly. Pinned by
`a_caller_budget_is_read_before_the_option_is_stripped`.
Rule: **parse, then consume** — never consume, then parse.

**R2 — `status` was one argument from being an admin operation.** `status` declares
`RequiresAdmin: false` but carries the fixed `-Action status`. A naive
`arguments.is_empty()` check counts fixed arguments too, exempting exactly the
verbs with the most dangerous fixed flags. Fix: decide from the declared **shape**
(`accepts_user_arguments` = the shape mentions `<…>` or `[…]`); `fixed_arguments`
never satisfies that test. Refuse with exit 2 before launching.

Also recorded: **R3** (console control events are undeliverable on ConPTY — below)
and **R4** (the tracer placeholder returned the whole table as one tab's rows, which
would have drawn `uninstall` inside Debugging).

### US 55 (Ctrl+C cancels the child) — implemented, delivery unprovable here

The implementation is complete; the **delivery proof** is not, and the reason is a
measured property of the host.

The implementation: `run_cli` selects on `tokio::signal::ctrl_c()` and calls
`request_cancel("cli")` — the same path the window's Cancel button uses, so there is
no second stop mechanism to keep correct. `console::ensure_console` attaches the
parent console only when `GetConsoleWindow()` is null **and** stdout is a real
terminal, because `AttachConsole` rebinds the standard handles and would otherwise
destroy output capture (`dashboard status | grep up` would return nothing — the trap
the WPF build documented).

The measurement. This session runs on a **ConPTY pseudo-console**, where Windows
delivers no console control event:

```text
GetConsoleWindow()       -> 0
AllocConsole()           -> False, ERROR_ACCESS_DENIED (5)
GetConsoleProcessList()  -> 1   (this process only)
```

Four spawn topologies were probed with a child that installs a real
`SetConsoleCtrlHandler` and writes a marker file the instant an event arrives — so
"delivered" means a marker on disk, not a lucky termination:

| Topology | Signal call | Event received |
|---|---|---|
| shares harness console, `CREATE_NEW_PROCESS_GROUP` | ok | **no** |
| own console, `+ CREATE_NEW_CONSOLE` | ok | **no** |
| own console, harness then `AttachConsole` | ok | **no** (attach → `ERROR_ACCESS_DENIED`) |
| `CREATE_NO_WINDOW` (what the launcher uses) | **fails, `ERROR_INVALID_HANDLE` (6)** | **no** |

So `tests/rust-ticket03-interrupt.mjs` reports `SKIP` with the measured error and
exits 0; it exits 1 only on a real FAIL.

**To convert the SKIP into a PASS:** run the harness from a real interactive console
(a normal PowerShell window, not an agent/PTY session):

```powershell
cd H:\Repo\komorebi-1click
node tests\rust-ticket03-interrupt.mjs
```

If it still SKIPs there, that is a real finding about the code, not the host —
investigate. **Do not weaken the case to make it pass.**

### Gaps carried forward

* **The CLI does not yet gate on elevation.** `requires_admin` is on every verb and
  reachable from the frontend, but the CLI still dispatches an admin verb without
  refusing. The WPF build gated here (`ElevationService.CanRun` before launch, loud
  refusal, dedicated exit code), so this is a **live parity gap** — ticket 05 owns
  it. It is recorded here rather than hidden.
* **Only one tab renders.** Until ticket 04 lands, the shell draws
  `CURRENT_TAB = 'Debugging'` and that tab's own rows. This is deliberate: the
  tracer's placeholder returned the whole table, which was exact with two verbs and
  wrong with 35.
* **No commit yet.** Nothing from ticket 03's session is committed; see §10.

---

## 9. The exact point to resume from — ticket `04-eight-tabs`

Start there. What it needs is already in place, so the work is the strip itself:

1. `registry.rs` already exposes `TABS` (8 entries, ordered) and
   `verbs_in_tab(id)` / `rows_in_tab(id)`, and `main.rs` already serves `list_tabs`
   over IPC. The backend is ready; ticket 04 is a frontend task.
2. In `src/lib/registry.svelte.ts`, replace the `CURRENT_TAB` constant with real
   selected-tab state, and keep `rowsForTab` as the row source — the guard it
   applies (`tab` **and** `renderInGui`) is what stops an admin verb appearing in a
   read-only tab.
3. `App.svelte` currently reads the heading from `registry.tabs.find(...)`; extend
   that to render the strip. Customization and About carry **no** registry verbs and
   must render as hand-built surfaces.
4. Order is the registry's order, not alphabetical — `rowsForTab` preserves it, and
   the frontend test `preserves the order the registry declares rather than sorting`
   exists specifically because sorting would break the parity the rewrite preserves.

**Before you start**, re-verify the baseline in §6.

---

## 10. Files changed across the ticket-01→03 sessions

```text
MODIFIED
 src/KomorebiDashboardRust/src-tauri/src/lib.rs
 src/KomorebiDashboardRust/src-tauri/src/main.rs
 src/KomorebiDashboardRust/src-tauri/tests/dispatch.rs
 src/KomorebiDashboardRust/src/App.svelte
 src/KomorebiDashboardRust/src/lib/ipc.ts
 src/KomorebiDashboardRust/src/lib/registry.svelte.ts
 src/KomorebiDashboardRust/src/tests/rows.spec.ts
 docs/rust-translate/handoff.md
 docs/rust-translate/implement/handoff.md
 docs/rust-translate/implement/BUILD-CHECKLIST.md
 docs/rust-translate/bugs-fixing.md
 docs/rust-translate/knowledges.md
 docs/rust-translate/roadmap.md
 docs/rust-translate/spec/spec.md
 tests/rust-ticket02-probe.ps1                     (dual-mode thresholds, ADR-0019)

NEW
 src/KomorebiDashboardRust/src-tauri/src/registry.rs          (the 35-verb table)
 src/KomorebiDashboardRust/src-tauri/tests/registry.rs        (11 tests)
 src/KomorebiDashboardRust/src/tests/registry.spec.ts         (5 tests)
 tests/rust-ticket03-interrupt.mjs
 docs/rust-translate/spec/ADR-0018-stabilization-decisions.md
 docs/rust-translate/spec/ADR-0019-dual-mode-thresholds.md
 docs/rust-translate/spec/ADR-0020-bilingual-cheatsheets.md
 cheatsheets/en/komorebi-description.md
 cheatsheets/en/komorebi-hotkeys.md
 cheatsheets/fa/komorebi-description.md      (moved from cheatsheets/)
 cheatsheets/fa/komorebi-hotkeys.md          (refreshed from the dev tree)
```

**Nothing is committed.** All of the above is in the working tree. Pre-existing dirty
entries that are **not** this work and must not be committed with it:
`config/komorebi.json`, `scripts/safe-restart.ps1`, the two staged `docs/HANDOFF-*`
deletions, `config/mini_asc.json`, `scripts/safe-restart-backup-full.ps1`,
`scripts/safe-restart-v1.ps1`, `tests/uia-dump.ps1`.

---

## 11. Rules that bind this project (do not learn these the hard way)

* **WSL guard.** `/mnt/*` is blocked by default. This project has explicit bypass
  approval: `export ALLOW_WINDOWS=1` and reach Windows through
  `~/.hermes/scripts/win-exec.sh pwsh '<script>'`. That wrapper has **no console** —
  it is why US 55 could not be proven here (§8), and it is why `Add-Type` inside it
  is unreliable for anything touching `kernel32` console APIs.
* **`win-exec.sh` takes a single inline script string**, not `-File` or
  `-Command` flags: `win-exec.sh pwsh 'Get-Date'`. Multi-line scripts work inside
  the quotes.
* **`win-exec.sh` does not propagate WSL environment variables to Windows** —
  `DASHBOARD_THRESHOLD_MODE` set in WSL is not seen by the probe. Pass parameters
  explicitly (`-Relaxed`, `-ThresholdMode`) instead.
* **win-exec'd shells report `$LASTEXITCODE` unreliably across a pipe.** Read exit
  codes without piping through `Select-Object`, or you will see `0` for a failing
  command.
* **The build host is Windows.** `cargo`/`npm` run under `win-exec.sh`; a WSL-native
  build is not the contract.
* **No new dependency without justification.** The console FFI in `main.rs` is
  hand-rolled (`#[link(name = "kernel32")]`) precisely so `--locked` stays honest and
  no crate is added for four lines of FFI.
* **Questions are never asked interactively.** They go in the final report; Davood
  answers them in the next prompt.
* **Shipped text is English only.** `tests/check-shipped-text.mjs` enforces it.
* **The four phases of `build.ps1` are the build contract**, and runtime verification
  is a separate step that is never inferred from a successful link.
* **The registry is the single source of truth.** Frontend and backend both derive
  from it; never keep a second list.
* **Source for the cheatsheets is the dev tree** at
  `~/projects/komorebi-1click/cheatsheets/`, which is *newer* than the published
  copies — e.g. `komorebi-hotkeys.md` there (18.8 KB) has section 3.5
  (`focus-monitor-workspace`), the `Alt + C`/`Alt + V` stack bindings, and the
  `wsl.exe`/`notepad++.exe` rows that the older published copy lacks. Update from
  there; the published `fa/` copies are downstream of it.

---

## 12. Mandatory reading order (bootstrap)

Before writing any code:

1. **This document** ← you are here
2. **`implement/BUILD-CHECKLIST.md`** ← build and verification contract
3. **`knowledges.md`** ← domain knowledge, invariants, host facts
4. **`codebase-inventory.md`** ← what C# maps to which Rust file
5. **`bugs-fixing.md`** ← defects that must not return
6. **`spec/spec.md`** ← the specification (84 user stories, IPC contract)
7. **`spec/ADR-0017` → `ADR-0020`** ← the decisions
8. **The starting ticket** — `tickets/04-eight-tabs.md`
9. **Adjacent tickets** — the ones the starting ticket blocks or is blocked by
10. **The current Rust codebase** — `src/KomorebiDashboardRust/`
11. **The .NET 8 WPF codebase** — `src/KomorebiDashboard/` — when you need parity
    detail for the ticket you are on

Then: re-verify the baseline (§6), and only then start the ticket.

### Where everything lives

| Path | What |
|---|---|
| `H:\Repo\komorebi-1click\` | publish tree (git, ships) — **source of truth** |
| `H:\Repo\komorebi-1click\docs\rust-translate\` | everything for this translation |
| `H:\Repo\komorebi-1click\src\KomorebiDashboard\` | the .NET 8 WPF codebase being translated |
| `H:\Repo\komorebi-1click\src\KomorebiDashboardRust\` | the Rust + Tauri codebase (tickets 01–03) |
| `H:\Repo\komorebi-1click\releases\rust\KomorebiDashboard.exe` | the built Rust EXE |
| `~/projects/komorebi-1click\.scratch\rust-translate\issues\` | WSL-side ticket tracker |
| `~/projects/komorebi-1click\cheatsheets\` | dev-tree cheatsheets (newer than published) |

### Suggested skills

Call these through the skill tool when the situation matches:

* **`handoff`** (mattpocock) — compact this conversation again when handing on
* **`implement`** / **`implement-spec`** (mattpocock) — implement a ticket against a spec
* **`tdd`** (mattpocock) — the registry and dispatch suites are test-first
* **`diagnosing-bugs`** (mattpocock) — for the R1/R2 class of failure
* **`code-review`** (mattpocock) — before committing a ticket
* **`hermes-agent`** — for Hermes configuration/tool questions
* **`wsl-isolation`** — the `/mnt/*` guard and `win-exec.sh` details
