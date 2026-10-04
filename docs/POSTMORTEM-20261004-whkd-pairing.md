# Postmortem: Hotkeys die while YASB keeps showing workspaces

Date: 2026-10-04
Severity: total hotkey loss (Komorebi still tiling, YASB bar still live)
Affects: any machine where `safe-restart.ps1` / `0-SAFE-RESTART.bat` falls back to
starting whkd on its own — including a clean Komorebi-1click install.

---

## Symptom

Every Komorebi hotkey stopped responding. The YASB bar kept showing all
workspaces and the current layout correctly. `restart-whkd.ps1` and
`0-SAFE-RESTART.bat` were run by hand and neither one brought the hotkeys back.
`safe-restart.ps1` *did* restart Komorebi and whkd, but the elevated/elevated-pwsh
and Hermes-app windows that Komorebi manages via special rules were then not
managed at all.

The failure is silent: both processes are alive, whkd reports
`Profile loaded in 0 ms`, the whkdrc parses with zero errors, and the socket is
up. Nothing in the log says hotkeys are dead.

## Root cause

`whkd` was started **standalone**, not as a child of `komorebic start --whkd`.

Komorebi and whkd are paired by ownership, not by configuration. When
`komorebic start --whkd` spawns whkd, the two share an IPC relationship and
whkd's `komorebic` invocations are dispatched by that komorebi instance. When
whkd is started by anything else — a manual `Start-Process`, a scheduled task,
or the fallback branch of a restart script — whkd registers its hotkeys with
Windows perfectly, parses the whkdrc perfectly, and then every hotkey it fires
goes nowhere, because no komorebi instance considers that whkd its own.

Evidence captured on the affected machine:

| Check | Value found |
|---|---|
| `komorebi.exe` parent | an already-exited launcher (correct — official start path) |
| `whkd.exe` parent | a **live, unrelated `pwsh.exe`** (wrong — standalone start) |
| `whkd-start.err` / `whkd-start.out` | created 2s **after** komorebi started, i.e. the fallback branch ran, not `--whkd` |
| `komorebi.state` whkd linkage | empty |
| whkd parsing its config | `Profile loaded in 0 ms` — the config was never the problem |

The chain that produced it: `Start-Komorebi` ran `komorebic start --whkd`,
slept 2 seconds, did not see a whkd process yet, and fell into its fallback
branch, which did `Start-Process whkd.exe` directly. The fallback then logged
`whkd started via absolute path` and returned **success**. Hotkeys were dead,
and the health check said healthy. The elevated windows falling out of
management was the downstream consequence: the special-handling rules are
applied per komorebi state, and the mismatched pairing meant several
applications were left untouched.

The `Get-Health` early-return made this worse: it reported `Process = $false`
for a komorebi that was running, so `Show-Status` was already untrustworthy
before this incident.

## Fix applied to the running machine

1. Back up the live config first —
   `~/.config/komorebi-pre-hotkey-fix-<timestamp>/` (whkdrc, komorebi.json, yasb tree).
2. Stop the pair with the official command, not `Stop-Process`:
   `komorebic stop --whkd` — this kills both komorebi **and** the whkd it owns,
   which is precisely why the hand-run `restart-whkd.ps1` could not fix it: it
   only restarted the orphan whkd, leaving the pairing broken.
3. Remove the stale socket/state handle so the new instance gets a clean IPC
   surface (Windows refuses an unattended UAC prompt, so no elevation prompt
   was triggered).
4. Start the pair with `komorebic start --whkd` so komorebi owns the whkd child.

Verified after the restart:

- `whkd.exe` parent PID points at an **already-exited** launcher — the
  signature of the official `--whkd` start path, not a live shell.
- `komorebic focus-workspace` round-trip succeeds with no error.
- Health check now reports `whkd PAIRING : OK (spawned by komorebi --whkd)`.
- YASB and AutoHotkey were never touched; no other component was restarted.

The hotkeys and the special-window management rules both came back with this
single pairing repair.

## Why the pairing breaks in the first place (and the elevated-window half)

The same restart hides a second failure. komorebi can only manage windows it
can open, and a window manager running at a lower integrity level than a
process cannot touch that process's windows. So an **unelevated** komorebi
silently drops every elevated window — and the Hermes window — out of the
layout, exactly as if they had never been opened.

The reference machine is not an Administrator account, so
`Start-Process -Verb RunAs` cannot obtain an elevated token without a consent
prompt an automated run cannot answer (`ConsentPromptBehaviorAdmin=0` with a
non-admin user does not auto-elevate). The reliable way to an elevated
komorebi is the `Komorebi` logon task the installer registers at
`RunLevel Highest`: `Start-ScheduledTask -TaskName 'Komorebi'` launches
`komorebic.exe start --whkd` with the elevated token.

Verified on the reference machine after the fix:
`komorebi pid=21108 elevated=True`, `whkd pid=48580 elevated=True`, and 12-14
windows tiled including elevated applications.

`restart-whkd.ps1` and `safe-restart.ps1` now both take this path when they
are not already elevated, and `komorebi-service.ps1` gained a `-Action stop`
so `safe-restart.ps1` can stop the pair and hand the start to the elevated
task. `tests/sandbox-test-suite.ps1` section `T04.1c` asserts komorebi is
elevated after a real install.

### A probe bug worth remembering

The first elevation checks reported `elevated=False` for every process and
sent the investigation down a dead end. They called `OpenProcess` with
`PROCESS_QUERY_INFORMATION | PROCESS_VM_READ` (0x0410), which UIPI denies for
processes outside the caller's integrity context, so `OpenProcess` returned
zero and the probe fell through to its default. The correct mask is
`PROCESS_QUERY_LIMITED_INFORMATION` (0x1000). The fixed probe is embedded in
the health check so this mistake cannot recur silently.

## Prevention — applied to the codebase

### 1. The fallback can no longer silently succeed

`scripts/komorebi-service.ps1` → `Start-Komorebi`.

The fallback branch that spawns `whkd.exe` directly now returns **failure** and
logs `whkd started standalone (NOT paired with komorebi)`. A standalone whkd
looks alive but is functionally dead, so reporting success for it was the bug.
The console message tells the operator the exact recovery command pair.

### 2. New pairing probe in `Get-Health`

`WhkdPaired` distinguishes the two start paths by process tree shape:

- `--whkd` launches whkd through a short-lived helper that exits immediately,
  so whkd's parent PID points at a **gone** process → paired.
- A standalone whkd has a **live** shell (pwsh/powershell/cmd/wt/conhost) as an
  ancestor → not paired.

`Show-Status` prints the probe on its own line, and when it is broken it prints
the two-command recovery inline so the operator never has to go hunting.

### 3. Fixed the `Get-Health` early return

It returned before `$h.Process` was ever populated, so `Show-Status` reported
BROKEN for a healthy system. Now `Process`, `Whkd`, `Socket`, `Monitors`,
`TiledWindows` and `HotkeyBindings` are all set before any verdict is drawn.

### 4. Regression test

`tests/sandbox-test-suite.ps1` → section `T04.1b`:
`Assert 'whkd is paired with komorebi (not a standalone instance)' $health.WhkdPaired`
after a real install, so a fallback that ever returns success again fails the
suite instead of a user's keyboard.

## Why `restart-whkd.ps1` and `0-SAFE-RESTART.bat` could not fix it

Both restart **whkd**. Neither can repair the pairing, because the pairing is
established by **how komorebi starts**, not by what whkd does afterwards.
Restarting whkd alone just replaced one standalone whkd with another. The only
repair is to stop the pair and start it through `komorebic start --whkd`.
`restart-whkd.ps1` is now fixed by the same change: it re-checks the pairing
after restarting and reports the failure honestly instead of claiming success.

## Recovery recipe (keep this, it is the whole fix)

```powershell
# one-time backup
Copy-Item "$env:USERPROFILE\.config\whkdrc" "$env:USERPROFILE\.config\whkdrc.bak"

# official stop removes BOTH the wm and the whkd it owns
komorebic stop --whkd

# remove stale IPC state so the new instance starts clean
Remove-Item "$env:LOCALAPPDATA\komorebi\komorebi.hwnd.json" -ErrorAction SilentlyContinue

# start through the official path so komorebi owns the whkd child
komorebic start --whkd
```

Then verify with `Get-KomorebiStatus` — the health output must say
`whkd PAIRING : OK`.

## Notes

- Windows refused the unattended elevation prompt during `komorebic stop`, so
  the stop/start pair was run without elevation; UAC is disabled on this host.
- The monitor-geometry warnings `Get-Health` reports (`DISPLAY2`/`DISPLAY3`
  mismatch) are a pre-existing, separate issue and were intentionally left
  alone, per the instruction not to change anything outside this fault.
