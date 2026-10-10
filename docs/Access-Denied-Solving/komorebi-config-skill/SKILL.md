---
name: komorebi-config
description: Use when configuring or debugging Komorebi WM rules.
category: devops
---

# komorebi-config

Configuring, debugging, or fixing the Komorebi tiling window manager on the
Windows host from WSL. Every fact below was verified against the installed
source, not inferred from docs — the JSON schema describes valid input, not
runtime behaviour.

## Procedure

1. Get the installed version (`komorebic --version`) and read the source at that
   exact tag (`.../LGUG2Z/komorebi/v<TAG>/komorebi/src/...`). Docs and schema
   alone do not predict behaviour.
2. From source, determine whether the knob you need is read at startup or has a
   runtime command. This decides every step after it.
3. Prefer the runtime command — it is reversible (cleared on restart) and needs
   no restart. Confirm it landed with `komorebic global-state` (read-only).
4. If the knob is startup-only, applying it requires a komorebi restart, which
   re-tiles every window. Confirm with the user before restarting.
5. Test a fresh window of the target app: enumerate top-level windows (class +
   title + exe) and check `komorebic state` for whether it entered the layout.
   `scripts/window-probe.ps1` does this in one shot — it prints class, exe,
   integrity level, `WS_EX_LAYERED`, decoded style bits and managed-state for
   every visible window, which attributes a "not managed" report to the right
   gate instead of guessing. Read it when a window is reported unmanaged.
6. Never reposition windows programmatically to "fix" their placement.
7. When the symptom is "hotkeys dead" or "elevated windows unmanageable", run
   `scripts/komorebi-stack-probe.ps1` first — it is read-only and prints the integrity level of
   each process, whether whkd was spawned by komorebi or standalone, the watchdog state, and
   the live layout in one pass. It attributes the failure to the right layer before you change
   anything.

## "Won't start at all" on Windows 11 25H2/26H2

If komorebi exits with `failed call to AllowSetForegroundWindow after 5 retries`
(`main.rs:219`) or `Access is denied. (0x80070005)` at `windows_api.rs:242:37`,
that is a stack of Windows regressions, not a config problem. `sfc /scannow`, a
plain reinstall and DCOM permission tweaks do not help.

There are **four sequential gates** in `main()`; each one hides the next, so
fixing the first just exposes the second. The order is: `AllowSetForegroundWindow`
-> `SetProcessDpiAwarenessContext` -> `SPI_SETFOREGROUNDLOCKTIMEOUT` -> the
`app_specific_configuration_path` file. Gate 2 is machine-local (an external
`komorebi.exe.manifest` that upstream does not ship); gates 1 and 3 need a
6-byte binary patch; gate 4 needs `applications.json` restored.

**Do not spend time on runtime workarounds** — ShellExecute, cscript, `cmd start`,
a WinForms foreground wrapper, `MinimizeAll`, `AttachThreadInput` and every
`SPI_SETFOREGROUNDLOCKTIMEOUT` parameter form were all tested and all fail on
build 26300. Full diagnosis, the patch offsets and the verification block are in
`references/win11-26h2-asfw-startup-block.md`.

## Rule evaluation model

- Manage/ignore is decided ONCE, at window creation (`window_is_eligible` in
  `window.rs`). Later title changes fire `TitleUpdate`, which only refreshes the
  bar — eligibility is never re-evaluated.
- Only `Exe`, `Class`, and `Path` are reliably available at decision time. A
  `Title` rule cannot match a window whose title is set after creation.
- Precedence: a window is skipped only if an ignore rule matches AND no manage
  rule matches. Any matching manage rule overrides ignore.
- Composite (AND-array) rules do work under an app's `manage`, under `ignore`,
  and in the top-level rule arrays.

## Reload semantics

Three distinct mechanisms — conflating them causes silent no-ops:

- `komorebic reload-configuration` runs `komorebi.ps1` / `komorebi.ahk` from HOME
  (`WindowManager::reload_configuration` → `load_configuration` in `lib.rs`).
  **On a modern JSON-only setup this is a no-op.**
- `komorebi.json` IS re-read by a **file watcher**: `StaticConfig::preload` registers
  `wm.hotwatch.watch(path, …)` which sends `ReloadStaticConfiguration` on
  `Modify`/`Remove`. So editing the file on disk applies within seconds without any
  command — and this watcher, not `reload-configuration`, is why a JSON edit appears
  to "just work".
- `komorebic replace-configuration <path>` re-reads and applies immediately, after
  validating with `StaticConfig::read` (a malformed file is refused, not applied).

Verified live by writing a throwaway rule into the file and checking `global-state`
after each method. Rules added by a runtime command (`identify-layered-application`,
`manage-rule`, …) live in memory only; a restart clears them.

## Input key names ≠ output key names (silent-drop trap)

The keys you WRITE in `komorebi.json` differ from the keys `komorebic global-state`
PRINTS. `StaticConfig` has no `deny_unknown_fields`, so a wrong key is dropped by
serde **silently** — no error, no warning, `komorebic check` still exits 0, and the
rule never applies.

| `komorebi.json` (input) | `global-state` (output) |
|---|---|
| `ignore_rules` | `ignore_identifiers` |
| `manage_rules` | `manage_identifiers` |
| `tray_and_multi_window_applications` | `tray_and_multi_window_identifiers` |
| `layered_applications` | `layered_whitelist` |

Always confirm a rule landed by reading `global-state` — never by assuming the file
edit took effect. Use the schema (`schema.json` at the installed tag) for the true
input names; `global-state` is the OUTPUT shape.

## Elevated windows and `WS_EX_LAYERED`

- Elevated (`Administrator`) windows need komorebi itself at High integrity — both the
  logon task and the watchdog task must be `RunLevel=Highest`, or a respawned komorebi
  silently drops to Medium and elevated windows become unmanageable after the first
  watchdog cycle.
- Classic consoles (`cmd`/`pwsh`/`powershell`/`conhost`) have class
  `ConsoleWindowClass` and carry `WS_EX_LAYERED` (`exstyle 0x000C0110`) **regardless of
  elevation**. `window_is_eligible()` rejects layered windows unless `allow_layered`,
  which only `layered_applications` sets. Add `Class = ConsoleWindowClass` there.
- Diagnostic asymmetry: if an elevated GUI app (Notepad) tiles but an elevated console
  does not, elevation is fine and the blocker is the LAYERED gate.
- **Prefer the narrowest gate that unblocks.** `layered_applications` flips exactly the
  one eligibility check that was blocking. `manage_rules` sets `managed_override`, which
  bypasses **all** eligibility checks and changes that app's layout behaviour. Reaching
  for the broad hammer to solve a narrow problem makes the window managed but alters how
  it tiles.

## Verifying a fix: a runtime rule hides a wrong config key

A rule applied at runtime (`komorebic identify-layered-application`, `manage-rule`, …)
lives in **memory** and takes effect immediately. That makes it the right instrument for
isolating a mechanism and the wrong thing to leave in place as the fix.

- **Isolate first, with the runtime command.** Apply the candidate rule at runtime and
  open a *fresh* window. Managed now ⇒ the mechanism is right and only the config
  spelling needs fixing. Still not managed ⇒ the mechanism is wrong; do not edit the
  config file yet. This separates "wrong key" from "wrong rule" in a single step.
- **Then make it permanent, and prove the permanence.** Write the config, apply it,
  **restart the service**, and re-verify on a fresh window. A fix that survives only
  until the next restart is not a fix — it is precisely the shape that makes a bug look
  intermittent, because the runtime-applied rule masks the wrong config key until the
  restart re-reads the file and silently drops it.

Corollary: `komorebic check` exiting 0 proves the JSON parses, not that any key inside
it is recognised. Only `global-state` (after a restart) shows what was actually loaded.

## Config drift between the live machine and the repo template

The project rule: whatever the installer ships to a target machine must equal the
live machine's config. Two independent drifts have already happened.

- **The source of truth is the last commit, not a backup.** A backup can predate
a later fix. Restoring from an older backup silently reverts committed fixes —
this happened: an incident restored a `00:42` snapshot that was older than
commit `8618dd7`, dropping the `Title` ignore rules for Network Connections /
Computer Management / Disk Management / Event Viewer (which made those legacy
shell applets overflow the monitor). Compare against `git show HEAD:<file>`.
- **Three keys are machine-specific and MUST stay `null` in the template**:
`monitors`, `display_index_preferences`, `app_specific_configuration_path`. The
installer generates them from target hardware. Exclude them when diffing or
every comparison reports a false difference.
- **`whkdrc` differs on purpose.** The template carries explanatory comments and
the machine carries personal bindings (`wsl.exe`, `notepad++.exe`). Never
overwrite the live `whkdrc` with the template — port only genuine improvements
(e.g. `powershell` -> `powershell.exe`) by hand, key by key not line by line.
- **Undocumented uncommitted changes in the template are drift, not intent.**
Seen once: `unmanaged_window_operation_behaviour` flipped `Op` -> `NoOp`, and
five shells added to `manage_rules`. Both contradicted ADR-0016 (which mandates
`layered_applications`, since `manage_rules` sets `managed_override` and bypasses
all eligibility checks). Revert to the committed value.

## The integrity chain: why a window can be detected yet not managed

"Detected but not manageable" — the window gets a border and lands in the layout, but
`alt+shift+N` does nothing — is a **two-layer** failure with one root cause. Both layers are
the same fact: **integrity level is inherited at spawn.**

```
whkd.exe  --spawns-->  powershell.exe  --writeln-->  komorebic.exe  -->  komorebi's named pipe
    ^                        ^                                                    ^
  must be High        inherits whkd's IL                          server runs at High
```

- Layer 1 — **the hotkey dispatch shell**. whkd spawns one long-lived shell at startup and
  writes each fired binding into its stdin. That shell inherits whkd's integrity. If whkd is
  Medium the shell is Medium, and `komorebic.exe` **cannot open komorebi's named pipe** (a
  High-IL server) — the command is refused silently, with no error anywhere.
- Layer 2 — **komorebi itself**. Started from an ordinary shell it is Medium and cannot manage
  elevated windows at all.

The two layers are independent, which is why the symptom is split: komorebi (High) draws the
border itself, so the window *looks* managed, while the move goes through
whkd -> shell -> komorebic -> pipe and dies at the integrity boundary.

Measured on the live machine:

| Start path | komorebi IL | whkd IL | hotkey |
|---|---|---|---|
| `Start-ScheduledTask -TaskName Komorebi` (= `komorebic start --whkd`, RunLevel=Highest) | High | **High** | works |
| `Start-Process whkd.exe` from an ordinary shell | High | **Medium** | silently dead |

**A standalone whkd is not cosmetic, and the process-tree probe is not a false positive.** An
earlier note claimed the pairing heuristic false-positives on a manually started but working
whkd. That holds only if the manual start happened in an *elevated* context. A whkd started
from an ordinary shell is genuinely inert against any target at a higher integrity level —
which is exactly what the probe detects. Trust the probe and confirm it by measuring the IL.

Prove a fix with a **negative control in one script**: reproduce the broken state (kill only
whkd, restart it by hand), print the measurements, then apply the official pairing command and
print them again. A rule that reproduces the bug on demand is a rule you can trust.

## Restarting without losing the layout

komorebi dumps and re-applies its own layout, but that dump only reflects the state at
the moment of the stop — so a deterministic restart must snapshot and then **write the
snapshot back**.

- `komorebic stop --whkd` is **graceful**: it writes the full layout to
  `%TEMP%\komorebi.state.json` and removes the whkd komorebi owns. The next start
  **auto-applies** that file. Verified: a window sent to workspace 5 came back on workspace 5
  after a stop/start cycle.
- `.Kill()` / `Stop-Process` is **not** graceful: no dump is written, so the layout is gone and
  the next instance starts empty. A hard kill also leaves `komorebi.hwnd.json` and
  `komorebi.sock` behind, and a new instance can attach to that dead IPC surface. Clear both
  when the stop was not graceful.
- **The auto-dump is not a restore guarantee.** `komorebic stop` writes the state file from
  whatever komorebi sees *at that instant*. If the layout had already collapsed (a crash, a
  stray kill, a deleted state file), the dump faithfully records the collapsed layout and the
  next start faithfully restores it. The user-visible symptom is "the restart lost my
  windows".

### Deterministic restore: snapshot -> stop -> write the snapshot back

`komorebic state` emits **exactly** the same JSON document as the state file komorebi
auto-applies (verified: identical top-level keys). That makes the snapshot both a record
and the restore payload:

```powershell
$raw = & komorebic.exe state                       # 1. snapshot - keep the WHOLE document
Set-Content $snapshotPath -Value $raw -Encoding UTF8

& komorebic.exe stop --whkd                        # 2. graceful stop - OVERWRITES the state file

Set-Content $StateFile -Value $raw -Encoding UTF8  # 3. write the snapshot BACK  <-- the restore

Start-ScheduledTask -TaskName 'Komorebi'           # 4. start; it applies the file
```

Step 3 MUST come after step 2 — `komorebic stop` overwrites the state file, so a write-back
before the stop is discarded. Measured: this returns every window to its exact
monitor/workspace (9/9) both with the state file present and with it deleted beforehand.

- **Do not hand-roll a per-window restore.** `move-to-workspace` / `move-to-monitor-workspace`
  act on the **focused** window, and forcing a window to the foreground does not make komorebi
  treat it as focused — measured 3/7 correct. The state-file write-back is the only mechanism
  that reliably restores the layout.
- **A verification step that only reports a discrepancy is not a restore.** A script that diffs
  the snapshot, prints `[WARN] window moved` and exits leaves the layout wrong, and the user
  reads "warned" as "not fixed". Diff to decide, then act, then re-read state and report the
  real outcome.

Correct order: freeze the watchdog -> snapshot `komorebic state` -> `komorebic stop --whkd` ->
kill only *stragglers* (an orphan whkd the graceful stop did not own, or a komorebi that
survived) -> clear stale IPC files -> **write the snapshot back** -> `Start-ScheduledTask
-TaskName Komorebi` -> start the bar standalone (it is not a komorebi child) -> re-read state
and report the outcome.

Procedure, script skeleton, and the verification block: `references/restart-and-elevation.md`.

## Pitfalls

- **whkd is a low-level keyboard HOOK, not `RegisterHotKey`.** whkd uses the
  `win-hotkeys` crate (`SetWindowsHookEx(WH_KEYBOARD_LL)`). A `RegisterHotKey`
  probe therefore reports every whkd binding as FREE even when whkd is perfectly
  healthy — never use that probe to judge hotkey liveness. Test by calling
  `komorebic` directly and diffing state, or by pressing the key.
- **komorebi core has no whkd ownership check.** `grep -rn whkd komorebi/src/*.rs` is
  empty; `komorebic start --whkd` merely runs a PowerShell `Start-Process whkd`. That does
  NOT make the health check's `whkd PAIRING: BROKEN` a false positive: the probe is a proxy
  for the variable that actually decides the outcome, which is **integrity level**. A whkd
  spawned by the elevated `--whkd` path is High; a whkd started by hand from an ordinary
  shell is Medium and genuinely inert against komorebi's High-IL named pipe. Trust the probe,
  then confirm it by measuring the IL — see *The integrity chain* above.
- **`replace-configuration` rebuilds the whole window manager** (`*self = wm` in
  `process_command.rs`). Calling it repeatedly in quick succession deadlocks the
  socket: the process stays alive and `Responding=True` but every `komorebic`
  call panics with `os error 10060`. Recovery needs kill-all **plus** deleting
  `komorebi.sock` / `komorebi.hwnd.json`, then starting via the elevated logon
  task. Space out calls by >=5s.
- **The health check's `VERDICT` can read HEALTHY on a deadlocked socket** — it
  only checks for the process. Always read `socket alive` and `monitors`
  separately.

- **Starting komorebi from a non-elevated shell silently disables elevated-window
  support.** `start-all.ps1` run from an ordinary terminal gives komorebi Medium
  integrity, so it cannot manage Administrator windows. Use the elevated logon
  task (`Start-ScheduledTask -TaskName Komorebi`, RunLevel=Highest), an elevated
  terminal, or Windows Startup. Read the real integrity level with
  `OpenProcess(0x1000)` + `TokenIntegrityLevel` — never with the 0x0410 mask,
  which UIPI denies and which reports a false "not elevated".
- When you change `komorebi.json`, restart via the **elevated logon task** —
  see *The integrity chain* above for why a plain `start-all.ps1` is not a valid
  recovery step when elevated-window support matters.
- Editing the JSON then running `reload-configuration` applies nothing — that command
  only re-runs the legacy ps1/ahk wrapper. Rely on the file watcher, use
  `replace-configuration`, or restart. (Conversely: do not credit
  `reload-configuration` when a JSON edit does take effect — the watcher did it.)
- Do not conclude a config rule was rejected because it is absent from
  `global-state` right after an edit — the watcher needs a moment. Re-check after a few
  seconds, or force it with `replace-configuration`.
- A `Title`-based ignore rule silently never matches a late-titled window —
  eligibility is evaluated once at creation and `TitleUpdate` only refreshes the
  bar. Match on `Exe`/`Class`, or accept the window cannot be distinguished at
  decision time.
- `komorebic ignore` purges currently-managed matching windows from the layout,
  and the purge can close the window rather than merely unmanage it.
- Do not add `SetForegroundWindow` / `EnumWindows` focus-stealing loops to
  scripts that run on the live desktop — it corrupts ALT+TAB order and window
  focus system-wide, and recovery needs `kill-all` + `start-all`.
- **Never loop a config-apply command in a test harness.** Each
  `replace-configuration` rebuilds the entire window manager; a loop over it races
  on the socket and deadlocks the process. Apply once, verify, move on.
- **Elevation is inherited at spawn — the START MECHANISM sets it, not the kill method.**
  `Start-Process whkd.exe` from an ordinary shell yields whkd at **Medium** integrity, because
  the child inherits the caller's token; `Start-ScheduledTask -TaskName Komorebi` runs
  `komorebic.exe start --whkd` at RunLevel=Highest, so komorebi **and** the whkd it spawns are
  both **High**. Mirroring `kill-all.ps1` + `start-all.ps1` works only because that pair is run
  *as Administrator* — the elevation is the load-bearing part, not the `Start-Process` call.
  Copying the kill/start calls without the elevated context is what reproduces the bug, so
  never replace `Start-ScheduledTask` with `Start-Process` when elevated-window support matters.
  Full procedure: `references/restart-and-elevation.md`.
- **Windows 11 copy/cut/delete progress is NOT a separate window.** It is rendered
  inside the Explorer window (title bar + taskbar), so `ignore_rules` with
  `Class` or `Title` cannot match it. Do not spend hours trying to trigger a
  progress dialog for probing — if it does not appear after 2-3 attempts, try a
  different approach or report the constraint. See
  `references/windows11-copy-progress.md` for details.
- **Use the user's `komorebi-service.ps1` for startup/watchdog, never a raw task XML,
  and never `powershell.exe` as a task action** — it blinks a console every interval.
  The repair script and the GUI-subsystem rule are in
  `references/repair-script-and-watchdog.md`.
- **Do not get stuck in loops when probing windows.** If an approach fails after
  2-3 attempts, try a different strategy or report the blocker. The user expects
  progress, not repeated failed attempts. "Continue and finish" means find a way
  forward, not repeat the same failing action.
- **A WPF app pushed across a monitor boundary on a multi-monitor desk needs an
  `ignore_rules` entry, not a repositioning script.** Matching the app's `Exe`
  leaves it exactly where it is put, because komorebi stops managing it. This is the
  standard fix to offer for any WPF window the user runs (their own utilities
  included), and it is a komorebi bug rather than an app bug — other WPF windows
  (legacy shell applets, Device Manager, Disk Management) show it too, which is
  worth saying in the UI copy so the user knows why the switch exists.
- **Do not name a PowerShell helper after a built-in verb family.** Defining a function
  called `Compare` makes `Compare $a $b 'label'` fail with "A positional parameter cannot be
  found that accepts argument 'label'" — PowerShell resolves the name to the cmdlet family
  and the call dies before your body runs. The same applies to `Where`, `Select`, `Format`,
  `Test`. Use an unambiguous name (`Test-Lay`, `Get-Diff`) in throwaway probe scripts too:
  a verification script that crashes mid-run reports a false FAIL and hides the real result.
- **When a config bug is found, grep the repo for every other copy of the same
  assumption.** A shipped template, a test assertion, and a design doc each restate
  the same key name or invariant. Fixing only the live config leaves the next install
  — and the suite — reproducing the bug. Fix the template and the assertions in
  the same change, and add an assertion that the obsolete form is *absent*, so a silent
  regression fails the gate instead of the user's keyboard.

## Editing the config file from a script

Adding a rule programmatically (an installer step, or a GUI button) has four traps
of its own. Full recipe: `references/scripted-config-edits.md`.

- **`ConvertTo-Json`/`ConvertFrom-Json` need `-Depth 32`, not the default 2.** The
  file nests monitors and workspaces past depth 2, and the depth cap silently
  replaces deeper levels with `System.Object[]` strings — a write-back built from a
  default-depth round-trip destroys the layout with no error and still passes
  `komorebic check`.
- **Create an absent rule array rather than assuming it exists.** Optional arrays
  (`ignore_rules`, `manage_rules`) are legitimately missing from a valid config; use
  `Add-Member -Force` when `PSObject.Properties[...]` is absent.
- **Check for a matching manage rule before claiming the ignore rule works.** An
  ignore rule is inert while a manage rule matches the same `Exe` — warn instead of
  reporting success. See the rule-evaluation model above.
- **Verify by re-parsing the file, not by exit code.** Round-trip both versions
  through an independent parser and diff them semantically; the depth bug is only
  visible there. Write UTF-8 **without BOM** (serde rejects it).

## Safe-change discipline

The target desktop is a working system, not a testbed: existing Komorebi/WHKD
behaviour is correct and must not be disturbed.

- Classify a change before applying it: runtime rule = reversible by restart;
  JSON edit = applies only at a restart; restart = re-tiles everything.
- Do not add a force-manage rule to work around an over-managed window — it
  newly tiles windows that were previously unmanaged and re-tiles existing ones
  at the next restart.
- When the fix is not achievable inside the tool's constraints, report the
  constraint and leave the system untouched. Shipping a change that alters
  working behaviour is worse than shipping no change.
- **Always take a backup before changing any config file.** Copy the current
  file to a backup location (e.g. `config/last-backup/`) before making any
  edits. This allows quick rollback if something goes wrong.
- **Rename old scripts before replacing them.** When rewriting a script, rename
  the old version (e.g. `safe-restart-v1.ps1`) before placing the new one.
  This preserves the working version for reference and rollback.
- **Do not create new bugs while fixing existing ones.** The user's primary
  concern is system stability. Every change must be verified to not break
  existing functionality. Test thoroughly before reporting completion.
