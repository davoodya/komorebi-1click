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
- `export`: Export config ZIP (`komorebi-backup.ps1 -Mode export -ZipPath [dir]`).
- `import`: Import config ZIP (`komorebi-backup.ps1 -Mode import -ZipPath [file]`).
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
* **The build host is Windows**: `cargo`/`npm` run through `win-exec.sh` with
  `ALLOW_WINDOWS=1` from WSL; a WSL-native build is not the contract. The
  wrapper has no console, which is why console-control-event tests SKIP there
  (defect R3), and it does not propagate WSL environment variables across the
  boundary — pass parameters explicitly.
