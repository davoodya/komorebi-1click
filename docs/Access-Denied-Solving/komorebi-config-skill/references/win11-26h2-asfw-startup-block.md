# Windows 11 25H2/26H2: komorebi refuses to start — the full four-gate stack

Verified 2026-10-10 on Windows 11 26H2 build 26300, komorebi v0.1.41 (whkd 0.2.10),
on a machine where komorebi had been running fine until it stopped.
Upstream bug: https://github.com/LGUG2Z/komorebi/issues/1699

## Symptom

```
$ komorebi.exe
Error: failed call to AllowSetForegroundWindow after 5 retries
Location: komorebi\src\main.rs:219:13
```

```
$ komorebic start --whkd
... komorebi.exe did not start... Trying again   (x3)
Error: failed call to AllowSetForegroundWindow after 5 retries
```

`sfc /scannow`, deleting `%LOCALAPPDATA%\komorebi`, DCOM permissions, and a plain
reinstall do **not** fix it.

## The four gates — fix them in this order

komorebi's `main()` walks a fixed sequence. Each gate hides the next one, so a
fix at gate N immediately exposes gate N+1. Fixing only the first looks like
"it still doesn't work".

| # | Call site | Failure on 26H2 | Fix |
|---|---|---|---|
| 1 | `allow_set_foreground_window()` main.rs:203-221 | `AllowSetForegroundWindow(own_pid)` fails for any non-foreground process | binary patch |
| 2 | `set_process_dpi_awareness_context()` main.rs:223 | `ERROR_ACCESS_DENIED` when the process is already DPI-aware | delete the external manifest |
| 3 | `foreground_lock_timeout()` main.rs:254 | `SPI_SETFOREGROUNDLOCKTIMEOUT` returns `ERROR_INVALID_PARAMETER` in every form | binary patch |
| 4 | `ApplicationSpecificConfiguration::load()` core/asc.rs:40 | `os error 2` — the `app_specific_configuration_path` file is missing | restore `applications.json` |

Gates 1 and 3 are Windows regressions. Gate 2 is a **machine-local** defect: an
external `komorebi.exe.manifest` declaring `PerMonitorV2` DPI awareness, which
Windows honours at process start, making komorebi's own runtime DPI call a
second (already-set) call. Gate 4 is usually collateral damage from running the
project's `cleanup-komorebi-whkd.ps1`, which deletes `applications.json`, while
`komorebi.json` still references it.

## Gate 2 — the external manifest (machine-local, no binary patch)

Upstream v0.1.41 does **not** ship `komorebi.exe.manifest` (the release is only
`.msi` + `.zip`). On this box the binaries were dated `May 3` but
`komorebi.exe.manifest` was dated four months later — added locally, not by the
release. komorebi sets DPI awareness itself at runtime, so the manifest is both
redundant and harmful.

Proof (a probe compiled with and without the same manifest):

| | DPI awareness at start | `SetProcessDpiAwarenessContext(-4)` |
|---|---|---|
| with manifest | `2` PerMonitorV2 (pre-set) | **`False` ERROR_ACCESS_DENIED** |
| without manifest | `0` UNAWARE | **`True` OK** |

And the control that proves the semantics — calling it twice in one process:

```
call#1 (set PMV2): True
call#2 (set PMV2 again): False ERROR_ACCESS_DENIED
```

**Fix:** rename `C:\Program Files\komorebi\bin\komorebi.exe.manifest` to `.bak`.
No binary change. komorebi then sets its own awareness on the first call.

## Gate 3 — SPI_SETFOREGROUNDLOCKTIMEOUT is dead on 26H2

`SPI_GETFOREGROUNDLOCKTIMEOUT` returns `2147483647` (0x7FFFFFFF, never expires)
regardless of the registry value, so komorebi's `if value != 0` branch always
runs and calls `SystemParametersInfoW(SPI_SETFOREGROUNDLOCKTIMEOUT, 0, NULL,
SPIF_SENDCHANGE)`. On build 26300 that SET returns `ERROR_INVALID_PARAMETER` in
**every** parameter form, even from a High-IL process:

| attempt | result |
|---|---|
| uiParam=0, pv=NULL, SPIF_SENDCHANGE | err=87 |
| uiParam=0, pv=NULL, UPDATEINIFILE\|SENDCHANGE | err=87 |
| uiParam=0, pv=NULL, flags=0 | err=87 |
| uiParam=200000, pv=NULL | err=87 |
| uiParam=0, pv=&0 | err=87 |
| uiParam=0, pv=&200000 | err=87 |
| control: SPI_SETBEEP(1, NULL) | **True OK** |

The control proves the P/Invoke is sound and the SPI itself is blocked. Writing
`HKCU\Control Panel\Desktop\ForegroundLockTimeout` (0, 150000, 200000 — all tried)
does not change the in-memory value. **Do not spend time on runtime SPI
workarounds.**

## Gate 1 — AllowSetForegroundWindow for background processes

The foreground lock never expires (see above), so a komorebi launched from a
background context can never satisfy "the calling process can set the foreground
window" and bails after 5 retries. Running it from a foreground terminal passes
this gate — which is why a direct `komorebi --clean-state` reports a *different*
error than `komorebic start`.

Workarounds tested and **all failed** — do not retry them: `Shell.Application`
ShellExecute, `cscript` + `WScript.Shell.Run`, `cmd /c start /b`, `Start-Process`
from an interactive shell, a WinForms launcher that takes the foreground and
calls `ASFW_ANY` (that call succeeds, but komorebi calls ASFW **on itself** and
child-of-foreground does not inherit the right on this build),
`AllowSetForegroundWindow(komorebi_pid)` right after spawn (err=87),
`CreateProcess` with `CREATE_NEW_CONSOLE`, and `AttachThreadInput` (err=5 against
a higher-IL foreground window).

## The binary patch (gates 1 and 3)

Both are the identical 6-byte swap at their single call site:

```
FF 15 <rel32>        call qword ptr [rip+rel32]   ->   B8 01 00 00 00 90   mov eax,1 ; nop
```

`test eax,eax` then sees 1, the `je` to the error path is not taken, and the
wrapper returns `Ok(())`. Length-preserving, so no RVA or rel32 shifts.

Locating the sites (parse the PE, never guess):

- **Gate 3** — the unique `mov ecx, 0x2001` action constant, which appears
  exactly once in the binary, followed by `xor edx,edx / xor r8d,r8d /
  mov r9d,2 / FF 15 <rel32>`. On this build: call at file offset `0x2898E9`.
- **Gate 1** — the *single* `FF 15` whose RIP-relative target is
  `user32.dll!AllowSetForegroundWindow`'s IAT slot. On this build: `0x28D7E4`.

Two traps when resolving the indirect calls:

1. `SystemParametersInfoW` is imported once but **called from 8 sites**. Patching
   all of them breaks monitor enumeration, wallpaper and more. Only the `0x2001`
   site may be touched.
2. RIP-relative targets are **RVAs**, not file offsets, and the section deltas
   differ (`.text`: rawptr-vaddr = -0xC00, `.rdata`: -0x1A00). Converting with a
   single flat formula silently resolves every call to the wrong slot and reports
   zero matches. Convert file->RVA->file through the section table.

Patch only after backing up the pristine binary. Verify by diffing against the
original: exactly 12 differing bytes, in two contiguous runs of 6, with the
surrounding instruction bytes unchanged.

## Gate 4 — the missing applications.json

`komorebi.json` lives in **`%USERPROFILE%`**, not `.config\komorebi\`
(`komorebic configuration` prints the real path). A reinstall can write a config
with `"app_specific_configuration_path": "%USERPROFILE%\.config\komorebi\applications.json""`
while the file itself is gone. komorebi **does** expand `%USERPROFILE%`
(`PathExt::replace_env` in `core/pathext.rs` handles `%VAR%`, `$Env:VAR`, `$HOME`
and `~`), so restoring the file is sufficient — no path edit needed.

Restore from the repo's committed `config/applications.json` (the source of
truth, not a backup).

## Verifying the fix

```powershell
Get-Process komorebi,whkd | Select Name,Id,SessionId
komorebic.exe state        # monitors + is_paused
komorebic.exe global-state # ignore/manage/layered counts actually loaded
```

A working end state on this box: both processes at **High** integrity started by
the `Komorebi` logon task (`RunLevel=HighestAvailable`), 3 monitors, and the full
rule set loaded (172 ignore / 24 manage / 12 layered identifiers).

## Ordering note for the whole job

Back up the configs FIRST (`komorebi-backup.ps1`, or copy `komorebi.json`,
`whkdrc`, `applications.json` and the `applications-*.json` set), then fix the
gates in the table order. The state file `%TEMP%\komorebi.state.json` is what
restores the layout — a graceful `komorebic stop --whkd` writes it, a hard kill
does not.
