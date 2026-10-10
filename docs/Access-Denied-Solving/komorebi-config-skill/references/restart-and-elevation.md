# Restarting komorebi + whkd + yasb without losing state or elevation

Depth for the restart procedure. The always-on rules live in SKILL.md; this file is the
recipe, the failure modes it avoids, and the verification block to ship.

## The four ways a restart breaks, and the mechanism behind each

| # | Failure | Mechanism | Avoided by |
|---|---|---|---|
| 1 | Windows detected but not manageable | whkd started outside the elevated spawn path -> Medium IL -> its dispatch shell is Medium -> `komorebic.exe` cannot open the High-IL named pipe | `Start-ScheduledTask -TaskName Komorebi` |
| 2 | Elevated windows fall out of management | komorebi started from an ordinary shell -> Medium IL | same |
| 3 | Layout lost | `.Kill()` tears the process down before it dumps `%TEMP%\komorebi.state.json` | `komorebic stop --whkd` first |
| 4 | Watchdog race / dead IPC | the 5-minute watchdog can start a second komorebi inside the restart gap; a hard kill leaves `komorebi.hwnd.json` + `komorebi.sock` stale | freeze the task, clear the files |
| 5 | Layout comes back wrong, not merely empty | the graceful dump records whatever komorebi sees *at stop time*, so a layout that had already collapsed is faithfully re-applied | snapshot `komorebic state` and write it back after the stop |

Failure 5 is the subtle one: it looks like "restore is broken" but the restore worked
perfectly — it restored the wrong thing. Fix the payload, not the restore mechanism.

## Why the Scheduled Task is the only reliable elevated start

`Start-Process -Verb RunAs` cannot be used unattended on a non-Administrator account: there
is no one to answer the consent prompt, and `ConsentPromptBehaviorAdmin=0` does not
auto-elevate a standard user. The installer therefore registers a logon task at
`RunLevel=Highest` whose action is `komorebic.exe start --whkd`. Starting that task is the
supported way to get an elevated komorebi together with a whkd it owns:

```powershell
Start-ScheduledTask -TaskName 'Komorebi'
```

Read the task's XML to confirm both properties before relying on it:

```powershell
Export-ScheduledTask -TaskName 'Komorebi'    # expect RunLevel HighestAvailable
```

## Procedure

```powershell
# 1. SNAPSHOT the layout - keep the WHOLE `komorebic state` document. It is the
#    same JSON the state file holds, so it doubles as the restore payload.
$raw = & komorebic.exe state
Set-Content $snapshotPath -Value $raw -Encoding UTF8

# 2. freeze the watchdog so it cannot start a second instance mid-restart
Disable-ScheduledTask -TaskName 'KomorebiWatchdog'

# 3. GRACEFUL stop - this is what dumps the layout
komorebic stop --whkd

# 4. kill only STRAGGLERS. The graceful stop removes komorebi and the whkd it
#    owns; a whkd that was started standalone is owned by nobody and survives -
#    that survivor IS the broken state and must go.
#    Also kill a komorebi that survived the graceful stop.

# 5. clear IPC handles the graceful stop did not clean
Remove-Item "$env:LOCALAPPDATA\komorebi\komorebi.hwnd.json" -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\komorebi\komorebi.sock"      -ErrorAction SilentlyContinue

# 6. WRITE THE SNAPSHOT BACK - this is the restore. It must come AFTER the stop,
#    because `komorebic stop` overwrites the state file with its own dump.
Set-Content "$env:TEMP\komorebi.state.json" -Value $raw -Encoding UTF8

# 7. elevated + paired start: ONE command delivers both fixes
Start-ScheduledTask -TaskName 'Komorebi'

# 8. the bar is NOT a komorebi child - start it standalone, with PATH rebuilt from
#    the registry so its komorebi widgets resolve

# 9. re-enable the watchdog in a finally block so a crash cannot leave it disabled
```

## Verification block to print at the end

Three separate lines, never one combined "healthy" verdict — they fail independently:

```
=== verification ===
  komorebi     running      IL=High
  whkd         running      IL=High
  whkd pairing OK - owned by komorebi
  layout       RESTORED - all 3 window(s) in place
```

- **IL** from the `0x1000` token probe (see SKILL.md). Never `0x0410`.
- **pairing** from the process tree: an officially spawned whkd hangs off a transient
  launcher that has already exited, so its parent PID resolves to nothing. A standalone whkd
  keeps a live shell as an ancestor.
- **layout** by diffing the step-1 snapshot against live state, matching on `hwnd` and
  comparing monitor/workspace/container. Diff to DECIDE, then restore, then re-read and
  report the real outcome — never print a warning and stop.

## Test the restore against a collapsed layout, not a healthy one

A restore that passes on a healthy system proves nothing: the graceful dump already had the
right layout, so the write-back was never exercised. Force the failure first:

1. Scatter windows into distinctive workspaces (record the exact monitor/workspace per hwnd).
2. Delete `%TEMP%\komorebi.state.json` to simulate a crash or hard kill.
3. Run the restart, then diff against the recorded target.

Both runs must be 9/9 (or N/N). Verify the per-window **fallback** separately if you keep
one: `move-to-workspace` acts on the focused window, and forcing a window to the foreground
does not make komorebi treat it as focused — that path measured 3/7 and is not a restore.

When pairing reads BROKEN, print the recovery pair inline so the operator never has to hunt:

```
FIX: komorebic stop --whkd ; then Start-ScheduledTask -TaskName Komorebi
```

## Reporting honesty

Report what the measurements say, not what the script intended. If the IL line reads Medium,
say so and say which layer failed — a restart that leaves Medium integrity is a failed
restart even when all three processes are running and the exit code is 0.
