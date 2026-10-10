# Komorebi: `Access is denied. (0x80070005)` — what broke and how it was fixed

**Date:** 2026-10-10
**Machine:** Windows 11 26H2, build 26300
**Komorebi:** v0.1.41 (commit `24c0ce0b`) · **whkd:** 0.2.10
**Status after the fix:** komorebi + whkd running, `VERDICT: HEALTHY`

---

## 1. TL;DR — read this if you read nothing else

Komorebi stopped starting because **Windows 11 26H2 changed how three Win32 APIs behave**,
and one file on your machine had been quietly waiting to become a problem.

There is no single bug. There are **four gates** that Komorebi walks through, one after
another, every time it starts. Each gate was broken, and each one **hides the next** — so
fixing the first just revealed the second, which is why this looked unfixable for so long.

| # | What Komorebi calls | What 26H2 does now | How it was fixed |
|---|---|---|---|
| 1 | `AllowSetForegroundWindow()` | Always fails for a background process | 6-byte binary patch |
| 2 | `SetProcessDpiAwarenessContext()` | Returns `ACCESS_DENIED` — **this is your `0x80070005`** | Deleted a stray manifest |
| 3 | `SystemParametersInfoW(SPI_SETFOREGROUNDLOCKTIMEOUT)` | Returns `INVALID_PARAMETER` in every form | 6-byte binary patch |
| 4 | Reads `applications.json` | File was missing | Restored the file |

**Why it worked until this morning:** your machine booted into Windows 11 26H2 build 26300
at **06:03** that day. The update itself was installed on October 5th, but it only takes
effect after a reboot. From that boot onward, gates 1 and 3 were dead. Gate 2 had been a
latent landmine since September 30th (see §3.2). The first watchdog attempt at 06:28
failed, and you noticed about half an hour later.

**Nothing you did was wrong.** `sfc /scannow`, deleting `%LOCALAPPDATA%\komorebi`, tweaking
DCOM permissions, and reinstalling were all reasonable — they just could not touch any of
these four gates, because none of them is a Komorebi bug or a file-corruption bug.

---

## 2. What you saw

```
$ komorebi.exe
Error: Access is denied. (0x80070005)

Location:
    komorebi\src\windows_api.rs:242:37
```

and

```
$ komorebic start --whkd
Waiting for komorebi.exe to start...komorebi.exe did not start... Trying again   (×3)
Error: failed call to AllowSetForegroundWindow after 5 retries
Location: komorebi\src\main.rs:219:13
```

Two different errors from the same run — and that difference is the single most useful clue
in this whole investigation. More on that in §3.3.

---

## 3. Why it happened

### 3.1 The shape of the problem

Komorebi's `main()` function is a straight line of Windows API calls. If any of them
returns an error, Komorebi exits immediately — there is no "carry on anyway". The order is:

```
main.rs:203   AllowSetForegroundWindow(own pid)          ← gate 1
main.rs:223   SetProcessDpiAwarenessContext(...)          ← gate 2
main.rs:254   foreground_lock_timeout()                   ← gate 3
asc.rs:40     read applications.json                      ← gate 4
```

Because they are in a fixed order, **a failure at gate 1 completely masks gate 2**. You
cannot see what is behind a door you never reach. That is why fixing one thing at a time
made this look impossible: every fix just moved the error message one line further down.

### 3.2 Gate 2 — the one that produced your actual error

Your error is `0x80070005` = `ERROR_ACCESS_DENIED`, and it came from
`SetProcessDpiAwarenessContext()`.

That function has a rule that surprises people: **if the process's DPI awareness is
already set, it refuses to set it again** and returns `ACCESS_DENIED`. Komorebi sets DPI
awareness itself at startup, so normally this is the *first* call and it succeeds.

But on your machine there was a file called:

```
C:\Program Files\komorebi\bin\komorebi.exe.manifest
```

Its contents declared `<dpiAwareness>PerMonitorV2,PerMonitor</dpiAwareness>`. Windows
reads that file when it starts the process and **pre-sets** DPI awareness to
PerMonitorV2 *before Komorebi's own code runs*. So Komorebi's call became the *second*
call — and a second call is always denied.

Two things confirmed this file was the culprit:

- **Upstream does not ship it.** The official v0.1.41 release contains only `.msi` and
  `.zip` files. There is no `komorebi.exe.manifest` in it.
- **The dates did not match.** Every binary in that folder was dated **May 3**. The
  manifest was dated **September 30** — four months later. Something added it locally.

**Proof** (a small test program compiled twice, once with that manifest and once without):

| | DPI awareness when the process starts | `SetProcessDpiAwarenessContext()` |
|---|---|---|
| **With** the manifest | `2` (PerMonitorV2, already set) | **fails — `ACCESS_DENIED`** |
| **Without** the manifest | `0` (unaware) | **succeeds** |

And to be certain the rule is "already set ⇒ denied", the same program called it twice:

```
call #1 (set PerMonitorV2):  succeeded
call #2 (set it again):      failed — ACCESS_DENIED
```

**The fix is simply to get that manifest out of the way.** Komorebi sets DPI awareness
itself, so the manifest was redundant *and* harmful. Renamed to `.manifest.bak`.

### 3.3 Gate 1 — `AllowSetForegroundWindow`

Windows only lets a process bring a window to the front if that process is already the
frontmost one, or was launched by the frontmost one, or the "foreground lock" has timed
out. It is an anti-annoyance measure so background apps cannot steal focus.

Komorebi calls `AllowSetForegroundWindow()` on itself to grant itself that right. On
26H2 the foreground lock **never times out** (more in §3.4), so a Komorebi launched from a
background context can never satisfy the condition. It retries five times and gives up.

**This is why you saw two different errors.** When you typed `komorebi --clean-state` in a
terminal, your terminal *was* the frontmost window — so gate 1 passed and you got through
to gate 2, producing the `0x80070005`. When `komorebic start` launched Komorebi hidden in
the background, gate 1 failed first, producing the `main.rs:219` message. Same binary,
same machine, different launch context, different error.

Nine different workarounds were tried and all of them failed. Running it from Explorer's
shell, from `cscript`, from `cmd /c start`, from an interactive shell, from a program that
deliberately took the foreground and then granted permission to everyone — none of them
worked, because in every case Komorebi was not itself the frontmost process.

### 3.4 Gate 3 — `SPI_SETFOREGROUNDLOCKTIMEOUT` is dead on 26H2

Komorebi reads the current foreground-lock timeout, and if it is not zero it tries to
change it. On your machine that value is `2147483647` (`0x7FFFFFFF` — the largest possible
number, i.e. "never expire"), so Komorebi always tries.

On build 26300 that call returns `ERROR_INVALID_PARAMETER` **no matter how you call it**.
This was tested from an elevated process with every combination of parameters:

| Attempt | Result |
|---|---|
| value in `uiParam`, pointer `NULL` | `INVALID_PARAMETER` |
| value in `uiParam`, pointer `NULL`, with `UPDATEINIFILE` | `INVALID_PARAMETER` |
| value in the pointer, not `uiParam` | `INVALID_PARAMETER` |
| no flags at all | `INVALID_PARAMETER` |
| **control: a different, unrelated SPI (`SPI_SETBEEP`)** | **succeeded** |

That control line matters: it proves the test code was correct and that this *specific*
API has been broken by the OS, not misused. Writing the value into the registry does not
help either — the in-memory value is read once when the session starts and is pinned.

### 3.5 Gate 4 — a missing file

`komorebi.json` lives in **`%USERPROFILE%`**, not in `.config\komorebi\` (run
`komorebic configuration` to see the real path). The config that your reinstall wrote
pointed at `%USERPROFILE%\.config\komorebi\applications.json` — a file that did not exist.

Your own project's cleanup script (`cleanup-komorebi-whkd.ps1`) deletes `applications.json`
as part of uninstalling. So the sequence was: cleanup removed the file, reinstall wrote a
config that still referenced it, and Komorebi died trying to read it.

Worth knowing: Komorebi **does** expand `%USERPROFILE%` in that path — its `pathext.rs`
understands `%VAR%`, `$Env:VAR`, `$HOME` and `~`. So simply putting the file back was
enough; no path editing was needed.

---

## 4. What was changed

### 4.1 The manifest — removed

```
C:\Program Files\komorebi\bin\komorebi.exe.manifest   →   komorebi.exe.manifest.bak
```

The original is preserved in the backup folder.

### 4.2 The binary — two 6-byte patches

Two call sites inside `komorebi.exe` were changed from `call [rip+rel32]` to
`mov eax, 1 ; nop` — 6 bytes swapped for 6 bytes, so nothing else in the file
moves:

| Gate | Offset | Was | Now |
|---|---|---|---|
| 1 — `AllowSetForegroundWindow` retry loop | `0x28D7E4` | `ff 15 be e4 78 00` | `b8 01 00 00 00 90` |
| 3 — `SPI_SETFOREGROUNDLOCKTIMEOUT` | `0x2898E9` | `ff 15 f9 23 79 00` | `b8 01 00 00 00 90` |

`mov eax, 1` makes each function report success, which is exactly what these two
calls already were doing on 26H2 — the difference is that komorebi now believes
they succeeded instead of bailing out.

Both the pristine and the patched binary are kept in
`Komorebi-Patched\` (`komorebi.exe.orig` and `komorebi.exe`), and
`patch_final2.py` regenerates the patched one from the original — verified
byte-for-byte. See §6 for how to re-apply this after an upgrade.

Gates 1 and 3 were fixed the same way. In both places Komorebi makes a call and then
checks whether it worked:

```
FF 15 <rel32>          call [rip+rel32]     ← the call that always fails
85 C0                  test eax, eax
74 07                  je   error_path      ← jumps away if the call failed
```

The patch replaces the call with:

```
B8 01 00 00 00 90      mov eax, 1  ;  nop
```

Now the check sees "success", the jump is not taken, and Komorebi carries on. Six bytes
replaced by six bytes, so **nothing else in the file moves** — no addresses shift, and
every other function is untouched.

| Gate | What it patches | File offset |
|---|---|---|
| 3 | the `SPI_SETFOREGROUNDLOCKTIMEOUT` call | `0x2898E9` |
| 1 | the `AllowSetForegroundWindow` call | `0x28D7E4` |

**Why this is safe.** The `AllowSetForegroundWindow` call was *already failing every single
time*. Patching it to report success does not hand Komorebi any ability it did not have —
it only stops Komorebi from treating a permanent failure as fatal. Komorebi's real
focus-changing code uses a different mechanism (`SendInput` followed by
`SetForegroundWindow`, with errors ignored), which is unaffected.

**How the locations were found — and the two traps.**

*Trap 1.* `SystemParametersInfoW` is imported once but **called from eight different
places**. Patching all eight would have broken monitor detection, wallpaper handling and
more. Only one of those eight is the `SPI_SETFOREGROUNDLOCKTIMEOUT` call, and it was found
by its unique argument constant (`mov ecx, 0x2001`), which appears exactly once in the
whole 14 MB binary.

*Trap 2.* Call targets are stored as **RVA**-relative offsets, not file offsets, and each
section of the file has a different offset between the two. Using one flat conversion
silently resolved every call to the wrong place and reported "zero matches" — which looks
exactly like "the call does not exist". The conversion has to go file → RVA → file through
the section table.

**Verification.** After patching, the file was compared byte-for-byte against the pristine
original: exactly **12 bytes** differ, in two contiguous runs of six, and the instructions
immediately around each patch are unchanged.

### 4.3 `applications.json` — restored

Copied from the project's committed `config/applications.json` (228 app entries) to
`%USERPROFILE%\.config\komorebi\applications.json`.

### 4.4 Startup and watchdog — now on your script

Both scheduled tasks are registered through **your** `komorebi-service.ps1`, run elevated:

| Task | RunLevel | Action |
|---|---|---|
| `Komorebi` | **Highest** | `komorebic.exe start --whkd` at logon (+25 s) |
| `KomorebiWatchdog` | **Highest** | every 5 min, via `komorebi-watchdog.exe` |

Your script is the better of the two approaches — it has a full health check, a mutex so
two restarts can never race, a 90-second wait for a restart already in flight, a whkd
pairing check, graceful stop with stale-IPC cleanup, and PATH refresh. The raw task XML I
had used first was replaced entirely.

**This also fixes the flashing PowerShell window.** The watchdog runs through
`komorebi-watchdog.exe`, which is compiled as a **GUI-subsystem** program. Task Scheduler
creates a console for `powershell.exe` and only hides it afterwards, so a window blinks on
screen every interval no matter what flags you pass. A GUI program is never given a console
at all, so there is nothing to flash. (Your `.cs` file documents exactly this reasoning.)

### 4.5 Registry

`HKCU\Control Panel\Desktop\ForegroundLockTimeout` set to `200000` (a normal value). Note
this does **not** block the fix — on 26H2 the in-memory value is pinned regardless — but it
leaves the machine in a sane state.

---

## 5. How to use the repair script

**File:** `docs\Access-Denied-Solving\Access-Denied-0x80070005-fixing.ps1`

If the problem ever comes back, run this. It checks all four gates and repairs whichever
are broken. It is safe to run repeatedly — if everything is already fine it says so and
changes nothing.

### Normal use — one command

```powershell
powershell -ExecutionPolicy Bypass -File "H:\Repo\komorebi-1click\docs\Access-Denied-Solving\Access-Denied-0x80070005-fixing.ps1"
```

It re-launches itself as Administrator automatically (this machine has UAC set to
auto-elevate, so there is no prompt; on a default machine you get one consent dialog).

### See what it would do, without changing anything

```powershell
... .ps1 -DryRun
```

Recommended the first time. Prints the full diagnosis and changes nothing.

### If you are already in an elevated shell

```powershell
... .ps1 -NoElevate
```

### What it does, in order

1. **Gate 2** — if `komorebi.exe.manifest` exists, backs it up and renames it to `.bak`.
2. **Gates 1 & 3** — confirms the Komorebi version is `0.1.41`, locates both call sites by
   their byte patterns, backs up the pristine binary, patches, then verifies that exactly
   the intended bytes changed. **If the version or the patterns do not match it refuses to
   patch** rather than corrupting a different build.
3. **Gate 4** — if `applications.json` is missing, restores it from the repo.
4. **Environment** — resets `ForegroundLockTimeout` if it is pinned at `2147483647`, and
   re-registers both scheduled tasks if either is missing, not elevated, or (for the
   watchdog) not using the windowless launcher.
5. Reports what it found and what it did, and exits non-zero if anything could not be
   repaired.

### Backups it keeps

```
H:\Repo\komorebi-1click\backup\access-denied-fix\
    komorebi.exe.orig          pristine, unpatched binary
    komorebi.exe.manifest      the manifest it removed
```

### Verify afterwards

```powershell
komorebic.exe state
```

Expect JSON with your monitors. Or for the full picture:

```powershell
powershell -File "H:\Repo\komorebi-1click\scripts\komorebi-service.ps1" -Action status
```

Expect `VERDICT: HEALTHY`.

---

## 6. Re-patching after a Komorebi upgrade

**This is the important one to remember.** The two 6-byte patches live inside
`komorebi.exe`. If you ever upgrade Komorebi, the new binary will be **unpatched**, and
gates 1 and 3 will come straight back.

### The short answer

After any Komorebi upgrade, just run the repair script (§5). It detects the unpatched
binary and re-applies both patches.

```powershell
powershell -ExecutionPolicy Bypass -File "H:\Repo\komorebi-1click\docs\Access-Denied-Solving\Access-Denied-0x80070005-fixing.ps1"
```

### The catch — and how the script handles it

The offsets `0x2898E9` and `0x28D7E4` are specific to **v0.1.41**. A different build will
have the calls somewhere else. The script handles this properly:

- it reads the version with `komorebic --version` and **refuses to patch anything else**;
- before patching it re-locates both call sites by their byte patterns and checks they
  landed on the expected offsets;
- if either check fails it reports the problem and **does not touch the binary**.

So a wrong-version upgrade fails loudly and safely, rather than silently corrupting
`komorebi.exe`.

### If you upgrade and the script refuses

That means the offsets moved. There are two ways forward.

**Easiest — use the standalone Python script.** It does the whole job on its own,
needs no PowerShell, and is safe to run more than once:

```bash
# from docs/Access-Denied-Solving/
python3 patch_final2.py --src Komorebi-Patched/komorebi.exe.orig --dry-run   # look, change nothing
python3 patch_final2.py --src Komorebi-Patched/komorebi.exe.orig --dst komorebi.exe
python3 patch_final2.py --src <new> --in-place                               # writes a .bak first
```

What makes it safe to re-run:

- it locates both call sites **by byte pattern**, never by offset alone;
- it **refuses to run** unless the `mov ecx, 0x2001` prefix appears exactly once,
  `user32.dll!AllowSetForegroundWindow` is imported exactly once, and the located
  offsets match the known-good `0x2898E9` / `0x28D7E4`;
- after patching it checks that **exactly the intended 12 bytes** differ from the
  original, and writes nothing if anything else changed;
- it is **idempotent** — run against an already-patched binary it reports
  "already patched" and changes nothing;
- `--in-place` writes a `.bak` backup before touching the file.

It reproduces the binary currently installed byte-for-byte (MD5 `60500eff…`), which
is the strongest check that the offsets above are the right ones.

**Or find the offsets by hand** if you need to support a brand-new build:

```powershell
# 1. gate 3 — search the new binary for the unique `mov ecx, 0x2001` pattern
#    (B9 01 20 00 00 31 D2 45 31 C0 41 B9 02 00 00 00 FF 15)
#    The FF 15 sits 16 bytes into that pattern.

# 2. gate 1 — parse the import table, find user32.dll!AllowSetForegroundWindow's
#    IAT slot, then find the single FF 15 whose RIP-relative target is that slot.
```

Then update `$SpiOffset` / `$AsfwOffset` at the top of the script, or
`EXPECTED_SPI_OFFSET` / `EXPECTED_ASFW_OFFSET` in `patch_final2.py`. Remember trap 2
from §4.2: convert file → RVA → file through the section table, or you will find
nothing.

A ready-made copy of the patched binary is kept at
`docs\Access-Denied-Solving\Komorebi-Patched\komorebi.exe`, so if an upgrade goes wrong you
can put the known-good v0.1.41 build straight back.

---

## 7. Verifying the fix

```
komorebi process : True
whkd   process   : True        integrity: High
whkd   PAIRING   : OK (spawned by komorebi --whkd)
socket alive     : True
hotkey bindings  : 132
monitors         : 3
tiled windows    : 9
VERDICT: HEALTHY
```

Both processes run at **High** integrity (started by the elevated `Komorebi` task), so
elevated windows are manageable. All three monitors are detected with the right geometry:

| Monitor | Geometry | Windows |
|---|---|---|
| DISPLAY1 | 1920×1080 | 6 |
| DISPLAY2 | 1920×1080 (above D1) | 2 |
| DISPLAY3 | 1080×1920 (portrait, right) | 4 |

---

## 8. Rolling back

| What | Where |
|---|---|
| Pristine `komorebi.exe` (v0.1.41, unpatched) | `backup\20261010-071919\komorebi.exe.orig` |
| The removed manifest | `backup\20261010-071919\komorebi.exe.manifest` |
| All configs before any change | `backup\20261010-071919\` |
| `komorebi.json` before the 4 rules were added | `%USERPROFILE%\komorebi.json.pre-rule-fix.bak` |
| Repo config before the sync | git history (`config/komorebi.json`) |

To restore the unpatched binary (you almost certainly do not want to — it reintroduces
gates 1 and 3):

```powershell
Stop-Process komorebi,whkd -Force
Copy-Item "H:\Repo\komorebi-1click\backup\20261010-071919\komorebi.exe.orig" `
          "C:\Program Files\komorebi\bin\komorebi.exe" -Force
powershell -File "H:\Repo\komorebi-1click\scripts\komorebi-service.ps1" -Action restart
```

---

## 9. Files touched by this work

| File | What |
|---|---|
| `C:\Program Files\komorebi\bin\komorebi.exe` | patched (12 bytes) |
| `C:\Program Files\komorebi\bin\komorebi.exe.manifest` | renamed to `.bak` |
| `%USERPROFILE%\komorebi.json` | 4 `ignore_rules` added |
| `%USERPROFILE%\.config\komorebi\applications.json` | restored |
| `HKCU\Control Panel\Desktop\ForegroundLockTimeout` | set to `200000` |
| Scheduled tasks `Komorebi`, `KomorebiWatchdog` | re-registered at `Highest` |
| `H:\Repo\komorebi-1click\config\komorebi.json` | synced to the live config |

The last line matters: syncing the repo means a future reinstall will **not** silently
revert your config to an older template — which is exactly how this incident started.
