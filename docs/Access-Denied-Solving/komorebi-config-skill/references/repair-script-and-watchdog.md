# Repair script + watchdog/startup mechanism (2026-10-10)

## The repair script

`H:\Repo\komorebi-1click\docs\Access-Denied-Solving\Access-Denied-0x80070005-fixing.ps1`

Diagnoses and repairs all four gates idempotently. Run it after any Komorebi upgrade
(it detects the unpatched binary and re-applies both patches). Auto-elevates itself;
`-DryRun` reports without changing anything; `-NoElevate` skips the self-relaunch.

It refuses to patch unless `komorebic --version` reports `0.1.41` AND both call sites
re-locate at the expected offsets. A wrong-version upgrade therefore fails loudly
instead of corrupting `komorebi.exe`.

`patch_final2.py` in the same folder reproduces the patched binary byte-for-byte from
`Komorebi-Patched\komorebi.exe.orig` (verified by matching MD5).

## Watchdog and startup: use the user's komorebi-service.ps1

The service script is the better mechanism, not a raw `schtasks` XML:

- full health check (process + socket + whkd pairing + monitors + tiled windows)
- mutex so two restarts can never race
- 90 s wait for a restart already in flight
- whkd pairing check (alt+shift+o must restart a *new* whkd)
- graceful stop, stale IPC cleanup, PATH refresh
- elevation-aware principal: `RunLevel=Highest` when elevated

Register it **elevated** so both tasks land at `RunLevel=Highest`:

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',
  'H:\Repo\komorebi-1click\scripts\komorebi-service.ps1','-Action','install'
```

## The flashing PowerShell window

A scheduled task running `powershell.exe` **always** blinks a console on screen, no
matter what flags are passed (`-WindowStyle Hidden`, `-NonInteractive`, `wscript`, a
`.vbs` wrapper, `-EncodedCommand`). Task Scheduler creates the console and only hides
it *afterwards*, so the window appears briefly every interval.

The only fix is a **GUI-subsystem** launcher, which is never given a console at all.
That is what `komorebi-watchdog.cs` builds: `%USERPROFILE%\bin\komorebi-watchdog.exe`,
PE subsystem `2` (GUI). The task must run that exe, never `powershell.exe`.

Verify after registering:

```powershell
$b = [IO.File]::ReadAllBytes("$env:USERPROFILE\bin\komorebi-watchdog.exe")
[BitConverter]::ToUInt16($b, [BitConverter]::ToInt32($b,0x3C) + 0x5C)   # 2 == GUI, no console
```

Also: a raw `schtasks /create` XML plus a service-script installer can double up. Let
the service script register both tasks itself, and delete any batch-file Startup entry
— two launchers racing means two komorebi processes fighting over the same socket.

## Keep the repo config in sync with the live machine

A reinstall overwrites `%USERPROFILE%\komorebi.json` from the repo template. If the
template is older than the live config, the reinstall silently reverts it. This is how
one incident started: the template's `applications.json` path pointed at a file the
cleanup script deletes.

After any live config edit, copy it back to `H:\Repo\komorebi-1click\config\` so the
installer ships exactly what the machine runs. Verify with matching MD5 hashes.
