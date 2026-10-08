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
