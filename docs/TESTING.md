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
| 05–07 — AHK + script portability + export/import | done | `ticket05-06-07.tests.ps1` — **65 assertions, 0 failures** on the live machine |
| 08 — AutoHotkey lifecycle | done | `ticket08-ahk.tests.ps1` — **17 assertions green** |
| 09 — EXE install wrapper | done (`f5363e6`) | `ticket09-exe-wrapper.tests.ps1` — **26 assertions green**, PS 5.1 + PS 7 |
| 10 — Dashboard shell | done | `ticket10-dashboard-shell.tests.ps1` — **128 assertions** |
| 11 — no-lag execution | done (`da42d3a`) | `ticket11-threading.tests.ps1` — **67 assertions**, launches the EXE |
| 12 — theme + elevation | done (`639216a`) | `ticket12-theme-elevation.tests.ps1` **48** + `ticket12-runtime.tests.ps1` **16** |
| 13 — publish pipeline | done (`07e374e`) | `ticket13-publish.tests.ps1` **15** + `ticket13-runtime.tests.ps1` **24**. **D-T1 still open** — see below. |

The Sandbox run itself is the single outstanding verification step for all four tickets.
It requires no decisions — only launching `sandbox.wsb` and reading the printed result.

## DEFERRED TESTS — to run when ticket implementation is finished

Registered 2026-10-05 at Davood's instruction, so they are not lost between sessions. Neither
can be proven on the development machine: both need an environment this machine is not.
**Do not attempt either one until the tickets are implemented.**

### D-T1 — run with no .NET 8 runtime installed  (blocks on: ticket 13)

| | |
|---|---|
| **What** | Launch the published self-contained `KomorebiDashboard.exe` on a machine with **no** .NET 8 Desktop Runtime, and confirm it opens its main window and that `--help` and a read-only verb work. |
| **Why deferred** | This machine has the .NET 8 SDK, so a framework-dependent run would also work and prove nothing. The whole point of ticket 13's `SelfContained` flag is untested until the runtime is absent. |
| **How** | Windows Sandbox (`sandbox.wsb`, networking disabled) or any VM without the runtime. The Sandbox already maps the repo read-only as `C:\Repo`. |
| **Pass criteria** | Window handle non-zero; `--help` exits 0; the app does **not** print "You must install .NET" or `0x80008096`. |
| **Fails if** | The app depends on a machine-installed runtime, or a satellite/native DLL was left beside the EXE and is missing. |
| **Blocks** | Ticket 13 cannot be called done. ADR-0015 lists this as required Sandbox verification. |

### D-T2 — observe the real UAC prompt  (blocks on: ticket 12, verifiable in ticket 14)

| | |
|---|---|
| **What** | On a **UAC-enabled** machine, trigger an admin verb (`kill-komorebi`) from the unelevated Dashboard and confirm the three-button dialog appears, `Rerun as Administrator` raises a genuine UAC prompt, and the relaunched instance reports `IsElevated=True`. Then confirm `Cancel` leaves the system untouched. |
| **Why deferred** | This machine has **UAC disabled** (recorded in ADR-0012 Consequences), so the prompt cannot appear at all. What *is* proven here is the gate's decision and exit code, not the OS prompt. |
| **How** | Any UAC-enabled target, or enable UAC on a disposable VM. Test with the dashboard **not** started as administrator, or the gate is bypassed. |
| **Pass criteria** | Prompt appears once and is attributable to our relaunch; the elevated instance reports `IsElevated=True`; `Cancel` and `OK` both change nothing. |
| **Fails if** | Two instances linger, the relaunch silently fails, or elevation is requested for a non-admin verb. |
| **Note** | ADR-0012 explicitly accepts the two-instance overlap (the unelevated one exits immediately after spawning). Confirm that assumption here rather than assuming it. |

Both rows above stay in this file until real evidence replaces them. Neither may be marked
passed on the strength of the development-machine evidence described elsewhere in this document.

## The Dashboard suites are different in kind

Tickets 09–12 do **not** belong in `sandbox-test-suite.ps1`. They need a Windows desktop with
the .NET 8 SDK, and they run on the development machine against the real tree:

- `tests/ticket11-threading.tests.ps1` and `tests/ticket12-theme-elevation.tests.ps1` both
  **start the EXE and require a non-zero window handle**. That is deliberate: defect D18 (no
  `x:Name` on the six views, so `FindName` returned null and the app died at startup) was
  invisible to 123 static assertions because nothing launched the app.
- `tests/ticket12-runtime.tests.ps1` builds a throwaway probe project under
  `tests/.build/` (gitignored) that references the real dashboard, hosts the actual `App`, and
  reads the brushes WPF resolves. It asserts on observed colours — Dark `202020` vs Light
  `FAFAFA`, 443 merged dictionary keys — rather than on a variable that merely flipped. It
  touches nothing: no process is started or stopped, no script is run.
- `tests/dashboard-paths.ps1` is a **shared helper, not a suite**. It resolves the built EXE by
  globbing `bin\Release\**\KomorebiDashboard.exe`. Ticket 13 added `RuntimeIdentifier=win-x64`,
  which pushed `dotnet build` output into a `win-x64\` subfolder and broke the three suites that
  hardcoded the old path. Globbing also survives the win-x86 matrix ADR-0015 defers to v2.
- `tests/ticket13-publish.tests.ps1` checks the publish **flags** (and can run `dotnet publish`
  itself; pass `-NoPublish` to skip). `tests/ticket13-runtime.tests.ps1` checks the **artefact**:
  exactly one file in `releases/`, both runtime packs and the R2R marker present *inside* the
  binary, and the app launching from an isolated temp directory containing only the EXE. The
  split matters — a framework-dependent build passes the flag suite and also launches on this
  machine, so only the bundle scan distinguishes them.

Run them from Windows, not from WSL:

```powershell
foreach ($t in @('ticket05-06-07','ticket08-ahk','ticket09-exe-wrapper',
                 'ticket10-dashboard-shell','ticket11-threading',
                 'ticket12-theme-elevation','ticket12-runtime',
                 'ticket13-publish','ticket13-runtime','ticket-monitor')) {
    & "H:\Repo\komorebi-1click\tests\$t.tests.ps1"
}
```

Note `ticket05-06-07.tests.ps1` never calls `exit`, so `$LASTEXITCODE` is blank after it. That is
a property of that suite, not a failure — read its printed `assertions:` / `failures:` lines
instead of the exit code.

`ticket08-ahk` and `ticket05-06-07` write to the live Startup folder and the live `autohotkey`
directory. Verify `AppRunner.vbs` is still present and the AutoHotkey interpreters are still
running after they finish — `ticket08` runs `ahk-cleanup`, which removes generated artifacts.
