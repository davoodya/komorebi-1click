# komorebi-1click: Architectural Knowledge Base & Technical Invariants

This document outlines the operational rules, core mechanisms, script inventories, and system properties required to successfully maintain and translate the `komorebi-1click` Admin Dashboard into Rust + Tauri.

---

## 1. Project Mission & Central Architecture

The `komorebi-1click` project provides a fully offline, one-click installer and management suite for Windows 11 tiling window management, bundling:
- **Komorebi 0.1.41**: Tiling window manager core.
- **WHKD 0.2.10**: Low-level global keyboard hotkey daemon.
- **YASB Reborn 2.0.7**: Highly configurable modern status bar.
- **AutoHotkey v1 (1.1.30) & v2 (2.0.12)**: Helper scripts for desktop workflow.

### The Central Architectural Invariant (ADR-0009 / ADR-0015)
> **The Dashboard owns NO system management logic.**

Every single action exposed on the GUI or CLI twins maps directly to an underlying PowerShell script located in the `scripts/` directory. The Dashboard serves as a high-speed, modern, ergonomic shell over this robust script layer.

```
┌────────────────────────────────────────────────────────┐
│                   Dashboard Frontend                   │
│   (Tauri Webview: Fluent UI, Tabs, Sliders, Console)   │
└───────────────────────────┬────────────────────────────┘
                            │ Tauri IPC (Commands / Events)
┌───────────────────────────▼────────────────────────────┐
│                    Rust Core Backend                   │
│   (Verb Registry, Process Tree Manager, SettingsStore) │
└───────────────────────────┬────────────────────────────┘
                            │ Async Process Streaming (pwsh.exe / powershell.exe)
┌───────────────────────────▼────────────────────────────┐
│                  PowerShell Scripts                    │
│   (kill-all, restart-all, komorebi-service, ahk, ...)  │
└────────────────────────────────────────────────────────┘
```

---

## 2. Pinned Stack & Environment Facts

### 2.1 Host Environment
- **OS**: Windows 11 Pro 64-bit (`10.0.26200.0`).
- **User Account**: `DavoodYa` (Standard User, **NOT** in local Administrators).
- **Display Setup**:
  - D1 (Primary, Front): Dell 1920x1080 Landscape (100% scale).
  - D2 (Top): Samsung 1920x1080 Landscape (100% scale).
  - D3 (Right): Dell 1080x1920 Portrait (125% scale).
- **PowerShell Toolchains**:
  - PowerShell 7.x (`pwsh.exe`): Target for modern features.
  - Windows PowerShell 5.1 (`powershell.exe`): Shipped inbox fallback. All scripts are compatible with both.

### 2.2 Elevation Strategy
Because the active user is not an Administrator, silent elevation (`-Verb RunAs`) will fail in automated runs. The only approved method to execute at `High` integrity is triggering pre-configured Windows Scheduled Tasks:
- `Start-ScheduledTask -TaskName 'Komorebi'` (Runs at `RunLevel=Highest`).
- `Start-ScheduledTask -TaskName 'KomorebiWatchdog'` (Runs at `RunLevel=Highest`).

When an administrative script must be run directly from the Dashboard (e.g., install/uninstall), the Dashboard must:
1. Detect whether it is running with an elevated token.
2. If unelevated, prompt the user with an Elevation Dialog.
3. Relaunch itself elevated (`runas`) and gracefully exit the medium-integrity instance.

---

## 3. Shipped Management Scripts & Verb Registry

The Dashboard exposes **35** primary verbs organized into tabs:

### Tab 1: Kill and Start (`Tabs.KillStart`)
- `kill-all`: Stop Komorebi, WHKD, and YASB (`kill-all.ps1 -Components all`).
- `kill-komorebi`: Stop Komorebi and WHKD (`kill-all.ps1 -Components komorebi-whkd`).
- `kill-whkd`: Stop WHKD standalone (`kill-whkd.ps1`).
- `kill-yasb`: Stop YASB only (`kill-all.ps1 -Components yasb`).
- `start-all`: Start Komorebi, WHKD, and YASB (`start-all.ps1 -Components all`).
- `start-komorebi`: Start Komorebi and WHKD (`start-all.ps1 -Components komorebi-whkd`).
- `start-whkd`: Start WHKD via safe path (`start-whkd.ps1 -Force`).
- `start-yasb`: Start YASB (`start-all.ps1 -Components yasb`).

### Tab 2: Restart and Reloading (`Tabs.Restart`)
- `restart-all`: Safe full stack restart (`restart-all.ps1`).
- `restart-komorebi`: Restart Komorebi + WHKD (`restart-komorebi.ps1`).
- `restart-whkd`: Restart WHKD via task scheduler (`restart-whkd.ps1`).
- `restart-yasb`: Restart YASB with PATH rebuilt from registry (`restart-yasb.ps1`).

### Tab 3: Settings & Configuration (`Tabs.Settings`)
- `startup-install`: Register logon + watchdog tasks (`komorebi-service.ps1 -Action install`).
- `startup-remove`: Unregister tasks (`komorebi-service.ps1 -Action uninstall`).
- `export`: Export the configuration — a directory selector opens and the chosen folder gets a new `komorebi-backup-<timestamp>\` holding the whole config set (`komorebi-backup.ps1 -Mode export`).
- `import`: Import the configuration — a directory selector opens and the chosen backup REPLACES the live config, with a rollback copy of the current config first (`komorebi-backup.ps1 -Mode import`).
- `set-transparency`: Adjust window opacity (`toggle-transparency.ps1 -Percent <0-100>`).
- `ignore-dashboard`: Add `ignore_rules` entry for the dashboard executable into `komorebi.json` (`ignore-dashboard.ps1`).
- App Settings: Folder openers, Factory Reset, and Command Cancellation.

### Tab 4: Customization (`Tabs.Customization`)
- Live Theme switching: Dark / Light.
- Accent Color selection: 8 presets (`Blue`, `Indigo`, `Violet`, `Rose`, `Amber`, `Emerald`, `Teal`, `Slate`) + Custom HEX picker.
- Font Family & Base Font Size settings.
- Console Font Family (Cascadia Mono / Consolas) & Console Font Size.
- Console Height Percentage Slider (Default: 35%).
- UI Scaling factor (100%, 125%, 150%).
- Apply Settings: Pushes changes to disk and notifies running components.

### Tab 5: AutoHotkey Scripts (`Tabs.AutoHotkey`)
- `ahk-enable-all`: Enable all scripts in `AppRunner.vbs` (`ahk-toggle.ps1 -State enabled`).
- `ahk-disable-all`: Disable all scripts (`ahk-toggle.ps1 -State disabled`).
- Per-script toggle controls:
  1. `autocorrect` (System-wide spelling correction).
  2. `ChangeLangF3` (Language toggle on F3).
  3. `NewFile` (`Ctrl+Win+N` context file creation).
- `ahk-versions`: Diagnostic probe for AHK v1/v2 paths.
- `ahk-newfile-check`: Diagnostic check for `NewFile` script.
- `ahk-diagnose`: Comprehensive AHK state dump.

### Tab 6: Debugging (`Tabs.Debugging`)
- `status`: Read-only health probe (`komorebi-service.ps1 -Action status`).
- `recover-monitors`: Retile and recover lost windows after display sleep/unplug (`recover-monitors.ps1`).
- `display-diag`: Diagnostic geometry report (`display-diag.ps1`).
- `reset-workspaces`: Renumber workspaces 1..9 on all monitors (`reset-workspaces.ps1`).
- `repair-whkdrc`: Re-encode and fix syntax in `whkdrc` (`repair-whkdrc.ps1`).
- `demo-stream`: Benchmark streaming output without system side-effects (`demo-stream.ps1`).

### Tab 7: Uninstall & Cleanup (`Tabs.Uninstall`)
- `uninstall`: Uninstall selected scope (`all`, `komorebi-whkd`, `yasb`, `autohotkey`).
- `cleanup`: Remove scheduled tasks, shortcuts, registry entries, and `%USERPROFILE%\.config` traces.

### Tab 8: About (`Tabs.About`)
- Identity: Product Name, Version, Platform, Git SHA.
- Paths: Running binary location, Scripts directory, `%APPDATA%` settings path.
- Author: Davood Yahay (DavoodSec) with clickable links (`davoodya.ir`, `github.com/davoodya`).

---

## 4. Execution & Threading Principles (The "No Lag" Mandate)

1. **Pure Asynchronous Process Execution**: Process execution must never block the main UI loop or Tauri async runtime.
2. **Process Tree Lifecycle & Cancellation**: When an execution is cancelled or times out, the entire process tree must be cleanly terminated (e.g. `taskkill /F /T /PID` on Windows or job objects in Rust).
3. **Stream Throttling**: Standard output and error streams must be buffered and throttled (~30–50ms intervals) before broadcasting to the frontend, preventing event queue flooding during high-volume logs.
4. **Guaranteed Cleanup**: Named pipes, mutexes, and temporary files must be tracked and freed upon application exit.

---

## 5. Test thresholds and the cheatsheets

* **Timing assertions are dual-mode** (ADR-0019). `tests/rust-ticket02-probe.ps1`
  takes a threshold mode: **strict** is the default and the only mode a release may
  pass; **relaxed** is opt-in (`-Relaxed`, `-ThresholdMode relaxed`, or
  `DASHBOARD_THRESHOLD_MODE`) for a busy local machine, and the mode is recorded
  with the result so a relaxed pass is never mistaken for a strict one. The probe
  prints its mode on line 1 and carries it in every assertion message; `-Strict`
  conflicting with a relaxed parameter exits 3. Note
  `DASHBOARD_THRESHOLD_MODE` does not cross the WSL→Windows interop boundary —
  pass the parameter explicitly from WSL.
* **Cheatsheets are bilingual** (ADR-0020). Each lives as
  `cheatsheets/fa/<name>.md` (Persian, authoritative) and
  `cheatsheets/en/<name>.md` (English, translated), cross-linked in the header.
  Hotkeys and commands are copied verbatim — only the description column is
  translated — so the two files provably describe the same configuration. The
  dev-tree source at `~/projects/komorebi-1click/cheatsheets/` is newer than the
  published copies; update from there.
* **AHK lifecycle pitfalls (found live, 2026-10-10).** Two traps cost a debug
  cycle each, and both now have static regression guards in
  `tests/ticket08-ahk.tests.ps1` section 9: (1) a process-match `-like`
  pattern that references a quoted script path must carry the trailing `*`
  (`"...\ChangeLangF3.ahk*"`), otherwise it never matches the live command
  line and a disable silently leaves the process running — the next enable
  then starts a duplicate; (2) PowerShell variable names are case-insensitive,
  so a local `$state` in a script whose param is `[ValidateSet] $State` IS
  that parameter, and assigning to a ValidateSet variable re-runs the
  attribute validation immediately — the assignment throws and the script dies
  where it stands. Never reuse a parameter name as a local.
* **The registry is the single source of truth** for verbs and tabs. Frontend and
  backend both derive from `registry.rs`; never maintain a second list. The verb
  count is 35 (asserted by
  `the_documented_counts_are_the_counts_the_table_actually_has`, which derives it
  from the table — do not hand-count).

---

## 6. Repo hygiene, the two ticket tracks, and host facts

* **The repo hosts two workstreams, and their ticket numbers collide.** The
  installer track (tickets 01-14) lives only in the dev tree at
  `~/projects/komorebi-1click/.scratch/komorebi-1click-installer/`; the Rust
  translation track (tickets 01-13) has its specs under
  `docs/rust-translate/` and a dev mirror at
  `~/.scratch/rust-translate/issues/`. Ticket `04` is `eight-tabs` in one track
  and `startup-tasks` in the other — establish which track a prompt means
  before executing.
* **`cheatsheets/` is gitignored** (`.gitignore` line 36). The bilingual
  cheatsheets are local reference documents; nothing in them is ever committed,
  so "committed" claims never apply to them. The tracked script documentation
  is `scripts/SCRIPTS-GUIDE.md` (English) and `scripts/SCRIPTS-GUIDE.fa.md`
  (Persian).
* **The shipped-text checker scans the docs too.** Persian digits count as
  foreign script; new or edited documents must pass
  `tests/check-shipped-text.mjs` before a baseline is claimed green (defect R5).
* **The startup machinery's canonical implementation** is `Install-StartupTasks`
  in `scripts/Install-Common.ps1` (installer ticket 04). The legacy duplicate,
  `komorebi-service.ps1 -Action install`, now refuses when unelevated instead
  of registering Medium-integrity tasks (ADR-0016), and `-Action status`
  reports YASB and its autostart entry next to komorebi and whkd. See
  `bugs-fixing.md` §1.9.
* **The AutoHotkey startup is generated, never copied.** `autohotkey\AppRunner.vbs`
  is a template with no machine paths; `Get-GeneratedAppRunnerContent` renders
  it into `%APPDATA%\...\Startup\AppRunner.vbs` with three `RunHidden` lines
  (mode 0, hidden) — v1 interpreter for `autocorrect.ahk` and `ChangeLangF3.ahk`,
  v2 interpreter for `NewFile.ahk` — and `Test-AppRunnerUpToDate` makes a
  re-run skip when the file already matches.
* **Persisted state must be layered onto the manifest before any render.**
  `Set-AhkEnabledState` (Install-Common.ps1) writes `autohotkey\ahk-state.json`
  and regenerates the Startup VBS through `Apply-AhkEnabledState` first; any
  future writer of that seam must do the same or the state file and the Startup
  folder disagree (defect R6). Tests assert on the generated VBS, never only on
  the state file.
* **The two registry tables drift silently unless a parity test reads both.**
  `src/KomorebiDashboard/Services/VerbRegistry.cs` (WPF) and
  `src/KomorebiDashboardRust/src-tauri/src/registry.rs` (Rust) are
  hand-maintained twins: the Rust header says every row was moved by a parser,
  but that parser is NOT in the repo, so nothing mechanical kept them in step.
  `tests/ticket10-registry-parity.tests.ps1` now parses both tables and
  requires field-by-field equality, with a reviewed exemption list for the
  sanctioned direction (Rust is the active table per roadmap Q4 — it ships
  alongside the WPF EXE until Phase 4). A new Rust-only verb, a C#-only verb,
  or an unreviewed field difference now fails. The reviewed list
  (`ignore-dashboard` since ticket 03; the export/import/demo-stream copy
  since ticket 07) is the audit's evidence, not a silent allow-list: it was
  proven by re-running the suite against drifted copies (renamed label, new
  verb, changed script — all three failed).
* **Three installer entry points, one code path.** `komorebi-1click-install.exe`
  (csc-built C# wrapper, ticket 09) locates `Install.ps1` next to itself,
  relaunches itself elevated when needed, and forwards the exit code — it is
  thin by design. A direct `.\Install.ps1` run sets `$PSScriptRoot` and works
  as-is. Under `irm ... | iex` there is NO file behind the script, so
  `$PSScriptRoot` is EMPTY: the installer's bootstrap branch resolves the repo
  from `KOMOREBI_1CLICK_ROOT` (a local clone), else fetches the release archive
  into `%LOCALAPPDATA%\komorebi-1click`, then re-execs the on-disk
  `Install.ps1` with the same parameters — `exit $LASTEXITCODE` at the handover
  terminates the iex session, which is exactly what a user's shell sees.
  E2E proof lives in `tests/ticket09-irm-e2e.tests.ps1` (recording stub,
  sentinel exit 7) — the bootstrap's `exit` also kills any test driver that
  runs the iex in-process, so the assertion side MUST live in a parent process.
* **The build host is Windows**: `cargo`/`npm` run through `win-exec.sh` with
  `ALLOW_WINDOWS=1` from WSL; a WSL-native build is not the contract. The
  wrapper has no console, which is why console-control-event tests SKIP there
  (defect R3), and it does not propagate WSL environment variables across the
  boundary — pass parameters explicitly.
* **`role="tab"` buttons are TabItems in the accessibility tree, not Buttons.**
  When runtime-verifying the strip over UIA (ticket 04, session 7), the eight
  tab controls surfaced as `ControlType.TabItem` — `FindAll(ControlType.Button)`
  returned zero of them while the verb action buttons on the same window were
  ordinary Buttons. Drive them with `SelectionItemPattern.Select()` (Invoke is
  absent), and read selection state from `SelectionItemPattern.Current.IsSelected`
  rather than from `aria-selected` text. Filtering by Name alone is the robust
  lookup: the tab's label also appears as the panel heading's Text element.
  Evidence script: `tests/.build/uia-ticket04-eight-tabs.ps1`.
* **A negative-pid `process.kill` and a `detached: true` process group are POSIX
  facts that are false on Windows.** `detached: true` is `DETACHED_PROCESS` (no
  console), not `CREATE_NEW_PROCESS_GROUP`, and Node's `process.kill` has no
  negative-pid semantics there — so a harness signal built on both throws ESRCH
  against a live child. The Windows delivery for a console control event is
  `GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, pid)` against a
  `CreateProcessW(..., CREATE_NEW_PROCESS_GROUP)` child sharing the caller's
  console (defect R7; applied in session 8 as
  `tests/rust-ticket03-signal.ps1`, driven by case 1 of
  `tests/rust-ticket03-interrupt.mjs`).
* **`CreateProcessW` through PowerShell P/Invoke needs BOTH `lpApplicationName`
  and a valid `lpCurrentDirectory`.** Passing `$null` for the application name
  fails with win32 123 (invalid name) or 3 (path not found) even when the
  command line is well-formed, and a bad cwd fails the same way; supplying the
  exe path in both places is the reliable recipe. `lpCommandLine` still carries
  the full line (exe + argv).
* **Node cannot hand an argument array to `pwsh -File`.** `powershell -File
  script.ps1 -Arguments @("a","b")` mangles the array into one unusable token
  (a `ping -n` arrived as a bare `-n`); pass argv as a JSON file and let the
  script re-read it (`-ArgumentsFile` in the signal helper).
* **A test that asserts on a file being concurrently hand-edited measures the
  editor, not the artifact.** The whkdrc binding assertions now read the
  **committed** template (`git show HEAD:config/whkdrc` — what an install
  actually ships) and a working-copy divergence is reported as a loud WARN
  naming the missing binding, never a FAIL and never a silent pass
  (session 8, `tests/ticket05-06-07.tests.ps1`).
* **A shape guard belongs BEFORE the elevation gate; both belong before the
  launch.** The Rust core refuses three malformed/missing things per verb with
  its own exit code (unknown verb 2, missing value 2, missing script 127) and
  the gate (**740**, the spec's number) last: a malformed request is malformed
  whatever the process's privilege, so "you must provide a value" is the more
  specific answer; but a well-formed administrative request must NEVER reach a
  process launch without passing the gate. Placing the gate between the guards
  and the launch is what let one pure function serve both the window and the
  CLI (session 11, `dashboard_core::elevation_gate`,
  `EXIT_NEEDS_ELEVATION = 740`). The first wiring ordered gate-before-guards
  and broke `dispatch.rs`'s "uninstall needs a value" test — the suite was
  right, the order was wrong.
* **The spec's exit code is the contract, not the neighbouring product's
  convention.** The first cut used 5, "matching the installer wrapper's
  elevation refusal" — and two independent reviewers caught it in the same
  pass: ticket 05, the spec, the roadmap, the codebase inventory and ADR-0017
  all document **740** for a dashboard dispatch refused for missing
  elevation, and the installer wrapper's 5 is a different product's number.
  When implementing against a spec, the spec's documented number is normative;
  a second convention in the same repo is drift (ADR-0018 §1), however
  reasonable it looks.
* **The elevation probe must ASK the OS, and the meeting point between the
  window's knowledge and the CLI's must be one function.** The Rust twin gates
  in `dashboard_core::elevation_gate` (pure: `verb.requires_admin && !elevated`)
  with a thin Windows-only probe (`OpenProcessToken` +
  `GetTokenInformation(TokenElevation)` behind two `extern "system"`
  declarations — the same no-windows-crate pattern the console module uses);
  both the Tauri command and the CLI call the same `run()`, so the dialog's
  feature list (`adminFeatures(registry.verbs)` in TypeScript) and the
  CLI's exit-740 message (`admin_feature_labels()` in Rust) are generated from
  the SAME table and can never name different features.
* **A dialog whose title and buttons are typed into the markup is a second
  contract.** The Rust dialog renders `ELEVATION_DIALOG_TITLE` /
  `ELEVATION_DIALOG_BUTTONS` from `src/lib/elevation.ts`, and the static suite
  (`tests/ticket12-rust-elevation.tests.ps1`) asserts the constants carry the
  ticket's exact wording — the same strings the WPF-era suite asserts against
  the WPF build. A rename now fails a test in both suites instead of drifting.
* **The theme switch is three pure functions plus one attribute set.** Rust's
  `src/lib/theme.ts` (parse stored / apply / flip) is tested against jsdom
  with a fake `Storage`, including the corrupted-value case (a junk stored
  theme must fall back to the documented default, never leave the document
  unstyled); `applyAppearance` sets `data-theme`/`data-accent` (the exact
  selectors the CSS declares) plus `color-scheme` for native controls. The
  WPF build's ThemeService was never the gap; the runtime switch was.
* **`win-exec.sh pwsh '<inline>'` wraps the script in `-Command "$2"` — so
  the inline script may contain single-quoted strings but never bare double
  quotes (the inner `"` closes the wrapper's quote and mangles the command),
  and never doubled single quotes `''` (an empty-string artifact that breaks
  the statement it stands in). The bash-safe spelling for a single-quoted
  string inside the argument is `'"'"'`. Bare paths need no quotes at all.
* **Never hand-type this repo's directory names.** `Komorb…`-style crate
  names have burned dozens of commands with one forgotten character
  (Set-Location silently failing, a fallback dir, "Exec format error"-ish
  confusion). Resolve them from an object instead — `(Get-ChildItem
  H:\Repo\komorebi-1click\src -Directory | Where-Object { $_.Name -like
  "*Rust*" }).FullName` — or glob them in Python and print, never transcribe.
* **A windows-subsystem EXE gives PowerShell nothing when called as
  `& $exe args`** — no stdout shape, no `$LASTEXITCODE` (both came back empty
  and looked like a broken build). The working recipe is `Start-Process
  -Wait -RedirectStandardOutput file -RedirectStandardError file` + the
  `-PassThru` process object's ExitCode; that is also how the sandbox suite
  drives the published EXE. This is how the ticket-12 gate was proven through
  the real shipped binary (exit 740 + the feature list on stderr + a
  0-byte stdout).
* **`cargo tauri build` reports `Built application at: <package-name>.exe`
  while the actual artifact on disk is the Cargo `[[bin]]` name** — trust
  `Get-ChildItem target\release -Filter *.exe`, and when copying into
  `releases/`, copy by the destination's own `$oldFile.Name` object, not a
  typed path (the typed copy produced a second, differently-spelled file).
* **`tests/sandbox-test-suite.ps1` RUNS THE INSTALLER.** On the production
  reference machine it may only be parser-checked (ParseFile via a temp
  .ps1 invoked with -Command), never executed; the live run is the Sandbox's
  job, launched from `tests/sandbox-test-harness.ps1`.
* **`releases/rust/*` is DELIBERATELY untracked** (`.gitignore`: only
  `.gitkeep`; the last commit touching it, d8d9906, "drop a dead asset"). A
  rebuilt dashboard EXE lives on disk and its identity lives in
  `tests/rust-release-pins.json` — do not `git add` the EXE and do not write
  its size/hash into suites or docs inline: the Sandbox §T13 reads the pins
  file, the docs cite it, and one rebuild edits one file.
* **A `Result` banner is a section boundary, not a bookmark.** Appending a new
  ticket block before `Section 'RESULT'` still leaves it AFTER the
  `# ====...\n# Result\n# ====...` banner comment — insert before the banner
  itself, and parser-check (`ParseFile`) the suite before claiming a section.
* **`if ($artifact) { ...probes... }` is a silent skip waiting to happen.**
  A missing build artifact must cost the run an assertion in the OPEN (fail),
  not quietly turn the probes into "unreported".
