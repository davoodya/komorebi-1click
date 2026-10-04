# Testing komorebi-1click

The test procedure is defined by **ADR-0008** and lives in one place:

| Artifact | Purpose |
|---|---|
| `tests/sandbox-test-suite.ps1` | The single authoritative suite — every assertion for tickets 01, 02, 03 and 04 |
| `sandbox.wsb` | Windows Sandbox config: maps the repo read-only as `C:\Repo`, disables networking, runs the suite at logon |
| `docs/sandbox-test-harness.ps1` | Optional host-side launcher: sanity-checks the repo, then opens `sandbox.wsb` |
| `docs/adr/0008-testing-strategy-revised.md` | Why tests run in the Sandbox and never on the production reference machine |

## The test environment (why Windows Sandbox)

The installer's whole purpose is to reconfigure a live Windows desktop — the window
manager, the hotkey daemon, the taskbar, the logon tasks and the machine PATH. That
cannot be tested on the machine it is being developed on: that machine is the production
reference system, and even a no-op re-run risks disturbing a working configuration
(ADR-0008 records this decision and the reasoning).

Windows Sandbox is the chosen environment because it is already enabled on this host,
is disposable by design (nothing persists past close), needs no ISO, and maps the repo
in as a read-only folder so no copy step is required. VirtualBox remains the fallback
for tests that must persist across reboots or attach N monitors.

## How a coding agent runs the tests (no UI required)

Windows Sandbox is driven entirely from the command line, which is what makes this
procedure usable without ever touching a GUI:

1. Launch the Sandbox headlessly with the repo's config. The `.wsb` file is the entire
   environment definition — it maps `H:\Repo\komorebi-1click` to `C:\Repo` read-only,
   disables networking (the install must be fully offline), and auto-runs the suite at
   logon:

   ```powershell
   Start-Process 'H:\Repo\komorebi-1click\sandbox.wsb'
   ```

2. The suite runs at logon inside the Sandbox. If it does not, run it manually in the
   Sandbox window:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\Repo\tests\sandbox-test-suite.ps1 -Repo C:\Repo
   ```

3. Read the result. The suite prints a `[PASS]`/`[FAIL]` line per assertion, ends with
   `TOTAL FAILURES: N`, and exits `1` on any failure. Closing the window discards the
   whole machine, so nothing can leak back to the host.

The only step that needs a human is pasting the output back — the Sandbox console is not
reachable from WSL, so its stdout cannot be captured programmatically.

## What the suite verifies

**T01 — repo payload + provenance (ticket 01):** all five install payloads are present
and non-empty, every pinned SHA256 in `binaries/payloads.sha256.json` matches the
committed binary, all four license texts are shipped, and each payload's official release
URL is recorded.

**T02.0–T02.2 — clean install (ticket 02):** the machine starts clean (no komorebi,
whkd, YASB, AutoHotkey, no config), `Install.ps1` exits 0, all five binaries land at the
vendor-default `C:\Program Files\...` paths, and `komorebic`/`whkd` report the expected
versions.

**T03.1–T03.4 — configuration generation (ticket 03):** `komorebi.json` is written for
the target user with at least one monitor block and 9 workspaces,
`app_specific_configuration_path` points at *this* user and `applications.json` is there,
`whkdrc` and the YASB config exist, `komorebi-resize.json` is created empty, the
`layered_whitelist` retains the mintty rule, no source-machine username or path appears
anywhere under `.config`, and `komorebic check` exits 0 on the generated config.

**T04.1b — whkd pairing (new, 2026-10-04):** after a real install the suite now
asserts `Get-Health.WhkdPaired` is true. A whkd that is alive but was not
spawned by `komorebic start --whkd` silently drops every hotkey while the rest
of the WM looks healthy — this is the exact regression the postmortem
(`docs/POSTMORTEM-20261004-whkd-pairing.md`) was written for.

**T04.1c — komorebi is ELEVATED (new, 2026-10-04):** asserts the running
komorebi holds an elevated token. An unelevated window manager cannot manage
elevated windows or the Hermes window, and the reference account is not an
Administrator, so the only reliable path to an elevated komorebi is the
`Komorebi` logon task at RunLevel Highest. The probe uses
`PROCESS_QUERY_LIMITED_INFORMATION` (0x1000) — the older
`PROCESS_QUERY_INFORMATION` mask is denied under UIPI and silently reports
every process as non-elevated.

**T04.1d — secondary install failures do not abort (new, 2026-10-04):** four
source-level assertions that `Install.ps1` splits its payloads into a primary
group (Komorebi, WHKD) that aborts the run on failure and a secondary group
(YASB, AutoHotkey) that reports the failure and continues. See
`docs/INSTALL-FAILURE-HANDLING.md`.

**T04.1e — restart-whkd goes through the elevated task (new, 2026-10-04):**
asserts `restart-whkd.ps1` stops via `komorebic stop --whkd`, starts via
`Start-ScheduledTask -TaskName 'Komorebi'`, and verifies the pairing
afterwards, exiting non-zero when it is broken.

**Ticket 08 — `tests/ticket08-ahk.tests.ps1` (new, 2026-10-04):** 17 assertions
covering the AutoHotkey lifecycle. State defaults, a disabled script rendering
as a commented-out VBS line with the `[disabled:<name>]` marker, the
persist-and-regenerate round-trip, degradation to defaults on a corrupt state
file, path-portability of the four new scripts, clean parsing, and cleanup
removing the leftovers. Runs entirely against a sandbox copy; containment is
verified after every run (3 AHK processes, Startup VBS intact).

**T04.1–T04.4 — startup machinery (ticket 04):** the `Komorebi` logon task exists at
`RunLevel Highest` with a logon trigger running `komorebic.exe start --whkd`; the
`KomorebiWatchdog` task exists at `RunLevel Highest`, repeats every 5 minutes, invokes
`komorebi-service.ps1 -Action watchdog` through the windowless GUI-subsystem launcher;
`komorebic.exe` resolves from PATH and is the installed binary; YASB autostart is enabled;
and no legacy `komorebi.lnk` racing shortcut remains in the Startup folder.

**T05 — idempotency (cross-ticket):** a second full `Install.ps1` run exits 0, leaves
`komorebi.json` byte-identical, leaves both scheduled tasks and the YASB autostart
setting unchanged, and the config still validates.

## Static checks that may run on the development machine

ADR-0008 permits read-only, non-installing verification on the reference machine. The
T01 section of the suite (payloads, SHA pins, licenses, provenance URLs) is exactly that
kind of check — it only reads files and never executes the installer. It has been
verified to pass against the current tree (27/27 assertions). Everything from T02 onward
must run in the Sandbox.

## Current status

| Ticket | Implementation | Test status |
|---|---|---|
| 01 — repo + binaries + provenance | done (commit 942ff3e) | assertions defined; T01 verified statically, 27/27 |
| 02 — installer core | done (commit 942ff3e) | assertions defined; awaits a Sandbox run |
| 03 — configuration generation | done (commit adb050b) | assertions defined; awaits a Sandbox run |
| 04 — startup tasks | done (commit 887db72) | assertions defined; awaits a Sandbox run |
| 05 — AutoHotkey integration | done | `ticket05-06-07.tests.ps1` T05.1–T05.4, 13/13 static PASS; awaits a Sandbox run |
| 06 — management-script portability | done | `ticket05-06-07.tests.ps1` T06.1–T06.5 static PASS; awaits a Sandbox run |
| 03-followup — dead whkdrc hotkeys | done | T03f.1–T03f.2 (in the static suite and the Sandbox suite) |
| 07 — export / import ZIP | done | T07.1–T07.4 static PASS + a full export→import round trip verified in a sandbox profile |

## Tickets 05, 06 and 07 — what was built and how it is verified

All three are covered by **two** independent layers, so nothing is left to a visual check.

### Layer 1 — static, runs on the development machine (no Sandbox)

`tests/ticket05-06-07.tests.ps1` — 61 assertions, exit 0 against the current tree:

- **T05.1–T05.4 (ticket 05):** the three `.ahk` scripts ship in the repo; `AppRunner.vbs` is a
  template carrying only the `RunHidden`/`RunNormal` helpers and the `AppRunnerEnd` marker; the
  interpreter paths are the vendor defaults; and the *generated* VBS names every shipped script
  with no leftover marker and no machine path. This proves the generation logic, not just that a
  file exists.
- **T06.1–T06.5 (ticket 06):** no management script references the source user or the `F:` backup
  drive; each documented switch (`-Components`, `-Scope`, `-Percent`, `-ZipPath`) is *declared*,
  *used* and backed by a `[ValidateSet]`; the companion scripts resolve their binaries through
  `common.ps1` or the repo marker rather than hardcoded paths; the watchdog mutex and the YASB
  registry PATH rebuild are intact; and every script parses cleanly.
- **T03f (the whkdrc follow-up):** `alt + shift + o` is bound and `alt + o` is deliberately
  unbound; `alt + ctrl + t` and `alt + ctrl + shift + r` are bound to the scripts the installer
  now ships; every `.config` path the whkdrc names is a file the installer supplies; and the
  `New-Whkdrc` rewrite is proven by running it — it emits `C:\TARGETUSER\.config\...`, never the
  source user.
- **T07.1–T07.4 (ticket 07):** the script ships and parses; the CLI form and the dialog form reach
  the same code; the archive covers the full config set; compression is `System.IO.Compression`
  with no third-party dependency; resize state is exported only when non-empty; and an import
  always backs the live config up and stops/starts the WM around the restore.

### Layer 2 — the Sandbox suite (real install, real target machine)

`tests/sandbox-test-suite.ps1` gained two new blocks that run *after* a real `Install.ps1`:

- **T03f.1–T03f.2** — the repaired bindings are actually present in the generated whkdrc, and the
  three files those hotkeys call exist in `%USERPROFILE%\.config`, including the
  `safe-restart.repo.txt` marker.
- **T07.1–T07.3** — a real export→import round trip: snapshot the live config by SHA256, export to
  a ZIP, import it back, and assert every file is byte-identical afterwards, plus that a
  `pre-import-backup-*` directory holding the old whkdrc was left behind.

### The export→import round trip, verified

`config-export-import.ps1` was executed end to end against a sandboxed profile (a fake
`%USERPROFILE%` under `%TEMP%`, so the reference machine was never touched):

```
export:  archive written: ...\k1c-t7-rt2\backup.zip (9 entries)
import:  current config backed up to: ...\pre-import-backup-20261004-043615
         9 file(s) restored.
verify:  komorebi.json: KJSON-V4      whkdrc: WHKDRC-V4      widget: WIDGET-V4
         komorebi.json NOT wrongly in .config: True
```

Two real bugs were found and fixed by exactly this test before any code was committed:

1. `komorebi.json` lives in `%USERPROFILE%`, not `.config`, so the restore loop wrote it to the
   wrong directory and the WM kept the stale file. The archive now maps top-level names back to
   their real home.
2. `CreateEntryFromFile` is an *extension* method, so it has to be called through
   `[System.IO.Compression.ZipFileExtensions]`, not on the `ZipArchive` object itself.
