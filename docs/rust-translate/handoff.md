# KomorebiDashboard — Rust Translation · Handoff

> **This is the single continuation document for the next agent.**
> Read sections 6–9 first; sections 1–5 are background. Last updated: **2026-10-10, after session 6.**
> There is exactly one handoff document — `handoff-last-session.md` and
> `implement/handoff.md` were merged into §0.3 and removed in session 6.

---

## 0. One-line status

The Rust track's tickets `01`, `02`, `03` are **implemented, verified, and
committed** (`5df6f6d` session-4 documents, `d64ec0c` ticket 03, `beec3f2`
installer fixes — all pushed with session 6). The next ticket is
**`04-eight-tabs`** (Rust track). Session 6 audited the installer track's
tickets `04-startup-tasks` and `05-autohotkey-vbs` end-to-end on the live
machine, closed both, and fixed one genuine defect in ticket 05's regenerate
seam (§0.2). Nothing is mid-edit; the only known gap is a host capability
(ConPTY), not a code defect. Another session is concurrently editing
`config/`, `scripts/step5/` and `docs/Access-Denied-Solving/` — do not touch
those paths.

If your connection drops, this document alone is enough to continue.

### 0.1 Session 5 (2026-10-10) — what changed since the ticket-03 landing

* **Baseline re-measured from scratch on the Windows host** (§6 is the contract):
  cargo 24, npm check 0 + test 49, ticket03-interrupt 8 passed + 1 honest SKIP,
  ticket01-cli 6/6, ticket02-probe 26/26 strict, shipped-text 194 files clean.
  One regression was found on the way in — `check-shipped-text.mjs` had been
  *recorded* green but actually failed (Persian digits in the session-4 docs).
  Fixed, re-run clean, and recorded as defect R5 in `bugs-fixing.md`: a baseline
  is a measurement, not a copy-forward.
* **Ticket 03 is committed** (`d64ec0c`, 22 files; the session-4 documents in
  `5df6f6d`, 4 files), scoped by pathspec so no pre-existing dirty entry entered
  either commit. The tracker boxes were ticked in both the dev mirror and the
  publish copy (they had drifted: the dev mirror was fully ticked, the publish
  copy was not — the publish copy is now a byte-identical mirror again).
* **Installer track, ticket `04-startup-tasks`** — audited against the live
  machine: both scheduled tasks exist, `RunLevel=Highest`, correct actions,
  `komorebic` on the machine PATH, YASB autostart present via its own Run key.
  Two genuine gaps were found in the **legacy duplicate**
  (`komorebi-service.ps1`): `-Action install` used to register Medium-integrity
  tasks from an unelevated shell (the ADR-0016 regression — and this host's user
  is a standard user, so that path always produced the broken state), and
  `-Action status` never confirmed YASB although its ticket requires all three.
  Both fixed and verified; details in `bugs-fixing.md` §1.9 and the dev tracker
  `~/.scratch/komorebi-1click-installer/issues/04-startup-tasks.md`.
* **US 55's delivery proof still SKIPs** on this ConPTY host — measured again
  this session, unchanged, and still a SKIP rather than a fake pass (§8).

### 0.2 Session 6 (2026-10-10) — installer tickets 04 and 05 verified and closed; one defect fixed

* **Ticket `04-startup-tasks` (installer track)** — audited against the live
  machine, all 13 boxes re-proven read-only: both scheduled tasks exist with
  `RunLevel=Highest`, correct actions and triggers (`komorebic.exe start --whkd`
  on logon for `Komorebi`; the windowless launcher → `komorebi-service.ps1
  -Action watchdog -WatchdogMinutes 5` on a 5-minute time trigger for
  `KomorebiWatchdog`), `komorebic` on the machine PATH, YASB autostart via its
  own HKCU Run key, `-Action status` HEALTHY for all three. The session-5
  fixes are confirmed in place (unelevated `-Action install` now refuses before
  any side effect; `-Action status` reports YASB). The `Global\komorebi-service-start`
  mutex and the both-streams redirection are preserved on every restart path.
  Nothing was left to implement; the tracker now records
  `implemented-and-pushed`.
* **Ticket `05-autohotkey-vbs` (installer track)** — verified end-to-end on the
  live machine: the real Startup `AppRunner.vbs` is **byte-identical** to what
  the shipped generator produces from the template and `autohotkey\` dir
  (`Test-AppRunnerUpToDate` returns True, so re-running correctly skips), it
  contains exactly three `RunHidden` lines and zero `RunNormal` lines, uses the
  v1 interpreter for `autocorrect.ahk` and `ChangeLangF3.ahk` and the v2
  interpreter for `NewFile.ahk`, and two `AutoHotkey.exe` (v1) plus one
  `AutoHotkey64.exe` (v2) process are running from `autohotkey\`.
* **Defect R6 found and fixed** (`bugs-fixing.md` §3.6):
  `Set-AhkEnabledState` persisted `ahk-state.json` but rendered the Startup VBS
  from the in-memory manifest without applying the new state first — so
  `ahk-toggle -State disabled` killed the scripts while the regenerated VBS
  kept them live, and all three returned at the next logon. The ticket-08
  tests had passed through the hole because their section 3 round-tripped only
  the state file, never the generated file. Fixed by applying the state before
  rendering; the hole is closed by two assertions that inspect the generated
  VBS (19/19 green).
* **The working tree is shared with another session.** `config/applications.json`,
  `config/config.yaml`, `config/whkdrc`, `scripts/safe-restart.ps1`,
  `config/backup-last/`, `config/backup-2026-10-10/`, `scripts/step5/` and
  `docs/Access-Denied-Solving/` belong to that session — untouched. Their
  in-flight `whkdrc` edit is also why one T03-followup assertion in
  `tests/ticket05-06-07.tests.ps1` (the `alt+ctrl+shift+r` binding to
  `safe-restart.ps1`, which the committed `config/whkdrc` still binds) fails
  against the working tree: committed at the time it was written, theirs to
  reconcile. Session-6 commits use explicit pathspecs so none of those entries
  enter them.
* **One handoff document.** Per Davood, `handoff-last-session.md` and
  `implement/handoff.md` were merged into this document (§0.3) and removed.
  Do not create a second handoff document.

### 0.3 Session history (compressed, sessions 2–5)

* **Session 2 (2026-10-08) — ticket 01.** The Rust + Tauri shell builds and the
  first suites land; artefact `releases/rust/KomorebiDashboard.exe`
  (6,420,992 bytes). Commits pushed to `origin/main`.
* **Session 2b (2026-10-08) — ticket 02 (`02-execution-contract`).** The
  backend that observes a stop now records `cancelled` / `timedOut` on the
  result instead of deriving a verdict from exit codes 130/124, and cancellation
  reaches a live run through a per-run-id sender registry. A clean-checkout
  proof is part of its record — and it must be run **on Windows**, not from
  WSL, or it verifies nothing about the shipped artefact.
* **Session 3 (2026-10-09) — ticket 03 (`03-registry-cli-twin`).** The
  35-verb registry (`registry.rs`) becomes the single source of truth, the CLI
  twin dispatches from it, `TABS` and `list_tabs` are served over IPC, and
  US 55 (Ctrl+C cancels the child) is implemented. R1/R2 are fixed here. The
  guard order inside `run()` is load-bearing and must not be reordered:
  (1) unknown verb → 2; (2) `ahk` two-part fold; (3) read the budget;
  (4) strip `-TimeoutSeconds`; (5) a verb declaring a **required** value sent
  bare → 2; (6) a verb declaring **no** value given one → 2; (7) missing
  script → 127; (8) dispatch. Steps 5 and 6 must stay **after** step 4, or a
  legitimate `-TimeoutSeconds` is refused as a script argument. Ticket 04 was
  deliberately left to render one tab until this ticket landed.
* **Session 4 (2026-10-10) — Davood's two ticket-02 decisions, applied as
  ADRs.** Cheatsheets: **bilingual** (ADR-0020) — `fa/` authoritative, `en/`
  translated, hotkeys and commands copied verbatim; all 158 hotkey/command
  pairs verified identical, the English file carries zero Arabic-script
  characters, and the Jalali change-log dates stay authoritative. Thresholds:
  **dual-mode** (ADR-0019) — strict default (the only mode a release may pass),
  relaxed opt-in. `DASHBOARD_THRESHOLD_MODE` does not cross the WSL→Windows
  boundary, so pass `-ThresholdMode` explicitly from WSL. **Deferred, large
  reference documents, still untranslated:** `komorebi-configuration.md`
  (61 KB), `komorebi-debugging.md` (91 KB), and
  `Komorebi-Hotkey-Cheatsheet.md` (59 KB — deprecated, carries a redirect
  header, needs no translation).
* **Session 5 (2026-10-10)** — see §0.1: ticket 03 committed, defect R5 fixed,
  installer ticket 04 audited with the two legacy-path gaps closed.

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
| `03-registry-cli-twin` | **done**, verified, committed `d64ec0c` | registry of 35 verbs + CLI twin + US 55 wired; see §8 for the one unprovable item |
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

The full set as last measured, all green — **re-measured end to end at the start
of session 5, after the R5 fix**, so these numbers are the current state rather
than a copy of an older session:

```text
cargo fmt --check                               exit 0
cargo clippy --locked --all-targets -D warnings exit 0   no warnings
cargo test --locked --no-default-features       exit 0   24 passed / 0 failed
npm run check                                   exit 0   0 errors, 0 warnings
npm test                                        exit 0   49 passed / 0 failed
tests/rust-ticket03-interrupt.mjs               exit 0   8 passed, 1 skipped, 0 failed
tests/rust-ticket01-cli.mjs                     exit 0   6/6 (regression)
tests/check-shipped-text.mjs                    exit 0   no foreign script (the file count moves with harness evidence; the assertion is the invariant)
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
* **Everything is committed now.** Session 5 landed the ticket-03 work
  (`5df6f6d`, `d64ec0c`), its own installer-track fixes (`beec3f2`), and this
  handoff update in the commit that carries it — all on `main`, unpushed. The
  pre-existing unrelated dirty entries listed in §10 (including the two
  `docs/HANDOFF-*` deletions) are deliberately left uncommitted for Davood.

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

**Committed.** The body above landed in two focused commits — `5df6f6d` (the
session-4 documents: ADR-0019, ADR-0020, the session-4 log, the dual-mode probe)
and `d64ec0c` (the registry, the CLI twin, their tests, the ticket-03 docs).
Session 5's installer-track fixes landed separately in `beec3f2`
(`scripts/komorebi-service.ps1`, both `SCRIPTS-GUIDE` files). Session 6's
defect R6 fix (`scripts/Install-Common.ps1`,
`tests/ticket08-ahk.tests.ps1`) and the document work that carries this
paragraph land in the commit that carries it — the first session to push all of
them to `origin/main`.

Pre-existing dirty entries that are **not** this work and must not be committed
with it — most now belong to the other session working this tree concurrently:
`config/komorebi.json`, `scripts/safe-restart.ps1`, `config/applications.json`,
`config/config.yaml`, `config/whkdrc`, the two `docs/HANDOFF-*` deletions,
`config/mini_asc.json`, `scripts/safe-restart-backup-full.ps1`,
`scripts/safe-restart-v1.ps1`, `tests/uia-dump.ps1`, `backup/`,
`config/backup-last/`, `config/backup-2026-10-10/`, `scripts/step5/`,
`docs/Access-Denied-Solving/`, `docs/rust-translate/prompt.md`, and the
`config/last-backup/` deletions. Use explicit pathspecs when committing.

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
* **`check-shipped-text.mjs` scans the docs, not only the UI.** Persian digits
  fail it (defect R5); run it after any document change before claiming a green
  baseline.
* **`cheatsheets/` is gitignored** — the bilingual sheets are local-only
  reference documents; never claim or expect them in a commit.
* **Two ticket tracks share this repo**: the installer track (01-14, dev tree
  only) and the Rust translation (01-13, `docs/rust-translate/`). Their numbers
  collide — name the track before acting on a ticket number.
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

**One handoff document.** This file is the only continuation document.
`handoff-last-session.md` and `implement/handoff.md` were merged into §0.3 and
removed in session 6 at Davood's instruction; `implement/BUILD-CHECKLIST.md`
remains as the build and verification contract, not as a handoff. Update this
document alone when a session ends, and never leave a second entry log behind.

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
