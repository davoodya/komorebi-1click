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

The Sandbox run itself is the single outstanding verification step for all four tickets.
It requires no decisions — only launching `sandbox.wsb` and reading the printed result.
