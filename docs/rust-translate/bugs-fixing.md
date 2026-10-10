# komorebi-1click: Known Bugs, Issues, and Fixes (Knowledge Base)

This document aggregates and synthesizes all defects, architectural traps, edge cases, and postmortem findings discovered during the development, debugging, and verification of the `komorebi-1click` stack and its Admin Dashboard. It serves as an authoritative guide for the Rust + Tauri rewrite.

---

## 1. Lethal System & Window Manager Traps

### 1.1 WHKD Shell Panics (Trap T1 / Defect A1)
- **Symptom:** WHKD fails immediately on startup or panics, completely dropping all hotkeys across the entire operating system, while Komorebi itself appears healthy.
- **Root Cause:** WHKD 0.2.10 source code strictly asserts `.shell` in `whkdrc` to be one of three values: `cmd`, `powershell`, or `pwsh` (`panic!("unsupported shell")`). Any other shell binary or syntax causes a panic.
- **Invariant:** Shipped `config/whkdrc` must preserve `.shell powershell` (or `pwsh`). The Rust Dashboard must never alter or regenerate this header with invalid shell names.

### 1.2 WHKD Pairing & Integrity Level Requirement (Trap T2 / Defect A2)
- **Symptom:** WHKD process is running, Komorebi is running, but hotkeys are completely ignored/dead.
- **Root Cause:** In Komorebi/WHKD architecture, WHKD must be launched via `komorebic start --whkd`. If WHKD is launched standalone or from an unelevated context, it registers global hooks but cannot communicate with Komorebi's named pipe (`\\.\pipe\komorebi`), which runs at High Integrity Level (`RunLevel=Highest`).
- **Invariant:** Never launch `whkd.exe` directly from the Dashboard. Starting WHKD standalone is explicitly forbidden. It must delegate to `restart-whkd.ps1` or `komorebic start --whkd`.

### 1.3 Silent Config Key Drop in Komorebi JSON (Trap T3 / B1)
- **Symptom:** Rules added to `komorebi.json` do not take effect, yet `komorebic check` exits with 0.
- **Root Cause:** Komorebi 0.1.41 deserialization silently ignores unknown or legacy fields without warning. For example, `manage_rules` (correct) vs `manage_identifiers` (ignored), `tray_and_multi_window_applications` (correct) vs `tray_and_multi_window_identifiers` (ignored).
- **Invariant:** When generating or modifying `komorebi.json` (such as `ignore-dashboard`), key names must strictly match the current schema.

### 1.4 Watchdog Double-Start Race (Trap T6 / Defect A10)
- **Symptom:** Workspace layout collapses, windows randomly disappear or tile incorrectly after restarts.
- **Root Cause:** A 5-minute scheduled watchdog task (`KomorebiWatchdog`) wakes up during a restart window, detects that `komorebi.exe` is temporarily absent, and starts a secondary instance against the same named pipe.
- **Invariant:** All restart operations must acquire the named global mutex `Global\komorebi-service-start` and temporarily disable/freeze `KomorebiWatchdog`.

### 1.5 Watchdog Permanent Disabling Bug (Trap T11 / Defect D4)
- **Symptom:** `KomorebiWatchdog` remains permanently disabled on the host machine (`188 missed runs`).
- **Root Cause:** Scripts disabled the task and checked `if ($watchWasEnabled) { Enable-ScheduledTask }`. If an operation was cancelled or crashed, the task remained disabled, and subsequent runs saw `State == Disabled` and never re-enabled it.
- **Fix & Invariant:** Any task management that freezes the watchdog must ensure restoring via `finally` blocks, or the Dashboard backend must guarantee state restoration.

### 1.6 Elevation & UAC Integrity Boundary (Defect A3)
- **Symptom:** After an unelevated restart, elevated windows (e.g. Administrator terminals, Task Manager, Hermes) cannot be tiled or focused.
- **Root Cause:** Windows UIPI (User Interface Privilege Isolation) prevents a Medium Integrity process from controlling High Integrity windows. On Davood's host, the user account `DavoodYa` is not in the Administrators group by default, so silent elevation via `runas` fails without credentials.
- **Invariant:** Komorebi and WHKD must be launched via the Windows Task Scheduler task `Komorebi` set to `RunLevel=Highest`.

### 1.7 Elevation Probe False Negatives (Defect A3)
- **Symptom:** Health check reports the process is not elevated when it actually is.
- **Root Cause:** Using `OpenProcess` with access mask `0x0410` (`PROCESS_QUERY_INFORMATION`) is denied under UIPI for elevated processes from a medium token.
- **Invariant:** The probe must use `0x1000` (`PROCESS_QUERY_LIMITED_INFORMATION`) before querying `TokenIntegrityLevel`.

### 1.8 Multi-Monitor Geometry Mismatches & Negative Bounds (Defect A4)
- **Symptom:** Health check reports `DEGRADED (3 problems)` on a fully functional 3-monitor setup.
- **Root Cause:**
  1. `komorebic state` stores monitor width/height inside `right` and `bottom` fields rather than coordinate offsets.
  2. DPI scaling differences (e.g. 125% scale on portrait monitor) cause WinForms logical bounds to differ from physical pixels.
- **Invariant:** Query per-monitor DPI through Device Contexts; do not flag zero-size containers or empty workspace names as errors.

### 1.9 The Startup Machinery Existed Twice, and the Second Copy Was Weaker (fixed session 5, installer ticket 04)

- **Symptom:** `2-ADD-TO-STARTUP.bat` → `komorebi-service.ps1 -Action install`
  registered the `Komorebi` and `KomorebiWatchdog` scheduled tasks at
  `-RunLevel Highest` **only when the shell was already elevated**. From an
  unelevated shell it silently registered Medium-integrity tasks — exactly the
  delayed regression ADR-0016 exists to prevent (elevated windows become
  unmanageable, and only *after* the first watchdog respawn drops Komorebi back
  to Medium integrity). On this host (`DavoodYa` is a standard user) that path
  always produced the broken state. The legacy action also never set up YASB
  autostart or the `komorebic` PATH entry, so it was a partial duplicate of the
  canonical machinery. Separately, `-Action status` reported komorebi and whkd
  but had zero YASB awareness, while its ticket requires status to confirm
  **all three** are running.
- **Fix & Invariant:** `-Action install` now refuses **before** it builds or
  registers anything when the shell is unelevated, naming the elevated entry
  points (the EXE wrapper, `Install.ps1` via "Run as administrator"); the
  unelevated fallback branch is deleted, so the task is registered Highest
  unconditionally. `Get-Health`/`Show-Status` gained `Yasb`, `YasbUptime` and
  `YasbAutostart` (Run key or Startup shortcut — the same test
  `Install-Common.ps1` performs), and a missing bar or autostart entry counts as
  a problem. Verified by parser (0 errors), a live read-only `-Action status`
  (yasb `True`, autostart `True`, verdict HEALTHY), and a live unelevated
  `-Action install` that threw the refusal and touched nothing.
- **General rule:** two code paths implementing the same machinery diverge
  silently, and the weaker one is exactly what a user finds first. One canonical
  implementation (`Install-StartupTasks`) plus a loudly failing duplicate is
  safer than a "compatible" second copy.

---

## 2. WPF / .NET Dashboard Historical Deficiencies & Lessons

### 2.1 The Silent Blank Window / DWM Mica Backdrop Defect (Defect D21)
- **Symptom:** Launching the dashboard resulted in a completely black or empty window; or theme toggle only changed titlebar text.
- **Root Cause:** WPF-UI 4.x `FluentWindow` attempts DWM Mica/Acrylic composition that fails on non-standard hardware/driver configurations or within certain virtual/composited desktop environments.
- **Lesson for Tauri:** In Tauri, Webview2 handles hardware acceleration natively. Acrylic/Vibrancy effects must be applied conditionally via Tauri window attributes (`window-vibrancy` crate) with graceful fallbacks.

### 2.2 Relative Pack URIs in WPF (Defect D26/Session 3)
- **Symptom:** Crash on startup with `XamlParseException: Cannot locate resource 'resources/icon.ico'`.
- **Root Cause:** WPF pack URIs without assembly qualifiers resolve against the entry assembly, breaking when run under test harnesses or wrappers.
- **Lesson for Tauri:** Asset bundling in Tauri uses standard frontend asset paths (e.g. `/assets/logo.ico`) and embedded Rust binary resources via `tauri::include_image!` or standard static file serving.

### 2.3 Broken Parameter Binding in Verbs (Defects D23, D24)
- **Symptom:** Clicking buttons for `startup` or `ahk` resulted in instant script failure (`Cannot validate argument on parameter 'Action'`).
- **Root Cause:** Registry entries were written against outdated design specifications rather than querying the actual PowerShell `param([ValidateSet(...)])` block of the target script (e.g. passing `add` instead of `install`).
- **Lesson for Tauri:** The Rust `ScriptService` must strictly define strongly-typed command mappings matching the exact script CLI contract.

### 2.4 ControlTemplate Instantiation Crash (Session 4)
- **Symptom:** App compiled cleanly with zero warnings, then crashed with `0xE0434352` upon opening a specific tab.
- **Root Cause:** XAML templates evaluate bindings and setters lazily upon view instantiation.
- **Lesson for Tauri:** Compile-time type checking in Rust and TypeScript guarantees that all props, commands, and events are verified before runtime.

### 2.5 Console Pane Height State Desynchronization (Session 4)
- **Symptom:** Moving the console height slider did not affect open tabs.
- **Root Cause:** ViewModels only read the setting during construction instead of subscribing to a reactive store.
- **Lesson for Tauri:** Use a centralized reactive state store (e.g. Svelte store / React state / Zustand / Vue reactive) coupled with Tauri event broadcasting.

### 2.6 WPF Window Misplacement under Komorebi (Session 4 `ignore-dashboard`)
- **Symptom:** Komorebi attempts to manage and tile the Dashboard window, causing flickering or pushing it across monitor boundaries on 3-monitor setups.
- **Solution:** A dedicated rule in `komorebi.json` under `ignore_rules` for the dashboard executable (`KomorebiDashboard.exe`, and in the future the Tauri executable `komorebi-dashboard.exe`).

---

## 3. Rust / Tauri Translation — Defects Found During Implementation

### 3.1 Caller Budget Silently Ignored (Defect R1, ticket 03)

- **Symptom:** `dashboard demo-stream -Lines 4000 -TimeoutSeconds 5` ran for the full
  300 s default instead of being stopped after 5 s. No error, no warning — the run
  simply ignored the budget the caller asked for.
- **Root Cause:** `-TimeoutSeconds` belongs to the **caller**, not the script, so it
  is stripped from the argument vector before dispatch (`strip_timeout_option`).
  `execute()` sourced its budget from that same vector via `timeout_for(arguments)`.
  Stripping first removed the only occurrence, so `timeout_for` always found nothing
  and fell back to `DEFAULT_TIMEOUT` — silently, because "no option present" and
  "option just removed" are indistinguishable at that point.
- **Fix & Invariant:** Resolve the budget from the **original** arguments *before*
  stripping, then pass it into `execute` explicitly as a parameter. The two can no
  longer disagree, and `execute` cannot re-derive it from a vector it does not own.
  Pinned by `a_caller_budget_is_read_before_the_option_is_stripped`, which asserts
  both halves: the original yields 5 s, and the stripped vector yields the default.
- **General rule:** When one piece of the input is consumed early, every value
  derived from that input must be read *before* the consumption. "Parse, then
  consume" — never "consume, then parse".

### 3.2 `status` Was One Argument Away From Being an Admin Operation (Defect R2, ticket 03)

- **Symptom:** `dashboard status -Action install` would have invoked
  `komorebi-service.ps1 -Action status -Action install`, letting the last `-Action`
  win — an administrative install triggered from an unprivileged read-only health
  check, with no elevation gate in front of it.
- **Root Cause:** The registry declares `status` with `RequiresAdmin: false` (it is
  read-only) **and** the fixed arguments `-Action status`. A naive "does this verb
  take arguments?" test written as `arguments.is_empty()` counts the **fixed**
  arguments too, so a verb carrying the most dangerous fixed flags is exactly the
  one that gets exempted — backwards.
- **Fix & Invariant:** Decide the rule from the declared **shape**, not from the
  vector: a verb takes user arguments only if its shape mentions a value
  (`accepts_user_arguments`, i.e. `<...>` or `[...]`). `fixed_arguments` must never
  satisfy that test. When the shape declares no value and arguments were supplied,
  refuse with exit 2 *before* launching anything.
- **Note:** `status` also demonstrates why refusal must name the verb: the message
  and the usage line are what tell the user which row rejected them.

### 3.3 Console Control Events Are Undeliverable on a ConPTY Host (Defect R3, ticket 03 / US 55)

- **Symptom:** A real interrupt test for `Ctrl+C cancels the child` could not
  produce a delivered event. The signal call returned success while the child never
  received anything, so a naive test would either hang or assert a false pass.
- **Root Cause:** The session runs on a **ConPTY pseudo-console**:
  `GetConsoleWindow() == 0`, `GetConsoleProcessList` reports only the calling
  process, and `AllocConsole()` fails with `ERROR_ACCESS_DENIED (5)`. Windows does
  not deliver `GenerateConsoleCtrlEvent` to a process group on that topology. With
  `CREATE_NO_WINDOW` — the flag the child launcher actually uses — the call itself
  fails with `ERROR_INVALID_HANDLE (6)`.
- **Measured, four topologies:** sharing the harness console, `CREATE_NEW_CONSOLE`,
  `CREATE_NEW_CONSOLE` + `AttachConsole` (which itself returned
  `ERROR_ACCESS_DENIED`), and `CREATE_NO_WINDOW`. **None** delivered an event, with
  a child that installed a real `SetConsoleCtrlHandler` and wrote a marker file the
  instant one arrived — so "no marker" is evidence, not an assumption.
- **Invariant:** A test for an OS delivery mechanism must **prove delivery** (a
  handler-installed marker), never infer it from the signal call returning success
  or from the child happening to die. Where the host cannot deliver the event, the
  suite reports `SKIP` with the measured OS error and the harness to run it in a
  real console — a skip is honest, a false pass is not.
- **Related trap (avoided on purpose):** `AttachConsole` rebinds this process's
  standard handles onto the console it attaches to, so calling it unconditionally
  **destroys output capture** — `dashboard status | grep up` would return nothing.
  The WPF build documented this and attached never; the Rust CLI attaches only when
  `GetConsoleWindow()` is null *and* stdout is a real terminal, giving up
  interruptibility rather than losing redirected output.

### 3.4 The Tracer's Placeholder Became a Security Regression When the Table Grew (Defect R4, ticket 03)

- **Symptom:** After the registry grew from 2 verbs to 35, the GUI tab would have
  drawn an administrative verb (`uninstall`) inside the **Debugging** tab.
- **Root Cause:** The ticket-01 tracer placeholder returned the **whole** table as
  the current tab's rows. That was byte-for-byte correct with two verbs and wrong
  the moment the table had more than one tab's worth.
- **Fix & Invariant:** Rows come from `rowsForTab(verbs, tab)`, filtering on the
  registry's own `tab` field **and** `render_in_gui`. The frontend test asserts a
  read-only tab can never contain a `requires_admin` row, and that a CLI-only verb
  (`startup`, superseded by `startup-install` / `startup-remove`) draws no row.
- **General rule:** A placeholder that happens to be correct for the sample size is
  not correct — when the real data arrives, re-read every placeholder that returned
  "all of it" and ask which subset it was actually standing in for.

### 3.5 A "Green Baseline" Was Copied Forward Past Its Own Regression (Defect R5, session 5)

- **Symptom:** The handoff recorded `tests/check-shipped-text.mjs` as
  `exit 0, 190 files`. Re-running it in the next session — before touching any
  code — produced `exit 1, 194 files`: three lines failed with Arabic-script
  codepoints (U+06F1, the Persian digit one).
- **Root Cause:** The session-4 documents (the session-4 log line, now
  `handoff.md` §0.3, and `ADR-0020-bilingual-cheatsheets.md` lines 43-44)
  illustrated the Jalali→Gregorian date conversion with the Jalali date
  written in Persian digit codepoints (U+06F0..U+06F9) instead of ASCII
  digits. The checker scans the docs, not only the shipped UI text, and the
  recorded baseline predated the new files — so the claim was stale, not
  measured.
- **Fix & Invariant:** The illustrative dates now use ASCII digits
  (`1405/07/09` = 2026-10-01); the suite passes again (194 files, exit 0).
  **A baseline is a measurement with a timestamp, not a status to copy
  forward.** After adding or editing any document, re-run
  `check-shipped-text.mjs` before claiming a green baseline — Persian digits are
  foreign script exactly like Persian letters (ADR-0017 rule 7).

### 3.6 The Persisted State and the Rendered Startup Disagreed (Defect R6, session 6, installer ticket 05)

- **Symptom:** `ahk-toggle.ps1 -State disabled` killed the AutoHotkey processes
  and wrote `autohotkey\ahk-state.json` correctly, but the regenerated
  `AppRunner.vbs` still carried every script as a live `RunHidden` line — so a
  machine that disabled a script had it silently back at the next logon.
- **Root Cause:** `Set-AhkEnabledState` in `scripts/Install-Common.ps1` wrote
  the state file and then called `New-AppRunnerVbs`, which renders from the
  in-memory `$script:AutoHotkeyScripts` manifest. Nothing applied the new state
  to that manifest first. The installer path (`Install-AutoHotkeyStartup`) was
  correct because it calls `Apply-AhkEnabledState` before rendering; the toggle
  path bypassed it, so the file and the artefact disagreed. The ticket-08 tests
  passed through the hole because their section 3 round-tripped the state file
  and never inspected the generated VBS — persistence is not the product.
- **Fix & Invariant:** `Set-AhkEnabledState` now calls
  `Apply-AhkEnabledState -RepoRoot $RepoRoot` after writing the file and before
  rendering, and `tests/ticket08-ahk.tests.ps1` gained two assertions that read
  the generated file — `the regenerated VBS comments out the disabled script`
  and `the regenerated VBS keeps the re-enabled script live` (19/19 green, and
  the two new assertions fail against the pre-fix code). **When persisted state
  drives a generated artefact, the test must read the artefact, not the
  state.**

### 3.7 The Interrupt Harness Could Never Deliver Its Signal on Windows (Defect R7, session 7)

- **Symptom:** case 1 of `tests/rust-ticket03-interrupt.mjs`
  (`delivered-interrupt`) SKIPs on every host with `ESRCH kill ESRCH`, and the
  handoff instructed "re-run on an interactive console to convert it into a
  PASS" — a path that could never work, on any console.
- **Root Cause:** the harness sends the interrupt with
  `process.kill(-child.pid, 'SIGBREAK')` against a child spawned with
  `detached: true`, and both are POSIX facts that are false on Windows:
  1. Node's `process.kill` has no negative-pid (process-group) semantics on
     Windows, so the call throws ESRCH even against a live child;
  2. `detached: true` maps to `DETACHED_PROCESS` (the child gets **no
     console**), not to `CREATE_NEW_PROCESS_GROUP` as the code comment
     claimed — so even a well-formed signal could not reach it, because a
     process without a console cannot receive console control events.
  Measured 2026-10-10 against a live, correctly-spawned child:
  `+pid, 0` OK; `-pid, 0` ESRCH; `-pid, SIGBREAK` ESRCH; `+pid, SIGBREAK`
  ENOSYS.
- **Fix & Invariant (designed, ticket 03 test-infra work, not yet applied):**
  the delivery must be a real `GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT,
  groupId)` — P/Invoke from PowerShell, the same family as the session-3
  probes and no new dependency — against a child created with
  `CREATE_NEW_PROCESS_GROUP` that shares the caller's console, behind a host
  gate that reports SKIP with the *measured* reason when no real console
  exists. The independent ConPTY limitation stays true (session-3's
  four-topology measurement): from a pseudo-console, even a correct call
  delivers nothing. **When a harness's own signal call throws ESRCH against a
  live child, the harness is broken, not the platform — measure the mechanism
  before re-diagnosing the host.**
