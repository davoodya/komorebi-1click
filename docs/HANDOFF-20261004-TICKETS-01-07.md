# Handoff — Tickets 01 → 07 (komorebi-1click)

**Date:** 2026-10-04
**Supersedes:** `HANDOFF-20261003-TICKETS-01-04.md` (that document is still accurate for
tickets 01–04; this one adds 05, 06, 07 and the follow-up fixes, and records the decisions
that changed after it was written).

---

## 1. What the project is

A one-click, offline installer for the whole **Komorebi + WHKD + YASB + AutoHotkey**
stack. It installs the four components from binaries committed to the repo, generates a
portable configuration for the target machine, sets up the startup machinery, and ships
the battle-tested management scripts — driven by a future Dashboard and CLI.

## 2. The two directories (important)

| | Path | Contents |
|---|---|---|
| **Dev (not on GitHub)** | `~/projects/komorebi-1click` | spec, ADRs, tickets, research, cheatsheets, tests, docs |
| **Publish (GitHub)** | `/mnt/h/Repo/komorebi-1click` (= `H:\Repo\komorebi-1click`, `github.com/davoodya/komorebi-1click`) | everything the installer ships: binaries, `Install.ps1`, `scripts/`, `config/`, `autohotkey/`, `tests/` |

The dev tree is the source of truth for *thinking*; the publish tree is the source of
truth for *what runs*. Test files are written in dev and copied across.

**SSH push is configured.** `origin` was switched from HTTPS to
`git@github.com:davoodya/komorebi-1click.git` and pushes over the Kali WSL key.

## 3. Ticket status

| # | Ticket | Status |
|---|---|---|
| 01 | repo + binaries + provenance | ✅ done (commit 942ff3e) |
| 02 | installer core | ✅ done (commit 942ff3e) |
| 03 | configuration generation | ✅ done (commit adb050b) |
| 04 | startup tasks | ✅ done (commit 887db72) |
| 05 | AutoHotkey integration (AppRunner.vbs) | ✅ done (commit 92e1e90) |
| 06 | management-script portability | ✅ done (commit 0064b36) |
| 07 | export / import ZIP | ✅ done (commit c0ca4d0) |
| 08 | AutoHotkey lifecycle scripts | ✅ done (commit `PEND`) |
| 09 | EXE wrapper (csc) | ready |
| 10–13 | Dashboard (shell, threading, theme, publish) | blocked by 10's own chain |
| 14 | verification harness (Windows Sandbox) | blocked by 09 + 13 |

Tickets 05, 06, 07 have all acceptance boxes ticked in their issue files.

## 4. What tickets 05, 06 and 07 delivered

### Ticket 05 — AutoHotkey integration
- `autohotkey/AppRunner.vbs` ships as a **template** (helpers + an `' AppRunnerEnd`
  marker). It is never copied to the Startup folder — the installer **regenerates** it,
  emitting one `RunHidden` line per shipped script, each pointing at the vendor-default
  interpreter and the repo-relative script path.
- `scripts/Install-Common.ps1` gained `Get-AhkInterpreterPath`,
  `Test-AhkInterpreterAvailable`, `Get-GeneratedAppRunnerContent`, `New-AppRunnerVbs`,
  `Test-AppRunnerUpToDate`, `Install-AutoHotkeyStartup`.
- Not compiled to EXE (ADR-0010: the bundled Ahk2Exe is the v1.1.37 compiler and cannot
  compile the v2 script).

### Ticket 06 — management-script portability
- Every machine-specific path was removed: `F:\Backups\...` is gone, and the scripts
  resolve binaries through `common.ps1` or `$PSScriptRoot`.
- New switches so the Dashboard can drive them per component:
  `kill-all.ps1`/`start-all.ps1 -Components {all|komorebi-whkd|yasb}`,
  `uninstall`/`cleanup -Scope {all|komorebi-whkd|yasb|autohotkey}`,
  `toggle-transparency.ps1 -Percent` (default 85 → alpha 38, identical to the original),
  `komorebi-backup.ps1 -ZipPath`.
- The watchdog mutex and the YASB registry PATH rebuild were left untouched (both are
  load-bearing; both are asserted in the test suite).

### Ticket 07 — export / import
- **New `scripts/config-export-import.ps1`.** One ZIP for the whole config set.
  Native Windows Save/Open dialogs (filter `*.zip`, suggested name
  `komorebi-1click-config-YYYY-MM-DD.zip`), and a `-ZipPath` CLI form that reaches the
  same code. `System.IO.Compression.ZipFile` only — no third-party dependency.
  `komorebi-resize.json` is included only when non-empty, so a fresh target never
  imports another machine's resize offsets. Import always backs the live config up to a
  timestamped `pre-import-backup-*` directory, stops the WM, restores, and starts it
  again.

### Ticket 08 — AutoHotkey lifecycle (this session)

AutoHotkey became a first-class part of the environment. Four new scripts plus
four `.bat` wrappers, all path-portable and all composing with `common.ps1`:

| Script | Does |
|---|---|
| `ahk-script.ps1` | Enable or disable ONE script by name; `-List` shows the state |
| `ahk-toggle.ps1` | Flip all three to the same state at once |
| `ahk-uninstall.ps1` | Remove both AutoHotkey versions by product code |
| `ahk-cleanup.ps1` | Remove the Startup VBS, the state file, and any repo-script process |

The enable/disable mechanism:

- State lives in `autohotkey\ahk-state.json`, not in the VBS. The VBS is a
  derived artifact, regenerated from the state every time.
- A disabled script renders as a **commented-out** `RunHidden` line with a
  `[disabled:<name>]` marker, so its position in the file is stable across
  enable/disable cycles.
- After the VBS is regenerated, the affected process is killed (disable) or
  started (enable) immediately — no logoff required.
- `Install-AutoHotkeyStartup` calls `Apply-AhkEnabledState` before rendering,
  so a re-install preserves what the user toggled off.

**Containment is critical here.** The scripts match processes on the `.ahk`
path **under this repo's `autohotkey\` directory**, never on the process name
or the file name alone. Every v1 script appears in the process list as
`AutoHotkey`, and the user runs personal scripts from `H:\Repo\Auto-HotKey\`
that must never be touched — a name-only match would kill those too. Only the
repo-relative path is unique.

`tests/ticket08-ahk.tests.ps1`: 17 assertions, all green, run against a
sandbox copy so the real Startup folder and the real processes stay untouched.
Verified the test run leaves the live machine unchanged: 3 AHK processes
before and after, Startup VBS intact.

### The ticket-03 follow-up (Davood's spec, this session)
Three whkdrc hotkeys pointed at files the installer never shipped. Fixed properly:

| Hotkey | Before | After |
|---|---|---|
| `alt + o` | bound to `restart-whkd.cmd` | **unbound** |
| `alt + shift + o` | — | `restart-whkd.cmd` (the installer-generated wrapper) |
| `alt + ctrl + t` | komorebi's built-in toggle-transparency | the shipped `toggle-transparency.ps1` |
| `alt + ctrl + shift + r` | — | the shipped `safe-restart.ps1` |

> **⚠ Hotkey postmortem (2026-10-04) — read before touching whkd.**
> whkd must ALWAYS be spawned by `komorebic start --whkd`. A whkd started any
> other way (manual `Start-Process`, a scheduled task, or the
> `Start-Komorebi` fallback branch) is alive, parses its config, and then
> silently drops every hotkey it fires — full hotkey loss while YASB keeps
> working (LGUG2Z/komorebi#956). If hotkeys ever die: `komorebic stop --whkd`,
> clear the stale socket/hwnd state, `komorebic start --whkd`. Restarting whkd
> alone can NEVER repair it; the pairing is set at komorebi start, not by whkd.
> Fixed at three levels: the fallback branch now returns failure, `Get-Health`
> exposes a `WhkdPaired` probe, and `tests/sandbox-test-suite.ps1` section
> `T04.1b` asserts the probe after a real install. Full write-up:
> `docs/POSTMORTEM-20261004-whkd-pairing.md`.
>
> **The elevated-window half of the same bug.** An unelevated komorebi cannot
> manage elevated windows (UAC integrity levels), so a restart done from a
> non-elevated shell silently drops every elevated window and the Hermes window
> out of the layout. The reference account is not an Administrator, so
> `-Verb RunAs` cannot elevate silently. Both `restart-whkd.ps1` and
> `safe-restart.ps1` now stop the pair and hand the start to the installer's
> `Komorebi` logon task, which is `RunLevel Highest`. `komorebi-service.ps1`
> gained `-Action stop` for this. Section `T04.1c` asserts komorebi comes back
> elevated. Verified: `komorebi pid=21108 elevated=True`, 12 windows tiled
> including elevated apps.

`Install-Configuration` now installs `toggle-transparency.ps1` and `safe-restart.ps1`
into `%USERPROFILE%\.config` with SHA256 idempotency, and writes
`safe-restart.repo.txt` next to them so `safe-restart.ps1` can resolve
`komorebi-service.ps1` in the repo instead of needing a second copy.

## 5. Directory consolidation

`final-scripts/` **no longer exists.** It was merged into `scripts/`, which is now the
single canonical directory for every management script. Git recorded the move as 36
renames. `komorebi-service.ps1` kept the ticket-06 version (the only file that existed
in both places; the 06 version has no `F:\Backups` fallback).

`cheatsheets/` is still git-ignored — it still carries `F:\Backups` machine paths and
is not publishable until a doc-portability pass removes them.

## 6. Real bugs found and fixed while testing (not cosmetic)

1. **`New-Whkdrc` rewrote nothing.** The regex pattern was double-escaped
   (`'C:\\\\Users\\\\DavoodYa'`) while the whkdrc file contains single backslashes, so
   the match silently failed and a target machine kept the *source* user's path in its
   hotkeys. Now `[regex]::Escape()`d and proven by a test that renders the whkdrc with a
   fake profile and asserts the source user is gone.
2. **PowerShell 5.1 ternary.** `Assert-ArchitectureSupported` used the PS7-only
   `? :` operator. The installer targets the inbox shell, so it is now `if/else`.
3. **`CreateEntryFromFile` is an extension method.** Calling it on the `ZipArchive`
   object throws `MethodNotFound`. It goes through `[ZipFileExtensions]::…`.
4. **`komorebi.json` restored to the wrong directory.** The import loop wrote
   everything under `.config`, but `komorebi.json` lives directly in `%USERPROFILE%`,
   so the WM kept the stale file after an "import". Top-level names are now mapped back
   to their real home.
5. **`safe-restart.ps1` could not find `komorebi-service.ps1`.** It dot-sourced by
   `$PSScriptRoot`, which breaks once the installer copies it into `.config`. It now
   reads the repo path from the installer-written `safe-restart.repo.txt` and falls back
   to the clone layout.

## 7. How everything is verified

Two independent layers; nothing is verified by eye.

**Layer 1 — static, on the dev machine (no Sandbox):**
`tests/ticket05-06-07.tests.ps1`, **61 assertions, exit 0**. Covers the shipped files,
the *generated* VBS content, the whkdrc bindings, the parameter declarations + usage +
`[ValidateSet]`s, the portability scan, and a live run of `New-Whkdrc`.

**Layer 2 — the Sandbox suite (real install on a clean machine):**
`tests/sandbox-test-suite.ps1` gained `T03f.1–T03f.2` (the repaired bindings are in the
generated whkdrc and the three hotkey targets exist in `.config`, including the repo
marker) and `T07.1–T07.3` (a real export→import round trip: snapshot by SHA256, export,
import back, assert byte-identical, and that a `pre-import-backup-*` directory holding
the old whkdrc was left behind).

The export→import round trip was also executed directly against a sandboxed fake
`%USERPROFILE%` under `%TEMP%` — the reference machine was never touched. Bugs #3 and #4
above were caught by exactly that run.

**Not yet done:** a full `Install.ps1` run inside `sandbox.wsb`. That is the single
outstanding verification step for tickets 02–07 and needs no decisions, only launching
the Sandbox.

## 8. Constraints honoured

- Nothing in this session touched the reference machine's live config. All runtime tests
  used a fake `%USERPROFILE%` under `%TEMP%`.
- The new bindings are in the **shipped templates** only — they apply to a target
  machine at install time, not to the machine the config was cloned from.
- The whkdrc source path rewrite is still the one place `DavoodYa` legitimately appears
  (it is the rewriter's pattern); the test suite asserts the *behaviour* instead of
  banning the string.

## 9. Where to start next

1. **Ticket 08** (AHK lifecycle scripts) — the AppRunner enable/disable mechanism is
   already anticipated by `$script:AutoHotkeyScripts` having an `Enabled` slot.
2. **Ticket 09** (EXE wrapper) unblocks 14.
3. **A Sandbox run** of the full suite would clear the "awaits a Sandbox run" column for
   tickets 02–07 in one shot.
