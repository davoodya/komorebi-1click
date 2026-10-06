# ADR 0016: Elevated window management (RunLevel Highest + layered_whitelist)

**Status:** accepted
**Date:** 2026-10-02
**Decision owner:** Davood
**Full analysis:** [`../elevated-windows-fixing.md`](../elevated-windows-fixing.md) (verified live on the reference machine)

## Context

Komorebi could not manage two classes of window. The symptoms looked identical but the root causes
were different:

1. **Applications launched as Administrator** — Windows UIPI blocks window-management operations
   (`SetWindowPos`, `SetForegroundWindow`, `ShowWindow`, border attachment) from a process at a lower
   integrity level against a higher one. Komorebi, launched from a Medium-integrity context, could see
   elevated windows but every tile/focus/hide call was silently denied by the kernel. Nothing in the
   UI hinted at the cause — the window was simply absent from the layout and unreachable by hotkeys.
2. **Git Bash (`git-bash.exe`)** — `git-bash.exe` is only a launcher; the visible window belongs to
   `mintty.exe` (class `mintty`). Rules aimed at `git-bash.exe` matched nothing. Beyond that, mintty
   carries `WS_EX_LAYERED`, and Komorebi's eligibility check
   (`window.rs :: window_is_eligible()`) rejects layered windows unless `allow_layered` is set for
   them. This gate is deliberate: layered windows cause ghost tiles and make tiling redraw "go crazy"
   on focus-change events.

## Decision

Two decisions are now load-bearing requirements of the installer and must survive install, reinstall,
and watchdog restarts:

1. **Both startup scheduled tasks are registered with `-RunLevel Highest`.**
   `Komorebi` and `KomorebiWatchdog` alike. The watchdog must be Highest too: a respawned Komorebi
   silently drops back to Medium integrity otherwise, and elevated windows stop being manageable
   after the *first* watchdog restart — a delayed regression that is very hard to trace.
2. **The generated `komorebi.json` contains `layered_applications` with the `mintty` class rule.**
   The key is `layered_applications` — **not** `layered_whitelist`. The latter is the name of
   the same list in `komorebic global-state` **output**; as an input key it is silently
   ignored by serde (no `deny_unknown_fields`, no error, `komorebic check` still exits 0).
   `layered_applications`, not `manage_rules`: `manage_rules` sets `managed_override`, which
   bypasses all eligibility checks and changes layout behaviour. `layered_applications` flips
   exactly the one gate that was blocking, and leaves the LAYERED filter intact for every other
   application.

   The list also carries `Class = ConsoleWindowClass` so classic Windows consoles
   (`cmd.exe` / `pwsh.exe` / `powershell.exe` / `conhost.exe`, elevated **and** non-elevated)
   are managed. Those windows carry `WS_EX_LAYERED`, which the same gate rejects — see
   ADR addendum below.

```json
"layered_applications": [
    { "kind": "Class", "id": "mintty", "matching_strategy": "Equals" },
    { "kind": "Class", "id": "ConsoleWindowClass", "matching_strategy": "Equals" }
]
```

## Addendum (2026-10-06): elevated consoles were still unmanaged

**Symptom.** `cmd.exe` / `pwsh.exe` / `powershell.exe` launched **as Administrator** were not
detected or tileable, while an elevated **GUI** app (e.g. Notepad) *was* managed. That
asymmetry is the diagnostic: elevation was fine, so the blocker had to be a per-window-style
gate.

**Root cause.** Classic Windows console windows have class `ConsoleWindowClass` and carry
`WS_EX_LAYERED` (`exstyle 0x000C0110`) — **regardless of elevation**, Medium and High alike.
`window_is_eligible()` rejects layered windows unless `allow_layered` is set, which only
`layered_applications` does. Decision 2 above had been implemented with the key spelled
`layered_whitelist`, so the list was never populated and every console stayed unmanaged.

**Why it looked like it had worked.** The rule had been added at runtime with
`komorebic identify-layered-application class ConsoleWindowClass`, which populates the
**in-memory** list. That survived until the first restart; afterwards the config was re-read
from disk, the misspelled key was ignored, and the rule vanished with no log entry.

**Consequence.** The key name is now a correctness requirement, not cosmetics, and the
verification suite asserts both the presence of `layered_applications` and the **absence**
of `layered_whitelist` (see `tests/verify-readonly.ps1` R04, `tests/sandbox-test-suite.ps1`
T03.2, `tests/sandbox-verify-install.ps1`).

**Verification.** Live on the reference machine: 3/3 `ConsoleWindowClass` windows managed
(one Medium `conhost.exe`, two High — `pwsh.exe` and `cmd.exe`), and the result persisted
across a full `safe-restart.ps1` cycle.

**Applying a `komorebi.json` change — which command actually re-reads the file.**
Tested live with a throwaway rule (`ZzWatcherProbeClass`) written into the file and then
checked in `komorebic global-state`:

| Method | Re-reads `komorebi.json`? |
|---|---|
| `komorebic reload-configuration` | **No** — it only loads legacy `komorebi.ps1` / `komorebi.ahk` (`WindowManager::reload_configuration` → `load_configuration`). On a modern JSON-only setup it is a **no-op**. |
| `komorebic replace-configuration <path>` | Yes — validated via `StaticConfig::read` before applying |
| Editing the file on disk | Yes, automatically — a file watcher (`wm.hotwatch`, registered in `StaticConfig::preload`) sends `ReloadStaticConfiguration` on `Modify`/`Remove` |
| Full restart | Yes (most deterministic) |

The watcher's existence is why a JSON edit usually appears to "just work" after a few
seconds, and why `reload-configuration` is so often — wrongly — credited for it.

## Consequences

- **Positive:** elevated `cmd`/`pwsh`/`powershell`, and Git Bash both elevated and non-elevated, are
  fully managed — not merely listed: `komorebic move-to-workspace` actually moves them.
- **Positive:** Komorebi listens on a Unix Domain Socket (`komorebi.sock` via `uds_windows`), which on
  Windows is not access-controlled the way named pipes are, and the socket is removed and re-created on
  startup. Non-elevated clients (`komorebic` CLI, the watchdog, YASB, custom scripts) keep working
  against an elevated listener — verified live.
- **Positive:** the `mintty` class is identical for Git Bash, Cygwin and MSYS2 consoles and survives
  Git for Windows upgrades; only a switch to a different terminal would need a new entry.
- **Negative:** on a normal machine the install triggers exactly one UAC dialog (once, at install time;
  UAC is disabled on the reference machine so the prompt does not appear there). The installer must
  state that elevation is required and why.
- **Negative:** other layered applications (some terminal and Electron builds) still need their own
  `layered_whitelist` entry. There is no global opt-out, and adding one would re-enable the ghost-tile
  behaviour the filter exists to prevent.
- **Out of scope:** WSLg / `PseudoConsoleWindow` windows remain unmanaged. That needs its own analysis
  and is a separate change.

## Why not the alternatives

- **Run Komorebi as a service.** Not the supported path; the scheduled-task-with-elevation shape is
  what the vendor's own autostart uses.
- **Match `mintty.exe` instead of class `mintty`.** Narrower with no benefit.
- **Disable the LAYERED check globally.** Would re-enable the ghost tiles the filter exists to prevent.

## Requirements this creates

The installer's startup registration and config generation are now correctness requirements, not
preferences: a default `komorebic start` will **not** reproduce the working state. See tickets
03 and 04, and `docs/elevated-windows-fixing.md` §6.
