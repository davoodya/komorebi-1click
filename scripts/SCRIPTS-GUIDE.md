# SCRIPTS-GUIDE — Komorebi + WHKD + YASB

> **⚠ Read this before restarting whkd.**
> If hotkeys are dead but the YASB bar still shows workspaces, do NOT restart
> whkd — that cannot fix it. whkd must be spawned by `komorebic start --whkd`;
> started any other way it registers every hotkey and then drops every command
> (LGUG2Z/komorebi#956). The repair is `komorebic stop --whkd`, clear the stale
> socket/hwnd state, then `komorebic start --whkd`.
> `Get-Health` / `4-STATUS.bat` reports this as `whkd PAIRING`.
> Full write-up: `docs/POSTMORTEM-20261004-whkd-pairing.md`.

> **⚠ And before you start komorebi from a script.**
> An unelevated komorebi cannot manage elevated windows, so a restart run from
> a non-elevated shell drops every elevated window and the Hermes window out of
> the layout. `restart-whkd.ps1` and `safe-restart.ps1` handle this: when they
> are not already elevated they stop the pair and trigger the installer's
> `Komorebi` logon task (RunLevel Highest) to bring it back elevated. Never
> replace that with a plain `Start-Process komorebic.exe start --whkd`.

> **⚠ Installer failures.**
> Komorebi and WHKD are primary — a failure aborts the install. YASB and
> AutoHotkey are secondary — a failure is reported with its cause and remedy and
> the install continues. Re-running the installer reinstalls only what failed,
> because every step detects what is already installed and skips it.
> Details: `docs/INSTALL-FAILURE-HANDLING.md`.

> Every script in this directory is SAFE and tested against the current
> configuration (komorebi 0.1.41 / whkd 0.2.10 / yasb). Each `.bat` is a
> user-friendly wrapper for one `.ps1`.

---

## ⭐ Primary script — always use this one

| Script | What it does |
|---|---|
| **`0-SAFE-RESTART.bat`** | **_Restarts + reloads komorebi, whkd and yasb._** The only script you should run to apply a config change. It disables the watchdog for the whole restart window (preventing the double-start race), snapshots tiled windows and then verifies none were left behind after the restart, and reports workspace order per monitor. Engine: `safe-restart.ps1`. |

> ⚠️ **`1-RUN-RESTART.bat` was removed.** That script was the cause of workspaces
> silently going unresponsive: a watchdog race plus a pipe-inheritance hang. Its
> safe replacement is `0-SAFE-RESTART.bat`.

---

## 1. Startup and service

| Script | What it does |
|---|---|
| `2-ADD-TO-STARTUP.bat` | Adds komorebi + whkd to Windows startup (logon scheduled task + watchdog task). Idempotent — re-running is harmless. Engine: `komorebi-service.ps1 -Action install`. |
| `3-REMOVE-FROM-STARTUP.bat` | Removes the scheduled tasks so komorebi no longer starts at boot. Does not stop the running session. Engine: `komorebi-service.ps1 -Action uninstall`. |
| `4-STATUS.bat` | **Read-only.** Health report: processes, socket, monitors, layouts, hotkeys, and anything you should know about. Engine: `komorebi-service.ps1 -Action status`. |

---

## 2. Restarting services

Every restart script here takes `-DiagnoseOnly`: it prints a read-only report of
the whole stack — processes, komorebi/whkd pairing, watchdog task state, and the
whkd layer — then exits without restarting anything. Use it first, because
"a hotkey does nothing" has three indistinguishable causes (a dead process, an
unpaired whkd, or a whkd that loaded zero hotkeys) and the report names which
one you have.

| Script | What it does |
|---|---|
| `A-RESTART-ALL.bat` | Restarts komorebi + whkd + yasb together (a lighter variant of 0-SAFE-RESTART). Engine: `restart-all.ps1`. |
| `B-RESTART-KOMOREBI.bat` | **komorebi only** — for applying a changed `komorebi.json`. Watchdog-safe. Engine: `restart-komorebi.ps1`. |
| `C-RESTART-WHKD.bat` | **whkd only** — for applying a changed `whkdrc`. Watchdog-safe. Engine: `restart-whkd.ps1`. |
| `D-RESTART-YASB.bat` | **yasb only** — for applying a changed `config.yaml`. Rebuilds PATH from the registry (so the event listener can find `komorebic.exe`) and prints the connection verdict from the log. Engine: `restart-yasb.ps1`. |

> **Why a full yasb restart instead of hot-reload?** YASB reads its PATH at
> launch. If that PATH is older than the komorebi install, `komorebic.exe` is
> not found and the komorebi widgets die. On top of that, `watch_config` does
> not see edits made from WSL (drvfs).

> **`7-YASB-RESTART.ps1` was REMOVED — merged into `restart-yasb.ps1`.**
> Its diagnosis half is now the `-DiagnoseOnly` switch on `restart-yasb.ps1`
> (prints the registry-vs-inherited PATH status and how YASB is registered at
> logon, then exits without restarting). Use `D-RESTART-YASB.bat` to restart,
> or `powershell -File restart-yasb.ps1 -DiagnoseOnly` to diagnose only.

---

## 3. Start and stop

| Script | What it does |
|---|---|
| `9-START-ALL.bat` | Starts komorebi + whkd + yasb (only if not already running). komorebi goes first because whkd/yasb talk to its socket. Engine: `start-all.ps1`. |
| `8-KILL-ALL.bat` | Stops komorebi + whkd + yasb completely. Windows stay where they are. The watchdog will not bring them back — run `9-START-ALL.bat` to restore. Engine: `kill-all.ps1`. |

---

## 4. Workspaces and monitors

| Script | What it does |
|---|---|
| `5-RESET-WORKSPACES.bat` | Renumbers workspaces `1..9` on every monitor. komorebi stores workspaces as one vector whose order flips as you move between them, and `retile` does not sort it — a full stop/start is the only way to fix it, and this script does that watchdog-safely. Engine: `reset-workspaces.ps1`. |
| `6-DISPLAY-DIAG.bat` | **Read-only.** Compares monitor geometry across three sources: `EnumDisplaySettings` (native pixels), Windows Forms (DPI-scaled), and komorebi. Use when `4-STATUS` shows a monitor with a negative width. Engine: `display-diag.ps1`. |
| `E-RECOVER-MONITORS.bat` | **Run after plugging/unplugging or powering a monitor on/off.** Restores orphaned windows, re-applies display index preferences, and retiles. Engine: `recover-monitors.ps1`. |

---

## 5. Config backup and restore

| Script | What it does |
|---|---|
| `EXPORT-CONFIG.bat` | Copies the live config (whkdrc, komorebi.json, applications.json, restart-whkd.cmd, toggle-transparency.ps1, komorebi-watchdog.*) into a fresh timestamped folder under `%USERPROFILE%\.config\`, named `komorebi-backup-<yyyyMMdd-HHmmss>`. **Read-only for the system.** Engine: `komorebi-backup.ps1 -Mode export`. |
| `IMPORT-CONFIG.bat` | Restores the config from a backup folder. **It first copies the current config into a `pre-import-<timestamp>` folder, so this is always reversible.** It then stops the WM, replaces the files, and starts again. Engine: `komorebi-backup.ps1 -Mode import`. |

> Backups are **not** written to a fixed location: each export creates its own
> timestamped folder, so successive exports never overwrite each other. The
> default is `%USERPROFILE%\.config\komorebi-backup-<timestamp>`; pass
> `-ZipPath` to `komorebi-backup.ps1` to choose another.

---

## 6. Uninstall and cleanup

| Script | What it does |
|---|---|
| `UNINSTALL-KOMOREBI-WHKD.bat` | **Removes komorebi + whkd (the software).** Removes the scheduled tasks, stops the processes, and uninstalls the packages via MSI uninstall entries (winget hangs on this machine). **The configs are left untouched.** Engine: `uninstall-komorebi-whkd.ps1`. |
| `CLEANUP-KOMOREBI-WHKD.bat` | **Run after UNINSTALL.** Wipes every remaining trace: install directories, config files, state and logs, helper binaries, and PATH entries. It writes a safety copy of the configs next to the script first and demands the word `DELETE`. Engine: `cleanup-komorebi-whkd.ps1`. |
| `AHK-UNINSTALL.bat` | **Removes AutoHotkey v1 and v2 (the software).** Stops the interpreter processes, runs the MSI uninstall, and removes the generated `AppRunner.vbs` from Startup. **The `.ahk` scripts in the repository are left untouched.** Engine: `ahk-uninstall.ps1`. |
| `AHK-CLEANUP.bat` | **Run after UNINSTALL.** Clears user-space leftovers: the generated `AppRunner.vbs`, the enable/disable state file, and any process running one of this repo's scripts. **It does not remove the interpreters.** Engine: `ahk-cleanup.ps1`. |

---

## 6b. AutoHotkey lifecycle (ticket 08)

These four scripts make AutoHotkey a first-class part of the environment:

| Script | What it does |
|---|---|
| `AHK-SCRIPT.bat` | **Enables/disables one script.** With no argument: lists the three scripts with their current state. With an argument: `AHK-SCRIPT.bat NewFile disabled` comments that line out in `AppRunner.vbs`, kills the process immediately, and records the state in `autohotkey\ahk-state.json` so it stays off at the next logon too. Engine: `ahk-script.ps1`. |
| `AHK-TOGGLE-ALL.bat` | **Turns all three scripts on or off at once.** `AHK-TOGGLE-ALL.bat disabled` disables all three. Engine: `ahk-toggle.ps1`. |
| `AHK-CLEANUP.bat` | Leftovers (same row as above). |
| `AHK-UNINSTALL.bat` | Uninstall (same row as above). |

**Important:** these scripts only manage the scripts present in this
repository's `autohotkey\` directory. Any AutoHotkey script the user runs from
some other path is left completely untouched — even if it happens to share a
name.

---

## 7. Helper utilities

| Script | What it does |
|---|---|
| `F-REPAIR-WHKDRC.bat` | Rewrites `whkdrc` in exactly the shape whkd accepts: no BOM, LF line endings, ASCII only, and `.shell` as a bare name. Remaining bindings are preserved and a backup is written next to the file. **For when whkd crashes with `could not load whkdrc`.** Engine: `repair-whkdrc.ps1`. |
| `toggle-transparency.ps1` | Toggles the active window between 85% transparent and fully opaque. **Bound to the `alt+ctrl+t` hotkey in whkdrc** — it is not meant to be run directly. |

---

## 8. Dependencies (do not run directly)

These files are shared helpers or internal engines. The `.bat` wrappers call them:

| File | Role |
|---|---|
| `common.ps1` | Shared helpers: `Resolve-KomorebiExe`, `Resolve-KomorebicExe`, `Resolve-WhkdExe`, `Test-Process`, `Stop-ProcessTree`, and `Show-KomorebiDiagnosis` (the shared `-DiagnoseOnly` report). Dot-sourced by kill-all / start-all / restart-*. |
| `komorebi-service.ps1` | Central engine for install/uninstall/start/restart/status/watchdog. **This is the script the watchdog scheduled task runs** (from the user's Temp path). It is mutex-protected so a restart can never race the watchdog. |

---

## Important notes

1. **Never run `komorebic.exe reload-configuration`.** To apply a config change:
   stop the WM → replace the files → start. `0-SAFE-RESTART.bat` does this
   safely.
2. **whkd 0.2.10 `.shell` accepts only `cmd` / `powershell` / `pwsh`.** Anything
   else → `panic!("unsupported shell")` → every hotkey dies.
3. **`focus-workspace N` in whkdrc is 0-indexed and per-monitor** (0 = workspace
   "1"). `focus-named-workspace` is global and jumps to the primary monitor —
   don't use it.
4. **YASB `label_zero_index: false`** so workspaces are displayed from 1.
5. **Run the `.bat` wrappers by double-clicking from Explorer.** `%~dp0` refers
   to the file's own path, so they work from any copy of the directory.
6. **Live config lives under `%USERPROFILE%`**: `.config\whkdrc`,
   `komorebi.json` and `applications.json` in the user profile. `EXPORT-CONFIG`
   writes a timestamped copy under `%USERPROFILE%\.config`, and `IMPORT-CONFIG`
   reads from the folder you point it at.

---

## Quick map: which script for which situation

| I want to... | Script |
|---|---|
| I changed the config and want it applied | **`0-SAFE-RESTART.bat`** |
| Check whether everything is healthy | `4-STATUS.bat` — or any restart script with `-DiagnoseOnly`, which changes nothing |
| I changed only `config.yaml` (yasb) | `D-RESTART-YASB.bat` |
| I changed only `whkdrc` (hotkeys) | `C-RESTART-WHKD.bat` |
| I changed only `komorebi.json` | `B-RESTART-KOMOREBI.bat` |
| Workspace order has got scrambled | `5-RESET-WORKSPACES.bat` |
| I plugged/unplugged a monitor | `E-RECOVER-MONITORS.bat` |
| Monitor geometry is reported wrong | `6-DISPLAY-DIAG.bat` |
| Stop the services completely | `8-KILL-ALL.bat` |
| Start everything again | `9-START-ALL.bat` |
| Back up the config | `EXPORT-CONFIG.bat` |
| Restore the config | `IMPORT-CONFIG.bat` |
| Remove everything | `UNINSTALL-KOMOREBI-WHKD.bat` then `CLEANUP-KOMOREBI-WHKD.bat` |
| whkd crashed with `could not load whkdrc` | `F-REPAIR-WHKDRC.bat` |