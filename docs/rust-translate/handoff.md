# KomorebiDashboard — Rust Translation · Handoff

> **This is the single continuation document for the next agent.**
> Read sections 6–9 first; sections 1–5 are background. Last updated: **2026-10-10, after session 8.**
> There is exactly one handoff document — `handoff-last-session.md` and
> `implement/handoff.md` were merged into §0.5 and removed in session 6.

---

## 0. One-line status

The Rust track's tickets `01`, `02`, `03`, `04` are **implemented, verified, and
committed** (all pushed). The next ticket is **`05-elevation`** (Rust track).
Session 8 applied the US 55 harness rework that session 7 had only designed
(defect R7 closed, the one real-console PASS left as Davood's manual run) and
deep-audited installer tickets `05-autohotkey-vbs` and `06-script-portability`
(no genuine gaps). Session 9 (2026-10-10): committed Davood's decision on the
live `whkdrc` — the safe-restart binding restored, suite 66/66, and the suite's
whkdrc comparison reworked to be line-wise (a `git show` array joined with
`\\n` can never again fake a divergence off the trailing newline);
**implemented Davood's new export/import mechanism** (installer ticket 07:
directory selectors instead of ZIP file dialogs, one shared set definition in
`common.ps1`, both the Dashboard's button script and the standalone tool on the
same flow, E2E 31/31 in a sandboxed profile, suite 91/91); rebuilt
`releases\rust\KomorebiDashboard.exe` so its usage advertises `-BackupPath`
(same size, new hash). The next installer ticket is **`08-ahk-scripts`**.
Another session is concurrently editing `config/`, `scripts/Install-Common.ps1`,
`scripts/safe-restart.ps1`, `tests/uia-dump.ps1` and
`docs/Access-Denied-Solving/` — do not touch those paths.

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
  `implement/handoff.md` were merged into this document (§0.5) and removed.
  Do not create a second handoff document.

### 0.3 Session 7 (2026-10-10) — rust ticket 04 landed; the US 55 harness defect found and recorded (R7)

* **Ticket `04-eight-tabs` (Rust track) — done, runtime-verified, pushed.** The
  strip iterates the backend's own tab list (eight `role="tab"` items, backend
  order, nothing added), and the panel resolves its id from the same list:
  `lib/registry.svelte.ts` gained `tabSelection` (the shell's reactive
  selection) and `resolveActiveTab` (the selection when the backend still
  declares it, otherwise the **first** declared tab — a stale id can never blank
  the shell), replacing the `CURRENT_TAB` placeholder. Customization and About
  render the empty row state honestly. Switching a tab leaves the accumulated
  console untouched (runtime: 32 lines before, 32 after, verdict intact).
  Evidence: `docs/rust-translate/evidence/ticket04-eight-tabs-uia.md` (12/12
  UIA assertions on the built EXE, sha256 `8ea3c3d1fe18ee4f…`). The numeric
  filter was extracted to `filterNumericValue` in `lib/format.ts` with its own
  tests; `src/tests/tabs.spec.ts` (10 tests) covers selection resolution and the
  grouping covering every rendered verb exactly once across the eight tabs.
* **Defect R7 (US 55) — the interrupt harness could never deliver its signal on
  Windows.** `process.kill(-child.pid, 'SIGBREAK')` fails on Windows for two
  independent reasons: Node has no negative-pid (process-group) semantics
  (ESRCH even against a live child), and `detached: true` is `DETACHED_PROCESS`
  (no console), not `CREATE_NEW_PROCESS_GROUP` as the code comment claimed. The
  ConPTY limitation measured in session 3 stands, but the documented
  "re-run on a real console to convert the SKIP into a PASS" path could never
  have worked. Details: §8 US 55 and `bugs-fixing.md` §3.7; probe scripts in
  `tests/.build/us55-*.mjs`. **The harness rework was designed here and applied
  in session 8** — see §0.4 and §8.
* **Davood re-ran `tests\rust-ticket03-interrupt.mjs` from a normal window this
  session**: same SKIP, same `ESRCH kill ESRCH` cause — expected, because the
  harness's own signal call is what fails, before any console is involved.
* Suites this session: cargo **24 passed** · `npm test` **63 passed** (7 files) ·
  `svelte-check` **0 errors, 0 warnings** · `build.ps1` **exit 0** (four
  phases) · shipped-text **202 files PASS** · ticket08 **19/19** ·
  ticket01-CLI, ticket02-probe, US 55 CLI cases green ·
  ticket05-06-07: the single pre-existing FAIL (`alt+ctrl+shift+r` vs the other
  session's uncommitted `config/whkdrc` + `scripts/safe-restart.ps1` work) is
  still theirs and still untouched.
* **Unrelated dirty entries are untouched** (see §10): the other session's
  `config/`, `scripts/`, `docs/Access-Denied-Solving/` work, the two merged
  `docs/HANDOFF-*` deletions, and `tests/uia-dump.ps1`. Commits use explicit
  pathspecs so none of it is carried.

### 0.4 Session 8 (2026-10-10) — US 55 rework applied (R7 closed); installer tickets 05 and 06 deep-audited

* **Defect R7 reworked — the US 55 interrupt harness now delivers for real.**
  `tests/rust-ticket03-signal.ps1` (new) is the delivery path node cannot
  express: `CreateProcessW(exe, cmdline, …, CREATE_NEW_PROCESS_GROUP, cwd)` —
  both `lpApplicationName` and a valid `lpCurrentDirectory` are required, or
  CreateProcessW fails with win32 123/3 (measured in an isolation probe) — child
  stdout/stderr through inheritable `CreateFileW` handles, then
  `GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, pid)` after 2.5 s, then
  `WaitForSingleObject`. `tests/rust-ticket03-interrupt.mjs` case 1 is rewired:
  a **host gate** (`GetConsoleWindow()`) skips with the measured reason on a
  pseudo-console (probe: `{"consoleWindow":0}`, no more post-hoc ESRCH), argv
  travels as JSON (`-ArgumentsFile` — node cannot pass an array through a
  `pwsh -File` command line; the first attempt arrived as one mangled string),
  and the verdict now distinguishes generate-refused (SKIP, measured win32) from
  accepted-but-never-exited (FAIL — a real product finding). Harness run here:
  **8 passed, 1 skipped (capability absent, measured), 0 failed**, gate evidence
  written into `delivered-interrupt.txt`. Details: §8 US 55.
* **The delivery machinery is proven, the event still cannot land on ConPTY —
  measured, both halves.** A `cmd /c echo` child through the helper spawned,
  printed through the redirect and reported `generateOk=true, exitCode=0`; a
  `ping` child reported `generateOk=true` then `waitStatus=258`
  (WAIT_TIMEOUT — the OS accepted the send, nothing arrived, exactly the
  session-3 topology probe). The one remaining step is Davood's: run
  `node tests\rust-ticket03-interrupt.mjs` **from a real PowerShell window**;
  the case must then PASS (`reported cancelled, exit 0, 0 stragglers`) or FAIL
  honestly (procedure in §8 US 55 / bugs-fixing R7).
* **Installer ticket `05-autohotkey-vbs` — audited deep-live, closed.**
  Suite `ticket05-06-07.tests.ps1` now **65 assertions, 0 failures**: the one
  FAIL (`alt+ctrl+shift+r`) was the suite asserting whkdrc's *working copy*,
  which another session's live tuning edit has since dropped the binding from;
  the assertion now reads the **committed** template (what installs actually
  ship) and a working-copy divergence reports a loud **WARN** naming the missing
  binding — the commit-vs-discard decision stays with Davood. Live state:
  Startup `AppRunner.vbs` `Test-AppRunnerUpToDate` **True**, byte-identical to
  a fresh render (29/29 lines; v1 for `autocorrect.ahk`/`ChangeLangF3.ahk`, v2
  for `NewFile.ahk`), no HKCU Run entry (Startup-folder arm of the ticket),
  `Komorebi` scheduled task `Ready`, `ahk-state.json` absent = all enabled.
* **Installer ticket `06-script-portability` — audited deep-live, closed.**
  36-script absolute-path scan: 61 raw hits, all classified benign (vendor-
  default `C:\Program Files\*` locations from ticket 02's resolver mandate,
  the `C:\Users\DavoodYa` **rewrite machinery** in `Install-Common.ps1`,
  `\.\DISPLAY$i` device prefixes, the csc.exe framework path, one doc-comment
  example) — no `F:\`, no `H:\Repo`, no foreign user profile. The four
  uninstall/cleanup scopes verified as `-Scope
  [ValidateSet('all','komorebi-whkd','yasb','autohotkey')]` driving
  patterns/processes/tasks/dirs; the dual `-RedirectStandardOutput`/`-Error`
  preserved in `restart-whkd.ps1` L118-121; `-ZipPath` declared+used ×10 with
  the timestamped-directory default. FYI recorded in the tracker: `-ZipPath`
  writes a directory, not a zip — shipped contract, deliberately not churned.
* Suites this session: ticket03-interrupt **8P/1S/0F** · ticket05-06-07
  **65/65** · ticket08-ahk unchanged (19/19 from the running box, not re-run —
  no ticket-08 code touched) · `node --check` on the harness · build.ps1
  exit 0 (release EXE unchanged, 6,450,176 bytes).
* Unrelated dirty entries untouched again (§10): the other session's `config/
  whkdrc` (its WARN is the suite's doing, not an edit by me), `scripts/
  safe-restart.ps1`, `docs/HANDOFF-*`, `scripts/step5/`, backup dir,
  `tests/uia-dump.ps1`. This session's commit pathspecs: `tests/` +
  `docs/rust-translate/` only.

### 0.5 Session 9 (2026-10-10) — the whkdrc decision landed; ticket 07 reworked to directory selectors

* **Davood's whkdrc decision executed (commit `77fb9f6`, pushed).** The live
  tuning edit had dropped the `alt+ctrl+shift+r` safe-restart binding; per
  Davood it is now restored in the working copy and **committed** — 133
  bindings, no duplicate keys (whkd panics on a double binding), so a fresh
  install keeps the watchdog-safe restart. The suite's whkdrc comparison was
  reworked from reconstructed strings to line arrays: `git show` returns an
  array and `-join "`n"` drops the trailing newline, so the old comparison
  reported a phantom divergence after every commit — now the WARN only fires
  on a real difference (unit-checked both branches), and an extra assertion
  pins the equality. Suite 66/66.
* **Installer ticket 07 reworked to Davood's new mechanism** (commit in this
  session, explicit pathspecs): clicking Export opens a native **directory**
  selector and a fresh `komorebi-backup-<timestamp>\` with the WHOLE current
  config set is created inside the chosen directory; clicking Import opens the
  same selector and the chosen backup **replaces** the live config (rollback
  copy first, WM stopped/started around the swap). The ZIP machinery
  (`System.IO.Compression`, Save/Open file dialogs) was deleted from both
  scripts, `-ZipPath` became `-BackupPath` (C# and Rust registries updated;
  the Dashboard buttons and `EXPORT/IMPORT-CONFIG.bat` reach the no-path form
  that opens the picker), and the config set + critical-file rule + selector
  were unified into `common.ps1` (`Get-ConfigExportSet`,
  `Get-CriticalConfigSet`, `Show-DirectorySelector`) because the Dashboard's
  set and the standalone set had drifted (each missed part of the setup).
  Import refuses a folder that is not a backup (`whkdrc` + `komorebi.json`
  must be present, exit 1 otherwise) — the restore replaces, so a wrong
  folder would silently wipe half the setup. `yasb` imports as a directory
  REPLACE, not a merge (a stale widget must not survive).
* **E2E, sandboxed profile, 31/31** (`tests/.build/t07-e2e.ps1`, fake
  `%USERPROFILE%` under `%TEMP%`; the komorebi-backup copy had its WM-kill
  neutralized so the live window manager was never stopped): full-set export,
  empty resize state skipped / non-empty included, export→mutate→import round
  trip byte-identical, stale widget gone, rollback kept, WM stop/start cycle
  attempted, foreign folder refused. Static suite: **91 assertions, 0
  failures**. Baseline re-measured: cargo 24, npm 63 (7 files), svelte-check
  0/0, ticket08-ahk 19/19, shipped-text 215 files.
* **Artifact rebuilt.** `releases\rust\KomorebiDashboard.exe` rebuilt with the
  new registry strings — 6,450,176 bytes,
  sha256 `4B1962A9FDD3F094D01BF17558503F722300EE5CD438656C95100FE948FEF97C`
  (was `8EA3C3D1...`); its usage now advertises `-BackupPath [directory]`
  (measured: unknown-verb exit 2 prints both new lines). The releases folder is
  **not** git-tracked — the hash travels in this document, not in a commit.
* Suite lesson recorded: never pass a multi-line regex string into the
  PowerShell suite (the patch tool writes real CRLFs, and `(?s)` patterns with
  embedded newlines produce phantom PASSes). The two affected assertions were
  rewritten as single-line patterns.

### 0.6 Session history (compressed, sessions 2–7)

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
| `04-eight-tabs` | **done**, verified, pushed | the real eight-tab strip + tab-selection state; runtime evidence `evidence/ticket04-eight-tabs-uia.md` (12/12 UIA) |
| 05–13 | not started | **05 (elevation) is next** — the first one with a live parity gap; §9 |

Artefact: `releases/rust/KomorebiDashboard.exe` — **6,450,176 bytes**, release
profile (rebuilt 2026-10-10, session 7, sha256 `8ea3c3d1fe18ee4f…`). The WPF
`releases/KomorebiDashboard.exe` (170,176,020 bytes) was never touched.

**Implementation phase status:**
- Phase 1 — Specification (`spec.md`, ADR-0017) — ✅ done 2026-10-08
- Phase 2 — Tickets (`tickets/`) — ✅ done 2026-10-08 (13 tickets)
- Phase 3 — Implementation by coding agent — ⏳ **in progress** (tickets 01–04 done)

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

**Defect R7 (session 7) — the harness could never deliver the signal on any
host, so the "re-run on a real console" path could not have worked.**
REWORKED IN SESSION 8 (`tests/rust-ticket03-signal.ps1`, case 1 rewired). The
original case 1 killed with `process.kill(-child.pid, 'SIGBREAK')`, and the two
POSIX facts it assumed are false on Windows: Node's `process.kill` has no
negative-pid (process-group) semantics — it throws ESRCH even against a live
child — and `detached: true` maps to `DETACHED_PROCESS` (no console at all),
not `CREATE_NEW_PROCESS_GROUP` as the code comment claimed, and a process
without a console cannot receive console control events. Measured 2026-10-10
against a live, correctly spawned child: `+pid, 0` OK · `-pid, 0` ESRCH ·
`-pid, SIGBREAK` ESRCH · `+pid, SIGBREAK` ENOSYS. The ConPTY measurement above
stays independently true: on a real console, a corrected delivery —
`GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, groupId)` against a
`CREATE_NEW_PROCESS_GROUP` child sharing the caller's console — should deliver
the event.

The rework, measured on this host (all on ConPTY, 2026-10-10):

* **Host gate.** Case 1 first asks PowerShell for `GetConsoleWindow()`. On this
  pseudo-console it returns `0`, so the case now SKIPs **before** sending
  anything, with that measured value recorded in the evidence file
  (`delivered-interrupt.txt`). The old flow instead threw ESRCH *after* trying
  to signal a live child.
* **Delivery machinery verified.** `rust-ticket03-signal.ps1` builds the real
  topology: `CreateProcessW(exe, cmdline, …, CREATE_NEW_PROCESS_GROUP, cwd)`
  with **both `lpApplicationName` and a valid `lpCurrentDirectory`** (measured:
  either one missing fails with win32 123/3), child stdout/stderr redirected
  through inheritable file handles, then `GenerateConsoleCtrlEvent
  (CTRL_BREAK_EVENT, pid)` after 2.5 s, then `WaitForSingleObject`. Probed with
  two children from this host: a `cmd /c echo` child spawns, prints through the
  redirect, and reports `generateOk=true, exitCode=0`; a `ping` child reports
  `generateOk=true` and then **`waitStatus=258` (WAIT_TIMEOUT)** — the OS
  accepted the send and nothing arrived, exactly the older session-3 finding.
  So the machinery runs end-to-end here; the event itself still cannot land
  without a real console.
* **What this fixes is the honesty and the mechanism, not the science.** On a
  real console the case must now produce PASS or a genuine FAIL — there is no
  path left where a broken harness blames the host.

**The manual procedure that converts the SKIP** (run from a real console —
PowerShell/Terminal window, not this agent shell):

```text
cd H:\Repo\komorebi-1click
node tests\rust-ticket03-interrupt.mjs
```

Then the delivered-interrupt case must be **PASS** (`reported cancelled, exit
0, 0 stragglers`). Anything else is a real finding: `waitStatus` 258 with a
cancelled-missing stderr means the console event was accepted but the run did
not cancel (a US 55 code bug, test-debt rows); a `graceful` marker on stderr
means a SIGKILL path replaced the graceful one.

**When a harness's own signal call throws ESRCH against a live child, the
harness is broken, not the platform — measure the mechanism before
re-diagnosing the host.**

### Gaps carried forward

* **The CLI does not yet gate on elevation.** `requires_admin` is on every verb and
  reachable from the frontend, but the CLI still dispatches an admin verb without
  refusing. The WPF build gated here (`ElevationService.CanRun` before launch, loud
  refusal, dedicated exit code), so this is a **live parity gap** — ticket 05 owns
  it. It is recorded here rather than hidden.
* **Customization and About render their empty row state.** Ticket 04 proved the
  grouping and the strip; the two hand-built surfaces themselves (theme controls,
  product identity) are roadmap R09/R10 work and tick when they land. The tabs
  exist, are selectable, and render honestly as empty rather than as a broken
  grouping.
* **Session 8 is committed and pushed with the harness rework + the two
  installer audits** (commit follows this edit; `tests/rust-ticket03-signal.ps1`
  NEW, `tests/rust-ticket03-interrupt.mjs` case 1 rewired,
  `tests/ticket05-06-07.tests.ps1` HEAD-template + WARN, the handoff rewrite,
  and this file). The pre-existing unrelated dirty entries listed in §10
  (including the other session's `config/whkdrc`, `scripts/safe-restart.ps1`,
  the two merged `docs/HANDOFF-*` deletions and `tests/uia-dump.ps1`) are
  deliberately left uncommitted for Davood.

---

## 9. The exact point to resume from — ticket `05-elevation`

Ticket 04 landed in session 7 (evidence:
`docs/rust-translate/evidence/ticket04-eight-tabs-uia.md`, 12/12 UIA
assertions), so the frontier is `05-elevation`. What it needs is already in
place:

1. **The live parity gap it closes** (§8): `requires_admin` is on every verb and
   the frontend can dispatch any of them, but the CLI still runs an admin verb
   without refusing. The WPF build refused before launch
   (`ElevationService.CanRun`, dedicated exit code 740) — match that, per
   ADR-0012.
2. `registry.rs` carries `requires_admin` per verb (ticket 03), so the CLI gate
   and the dialog's feature list are both **generated** from the table — the
   dialog must never hard-code a feature list that can drift.
3. The GUI side is the `Rerun as Administrator` dialog: exactly three actions
   (OK, Rerun as Administrator, Cancel), then a relaunch elevated with the old
   instance exiting (one window only), and declining UAC returns to a usable
   unelevated window with no error state.
4. **Do not** use process-access escalation for the token probe — ADR-0016; the
   elevation probe lives in `wsl-isolation`/`godmode` skills and the repo's
   ADR set.

**DONE in session 8:** the US 55 harness rework (defect R7, §8) —
`GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, pid)` via PowerShell P/Invoke
against a `CreateProcessW(..., CREATE_NEW_PROCESS_GROUP)` child sharing the
caller's console, behind a `GetConsoleWindow()` host gate; delivery machinery
measured end-to-end on this host, and the remaining item is Davood's
real-console run (`node tests\rust-ticket03-interrupt.mjs` from a normal
window — procedure in §8 US 55). **Davood ran it on 2026-10-10:**
8 passed / 1 honest SKIP / 0 failed, and the SKIP is now itself the measured
evidence (it names the pseudo-console cause and re-runs on a real console).

**Next installer ticket: `08-ahk-scripts`.** Davood's sequence: ticket 07
first (DONE in session 9 — §0.5), then ticket 08. The AHK lifecycle
scripts (`ahk-toggle.ps1`, `ahk-script.ps1`, `ahk-cleanup.ps1`,
`ahk-uninstall.ps1`) already ship; the R6 defect (the enable seam writing
state while the watchdog re-launches) was fixed in session 6 and its suite is
19/19. What ticket 08 still owes is the **live audit** in the shape of
sessions 5–9: run the enable/disable cycles and the doctor against the live
machine and a sandboxed copy, confirm state-file semantics and interpreter
resolution, and close or extend the tracker's remaining box
(`SCRIPTS-GUIDE.fa.md` documents ticket 08's bats) only against what was
measured. The live-machine rule (§11) applies: enable/disable toggles real
state on Davood's box — restore whatever the audit changes.

**Before you start**, re-verify the baseline in §6.

---

## 10. Files changed across the ticket-01→04 sessions (+ sessions 5–8)

```text
MODIFIED
 src/KkomorebiDashboardRust/src-tauri/src/lib.rs
 src/KkomorebiDashboardRust/src-tauri/src/main.rs
 src/KkomorebiDashboardRust/src-tauri/tests/dispatch.rs
 src/KkomorebiDashboardRust/src/App.svelte
 src/KkomorebiDashboardRust/src/lib/ipc.ts
 src/KkomorebiDashboardRust/src/lib/registry.svelte.ts
 src/KkomorebiDashboardRust/src/tests/rows.spec.ts
 docs/rust-translate/handoff.md
 docs/rust-translate/implement/handoff.md
 docs/rust-translate/implement/BUILD-CHECKLIST.md
 docs/rust-translate/bugs-fixing.md
 docs/rust-translate/knowledges.md
 docs/rust-translate/roadmap.md
 docs/rust-translate/spec/spec.md
 tests/rust-ticket02-probe.ps1                     (dual-mode thresholds, ADR-0019)

NEW
 src/KkomorebiDashboardRust/src-tauri/src/registry.rs          (the 35-verb table)
 src/KkomorebiDashboardRust/src-tauri/tests/registry.rs        (11 tests)
 src/KkomorebiDashboardRust/src/tests/registry.spec.ts         (5 tests)
 tests/rust-ticket03-interrupt.mjs
 docs/rust-translate/spec/ADR-0018-stabilization-decisions.md
 docs/rust-translate/spec/ADR-0019-dual-mode-thresholds.md
 docs/rust-translate/spec/ADR-0020-bilingual-cheatsheets.md
 cheatsheets/en/komorebi-description.md
 cheatsheets/en/komorebi-hotkeys.md
 cheatsheets/fa/komorebi-description.md      (moved from cheatsheets/)
 cheatsheets/fa/komorebi-hotkeys.md          (refreshed from the dev tree)
```

**Ticket 04 (session 7, 2026-10-10):**

```text
MODIFIED
 src/KkomorebiDashboardRust/src/App.svelte                       (strip + tab resolution + empty state)
 src/KkomorebiDashboardRust/src/lib/registry.svelte.ts        (tabSelection + resolveActiveTab)
 src/KkomorebiDashboardRust/src/lib/format.ts                 (filterNumericValue)
 src/KkomorebiDashboardRust/src/components/VerbRow.svelte      (numeric filter via format.ts)
 src/KkomorebiDashboardRust/src/tests/format.spec.ts          (+4 filterNumericValue tests)
 docs/rust-translate/tickets/04-eight-tabs.md                 (status → done, evidence)
 docs/rust-translate/handoff.md
 docs/rust-translate/bugs-fixing.md                           (defect R7)
 docs/rust-translate/knowledges.md                            (UIA TabItem seam; R7 lesson)

NEW
 src/KkomorebiDashboardRust/src/tests/tabs.spec.ts            (10 tests)
 docs/rust-translate/evidence/ticket04-eight-tabs-uia.md     (12/12 UIA assertions)
```

**Session 8 (2026-10-10) — US 55 harness rework + installer 05/06 audits:**

```text
MODIFIED
 tests/rust-ticket03-interrupt.mjs             (case 1 rewired: host gate + helper delivery)
 tests/ticket05-06-07.tests.ps1                (whkdrc section reads the committed template; WARN, not FAIL)
 docs/rust-translate/handoff.md                (§0.4, §8 R7, §9, §10 — this document)
 docs/rust-translate/bugs-fixing.md            (R7 → reworked, with the manual procedure)
 docs/rust-translate/knowledges.md             (CreateProcessW requires BOTH app name and cwd; argv-as-JSON)

NEW
 tests/rust-ticket03-signal.ps1                (the delivery helper: gate + P/Invoke + JSON result)
```

**Committed.** The body above landed in two focused commits — `5df6f6d` (the
session-4 documents: ADR-0019, ADR-0020, the session-4 log, the dual-mode probe)
and `d64ec0c` (the registry, the CLI twin, their tests, the ticket-03 docs).
Session 5's installer-track fixes landed separately in `beec3f2`
(`scripts/komorebi-service.ps1`, both `SCRIPTS-GUIDE` files). Session 6's
defect R6 fix (`scripts/Install-Common.ps1`,
`tests/ticket08-ahk.tests.ps1`) and the document work that carries this
paragraph land in the commit that carries it — the first session to push all of
them to `origin/main`. Session 8 lands the US 55 rework
(`tests/rust-ticket03-signal.ps1`, case 1) and the installer-ticket audit notes
in the commit that carries this sentence, also with explicit pathspecs
(`tests/`, `docs/rust-translate/`).

**Session 9 (2026-10-10) — the whkdrc decision + ticket 07 rework:**

```text
MODIFIED
 scripts/common.ps1                       (Get-ConfigExportSet / Get-CriticalConfigSet /
                                           Show-DirectorySelector — the ONE shared definition)
 scripts/komorebi-backup.ps1              (the Dashboard's Export/Import: directory selectors,
                                           $BackupPath, -NoDialog, shared set, critical-file guard,
                                           yasb directory REPLACE, common.ps1 resolution block)
 scripts/config-export-import.ps1         (standalone tool: same flow, ZIP machinery REMOVED,
                                           same shared set + selector)
 scripts/EXPORT-CONFIG.bat                (comment: the picker flow)
 scripts/IMPORT-CONFIG.bat                (comment: the picker flow; the F:\Backups path is gone)
 scripts/SCRIPTS-GUIDE.md                 (section 5: picker flow, -BackupPath, the guard)
 scripts/SCRIPTS-GUIDE.fa.md              (section 5, Persian: picker flow, no F:\Backups)
 tests/ticket05-06-07.tests.ps1           (T07 rewritten: directory selectors + shared set, 91
                                           assertions; whkdrc comparison line-wise; -BackupPath)
 tests/TESTING.md                         (T07 description, E2E block, counts)
 src/KomorebiDashboard/Services/VerbRegistry.cs   (usage texts: -BackupPath [directory] ×2)
 src/KomorebiDashboardRust/src-tauri/src/registry.rs (same two strings in the Rust table)
 docs/rust-translate/knowledges.md        (export/import verb descriptions)
 docs/rust-translate/handoff.md           (§0, §0.5, §9, §10 — this document)

ARTIFACT (not git-tracked)
 releases\rust\KomorebiDashboard.exe     rebuilt: 6,450,176 bytes,
                                           sha256 4B1962A9FDD3F094D01BF17558503F722300EE5CD438656C95100FE948FEF97C
```

**Committed.** Session 9's whkdrc decision landed as `77fb9f6`
(`config/whkdrc` + the suite's line-wise comparison), pushed. The ticket-07
rework lands in the commit that carries this paragraph, explicit pathspecs
(`scripts/`, `tests/`, `src/`, `docs/rust-translate/`), never the other
session's `config/`, `scripts/Install-Common.ps1`, `scripts/safe-restart.ps1`
or `docs/` deletions.

Pre-existing dirty entries that are **not** this work and must not be committed
with it — most now belong to the other session working this tree concurrently:
`config/komorebi.json`, `scripts/safe-restart.ps1`, `config/applications.json`,
`config/config.yaml`, `scripts/Install-Common.ps1`, the two `docs/HANDOFF-*` deletions,
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
`handoff-last-session.md` and `implement/handoff.md` were merged into §0.5 and
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
