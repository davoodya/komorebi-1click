# Elevated Windows & Git Bash Support in Komorebi

**Status:** FIXED and verified (2026-10-02)
**Scope of this fix:** make Komorebi manage (a) applications launched as Administrator, and (b) `git-bash.exe` / `mintty`. No other behavior was touched.

---

## 1. Symptom

| Application | Before | After |
|---|---|---|
| `cmd.exe` / `pwsh.exe` / `powershell.exe` launched **as Administrator** | not detected, not tileable, not reachable by any `whkd` hotkey | managed and fully tileable |
| `git-bash.exe` — **non-elevated** | not detected | managed and fully tileable |
| `git-bash.exe` — **elevated** | not detected | managed and fully tileable |

Note the two rows have **two different root causes** even though the symptom looks identical to the user.

---

## 2. Root cause 1 — elevated applications

### 2.1 The mechanism (Windows, not Komorebi)

Windows isolates processes by **integrity level**. A process started normally runs at *Medium* integrity; an elevated process runs at *High* integrity.

**UIPI (User Interface Privilege Isolation)** is a mandatory rule, not a bug: a process at a lower integrity level **cannot** perform window-management operations on a process at a higher one. The blocked operations are exactly what a window manager needs:

- `SetWindowPos` / `MoveWindow` (moving and resizing tiles)
- `SetForegroundWindow` (focus and focus-follows-mouse)
- `ShowWindow` / hiding
- attaching borders to another process's window
- enumerating via `EnumWindows` in some situations

Komorebi was started from a plain (Medium integrity) shell context, so it was a *Medium* integrity process. Every elevated window was, from its point of view, read-only: it could see the window existed, but every attempt to move, tile, focus, or hide it was silently denied by the kernel.

This is why the failure looked "random": the elevated application ran fine, its window was visible, it simply never appeared in the tiling layout and no hotkey could touch it.

### 2.2 The fix — run Komorebi itself at High integrity

The correct and only supported remedy is to run the window manager **above** every window it must manage. The launch was re-registered so the scheduled task starts `komorebic.exe` at the **Highest** run level, which makes the `komorebi.exe` process inherit High integrity.

The watchdog task that respawns Komorebi if it dies was re-registered identically, so the elevation survives restarts.

**Verification of the elevated state:**

```
Komorebi        : Ready  runlevel=Highest
KomorebiWatchdog: Ready  runlevel=Highest
```

### 2.3 Why this is safe — no client breakage

The legitimate concern is that elevating the server might break non-elevated clients (`komorebic` CLI calls, the watchdog, YASB, custom scripts).

It does not. Komorebi listens on a **Unix Domain Socket** (`komorebi.sock`) created with `uds_windows`. UDS on Windows is not access-controlled by a security descriptor the way named pipes are, and the code removes and re-creates the socket on startup. A non-elevated client can still connect to an elevated listener.

Evidence: after the change, `komorebic state` / `reload-configuration` / `move-to-workspace` still work from an ordinary shell, YASB still renders workspaces, and the watchdog still reports healthy.

### 2.4 Elevation is not a magic wand

Being elevated lets Komorebi **act** on a window, but it does not change what it **decides** to manage. That is a separate rule engine, and it is what caused the second bug.

---

## 3. Root cause 2 — Git Bash (elevated *and* non-elevated)

### 3.1 Git Bash does not have its own window

`git-bash.exe` is only a launcher. It spawns `mintty.exe`, and **mintty** owns the visible window. Its Win32 class is exactly `mintty`, and its executable is `C:\Program Files\Git\usr\bin\mintty.exe`.

So any rule aimed at `git-bash.exe` matches nothing — there is no window owned by `git-bash.exe`. Every rule for Git Bash must target **`mintty`**.

### 3.2 The real blocker: `WS_EX_LAYERED`

The mintty window has these styles:

```
style  = 0x14ef0000   -> WS_CAPTION ✓, WS_THICKFRAME ✓
exstyl = 0x00080100   -> WS_EX_WINDOWEDGE ✓, WS_EX_LAYERED ✓
```

Komorebi decides whether a window is tileable in `window.rs :: window_is_eligible()`. Simplified to the branch that matters here:

```rust
if (allow_wsl2_gui
     || allow_titlebar_removed
     || style.contains(CAPTION) && ex_style.contains(WINDOWEDGE))
    && !ex_style.contains(DLGMODALFRAME)
    && (allow_layered || !ex_style.contains(LAYERED))   // <-- mintty dies here
    || managed_override
{
    return true;
}
```

mintty passes `CAPTION` and `WINDOWEDGE`, so it gets past the first gate — but it carries `WS_EX_LAYERED`, and `allow_layered` is only set for windows that Komorebi itself has made transparent or that are explicitly listed in `layered_whitelist`.

So the LAYERED clause is `false || !true` = **false**, and the whole window is rejected. The window is not ignored because of elevation at all — it is refused because it is a layered window.

**The comment in source explains why the filter exists:** layered windows make tiling redraw "go crazy" on focus-change events and produce ghost tiles. The default is deliberately conservative; you must opt a specific app in.

### 3.3 The fix — `layered_applications`

> **CRITICAL — input key name.** The key in `komorebi.json` is **`layered_applications`**.
> `layered_whitelist` is the name of the same list in `komorebic global-state` **output**;
> it is **not** a valid input key. `StaticConfig` in komorebi 0.1.41 has no
> `deny_unknown_fields`, so serde drops an unknown key **silently** — no error, no warning,
> and `komorebic check` still exits 0. An earlier revision of this document used
> `layered_whitelist`, which is exactly how the elevated-console regression shipped and
> then survived every restart undetected. Verified against
> `komorebi/src/static_config.rs:631` (`pub layered_applications: Option<Vec<MatchingRule>>`)
> and `komorebi/src/state.rs:143` (`pub layered_whitelist` — the serialized output name).

`komorebi.json` gained exactly one entry, scoped to the single offending class:

```json
"layered_applications": [
    { "kind": "Class", "id": "mintty", "matching_strategy": "Equals" }
]
```

This is the purpose-built mechanism: it sets `allow_layered = true` for that class alone and lets mintty pass the style gate. It does **not** touch the LAYERED filter for any other application, and it does not disable any of Komorebi's other window-management logic.

Applied with `komorebic reload-configuration`.

**Why class, not exe:** the class string `mintty` is stable and identical for Git Bash, Cygwin and MSYS2 consoles. Matching on `mintty.exe` would also work but is narrower with no benefit here.

---

## 4. What changed on disk

Exactly one file, plus the two scheduled tasks.

| Object | Change |
|---|---|
| `C:\Users\DavoodYa\komorebi.json` | +1 key: `layered_applications` with the `mintty` class rule. `manage_rules`, `ignore_rules`, monitors, workspaces — **untouched**. |
| Scheduled task `Komorebi` | re-registered, `RunLevel Highest` |
| Scheduled task `KomorebiWatchdog` | re-registered, `RunLevel Highest` |

Pre-change timestamped backup:
`F:\Backups\Software-Backups\komorebi-whkd\config-backups\komorebi.json.bak-2026-10-02_15-54-39-layeredwhitelist`

`whkdrc` was **not** modified — hotkeys were already per-monitor and correct.

---

## 5. Verification

All checks were run live against the real desktop.

### 5.1 Elevated cmd / pwsh / powershell

```
managed windows before: 13
launch elevated cmd.exe
managed windows after : 14
NEW managed: cmd.exe
```

### 5.2 Git Bash, non-elevated

```
launch C:\Program Files\Git\git-bash.exe
MANAGED: exe=mintty.exe class=mintty @ DISPLAY1/
```

### 5.3 Git Bash, elevated

```
launch C:\Program Files\Git\git-bash.exe -Verb RunAs
MANAGED: exe=mintty.exe class=mintty @ DISPLAY1/
total managed windows: 14
```

### 5.4 It is genuinely manageable, not merely listed

The decisive test — move the elevated mintty window between workspaces:

```
location right after launch : DISPLAY1 (workspace 3), DISPLAY1 (workspace 4)
komorebic move-to-workspace 2
location after move          : DISPLAY1 (workspace 3) x3
```

The window actually moved. A window that only *appears* in state but cannot be moved would still be broken.

### 5.5 No collateral damage

```
komorebi 53528 / whkd 49736 / yasb 27280  — all still running, unchanged start times
Komorebi: Ready (runlevel Highest)
KomorebiWatchdog: Ready (runlevel Highest)
workspace sets intact on all three monitors
whkdrc hotkeys: alt+1..9 -> focus-workspace 0..8 (per-monitor), unchanged
```

---

## 6. Notes for the installer

For the packaging work in the other session, the installation must reproduce these two decisions; a default `komorebi start` will not.

1. **Register the startup task with `-RunLevel Highest`.** Without this, elevated applications are silently unmanageable. This needs elevation once, at install time. Because UAC is disabled on this machine, the registration itself happens without a prompt; on a normal machine the installer will trigger exactly one UAC dialog.
2. **Write `layered_applications` into the generated `komorebi.json`** with the `mintty` class entry.
   The key is `layered_applications`, **not** `layered_whitelist` (that is the `global-state`
   output name; serde ignores the wrong key silently). Omitting it restores the Git Bash failure.
3. **The watchdog task must also be `-RunLevel Highest`**, otherwise a respawned Komorebi silently drops back to Medium and elevated windows stop being manageable after the first watchdog restart — a confusing regression that only appears later.
4. Prefer `layered_applications` over `manage_rules` for mintty. `manage_rules` bypasses *all* eligibility checks as `managed_override`, which is a bigger hammer and changes layout behaviour; `layered_applications` changes only the one gate that was actually blocking.
5. If Git Bash is upgraded/reinstalled the class stays `mintty`, so the rule survives; only a move to a different terminal (e.g. Windows Terminal) would need a new entry.

---

## 7. Quick troubleshooting

| Symptom | Check |
|---|---|
| Elevated app not managed | `Get-ScheduledTask Komorebi` → must show `runlevel=Highest` |
| Git Bash not managed | `komorebi.json` must contain `layered_applications` with `Class = mintty`, then `komorebic reload-configuration` |
| Elevated `cmd`/`pwsh`/`powershell` not managed | `layered_applications` must also contain `Class = ConsoleWindowClass`; verify with `komorebic global-state` |
| `layered_whitelist` present in the file but has no effect | wrong key name — it is the `global-state` output name; rename to `layered_applications` |
| Worked, then broke after a restart | the watchdog task's run level — it must also be `Highest` |
| Config change had no effect | the command is `reload-configuration`, not `config-reload` |
| Cannot tell which process owns a window | Git Bash's window belongs to `mintty.exe`, class `mintty`, not to `git-bash.exe` |

## 8. Known limitations (not done — out of scope)

- **WSLg / `PseudoConsoleWindow`** windows are still not managed. This is a known Komorebi area; it needs its own analysis and would be a separate change.
- Other layered apps (some terminal and Electron builds) would each need their own `layered_applications` entry. There is no global opt-out, and adding one would re-enable the ghost-tile behaviour the filter exists to prevent.
