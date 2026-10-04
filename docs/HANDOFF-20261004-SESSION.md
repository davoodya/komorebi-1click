# Handoff — komorebi-1click, session 2026-10-04 (Tickets 01–08 + geometry fix)

**Date:** 2026-10-04 (audit session — **updated later the same day**)
**Supersedes:** `~/projects/komorebi-1click/docs/HANDOFF-20261004-TICKETS-01-07.md`
(that document remains accurate for tickets 01–07 and the whkd/elevation
postmortems; this one adds Ticket 08, the monitor-geometry fix, the standing
rules, and the test policy.)
**Next session focus:** implement **Ticket 09** (EXE wrapper).
**Ticket order (decided 2026-10-04):** sequential **09 → 10 → 11 → 12 → 13 → 14**.

> ### ⚠️ READ THIS FIRST — later update to this handoff
> An **audit session** ran after this document was first written. It audited the
> whole project, closed **10 defects (D1–D10)**, and opened **D11**. The durable
> reference is now the **`handoff/` directory** — read those four documents
> instead of re-auditing:
>
> - `handoff/komorebi-1click-description.md` — structure, rules, defect ledger
> - `handoff/komorebi-1click-knowledges.md` — **the traps; read before coding**
> - `handoff/komorebi-1click-completed-steps.md` — every ticket + commit
> - `handoff/komorebi-1click-bugs-issues.md` — every bug + D1–D11
>
> **What the audit changed:**
> - **Static suites are now fully green:** `ticket05-06-07` went **61 assertions /
>   1 failure / exit 1 → 65 / 0 / exit 0** (commit `a72f57c`). `ticket-monitor`
>   12/12 and `ticket08-ahk` 17/17 were already green.
> - **`KomorebiWatchdog` was Disabled** on this machine (188 missed runs) and has
>   been **re-enabled**. It was then found Disabled **again** 90 minutes later,
>   which proved the cause rather than the state: all four restart scripts
>   restored the task only on the happy path. They now restore it from a
>   `finally` — commits `488b995` and `dd25680`. Trap **T11** is closed.
> - **dev and publish `tests/` are now byte-identical** (7 files). The dev Sandbox
>   suite had been **stale**, missing the whkd-pairing and elevation tests entirely.
> - **`7-YASB-RESTART.ps1` was deleted** as a genuine duplicate; its diagnosis half
>   merged into `restart-yasb.ps1 -DiagnoseOnly`.
> - **New open defect D11:** `scripts/SCRIPTS-GUIDE.md` is in **Persian** and must
>   be translated to English.
>
> The ticket-status table and the testing numbers **below are stale in places** —
> trust `handoff/` over this file where they disagree.

---

## 1. What the project is

A one-click, offline installer for the whole **Komorebi + WHKD + YASB +
AutoHotkey** stack: installs the four components from binaries committed to the
repo, generates a portable config for the target machine, sets up the startup
machinery, and ships the battle-tested management scripts — driven by a future
Dashboard and CLI.

## 2. The two directories (important)

| | Path | Contents |
|---|---|---|
| **Dev (not on GitHub)** | `~/projects/komorebi-1click` | spec, ADRs, tickets, research, cheatsheets, tests, docs |
| **Publish (GitHub)** | `/mnt/h/Repo/komorebi-1click` (= `H:\Repo\komorebi-1click`, `github.com/davoodya/komorebi-1click`) | everything the installer ships: binaries, `Install.ps1`, `scripts/`, `config/`, `autohotkey/`, `tests/` |

The dev tree is the source of truth for *thinking*; the publish tree is the
source of truth for *what runs*. Test files and docs are written in dev and
copied across. **Davood authorised bypassing the WSL `/mnt/h` guard block for
this project** (his own restriction) — but nothing under `/mnt/c` without a
fresh explicit request.

SSH push is configured: `origin` is `git@github.com:davoodya/komorebi-1click.git`
over the Kali WSL key.

## 3. Ticket status

| # | Ticket | Status |
|---|---|---|
| 01 | repo + binaries + provenance | ✅ done (942ff3e) — checkboxes now ticked |
| 02 | installer core | ✅ done (942ff3e) |
| 03 | configuration generation | ✅ done (adb050b) |
| 04 | startup tasks | ✅ done (887db72) |
| 05 | AutoHotkey integration (AppRunner.vbs) | ✅ done (92e1e90) |
| 06 | management-script portability | ✅ done (0064b36) |
| 07 | export / import ZIP | ✅ done (c0ca4d0) |
| 08 | AutoHotkey lifecycle scripts | ✅ done (5ae504f) |
| — | monitor geometry false-DEGRADED fix | ✅ done (8398fda) |
| **09** | **EXE wrapper (csc)** | **← NEXT** |
| 10–13 | Dashboard (shell, threading, theme, publish) | blocked by 10's own chain |
| 14 | verification harness (Windows Sandbox) | blocked by 09 + 13 |

All tickets live in `~/projects/komorebi-1click/.scratch/komorebi-1click-installer/issues/`.
Ticket 09's file is `09-exe-wrapper.md`.

## 4. What happened this session

### Ticket 08 — AutoHotkey lifecycle (commit 5ae504f)

Four new scripts plus four `.bat` wrappers, all path-portable and composing with
`common.ps1`:

| Script | Does |
|---|---|
| `ahk-script.ps1` | Enable or disable ONE script by name; `-List` shows the state |
| `ahk-toggle.ps1` | Flip all three to the same state at once |
| `ahk-uninstall.ps1` | Remove both AutoHotkey versions by product code |
| `ahk-cleanup.ps1` | Remove the Startup VBS, the state file, any repo-script process |

State lives in `autohotkey\ahk-state.json`, not in the VBS; the VBS is
regenerated from it. A disabled script renders as a **commented-out**
`RunHidden` line with a `[disabled:<name>]` marker, so its position is stable
across cycles. After regeneration the affected process is killed (disable) or
started (enable) immediately — no logoff required.

**Containment is critical.** Processes are matched on the `.ahk` path **under
this repo's `autohotkey\` directory** only — never on process name (every v1
script appears as `AutoHotkey`) or filename, because the user runs personal
scripts from `H:\Repo\Auto-HotKey\` that must never be touched.

### Monitor geometry fix (commit 8398fda)

`4-STATUS.bat` reported `DEGRADED (3 problem(s))` on a machine where everything
worked. Three defects in the health check, not the environment. Full write-up:
`docs/MONITOR-GEOMETRY.md`.

1. **`komorebic state` puts monitor WIDTH/HEIGHT in `right`/`bottom`, not the
   far edge.** `Get-Health` computed `right - left` and produced **-840** for
   the portrait monitor. Fixed in `komorebi-service.ps1` **and**
   `display-diag.ps1`.
2. **WinForms `Screen.Bounds` are logical, komorebi reports physical.** The 125%
   monitor reported 864x1536 where komorebi reported 1920x1080 → false
   "disagrees with Windows". `Get-WindowsMonitor` now converts using the
   **monitor's own** DPI (P/Invoke through its DC), not the system DPI.
3. **`$p++` instead of `$problems++`** in the mismatch branch, so a real
   mismatch never counted at all.

Also demoted two non-faults inflating the count: unnamed workspaces (this config
addresses workspaces **by index**, so empty names are the design) and zero-size
containers (`komorebic state` reports 0x0 for hidden/minimised windows — Sticky
Notes, Phone Link, Settings).

**Verified live:** `VERDICT: HEALTHY`, `BadMonitors=0`, `MonitorMismatch=0`,
3 monitors, 12 tiled windows, whkd paired, 119 bindings — process/socket/pairing
lines unchanged. Also verified under **Windows PowerShell 5.1** (the installer
targets the inbox shell).

### The whkd pairing postmortem (earlier this session, still binding)

> **whkd must ALWAYS be spawned by `komorebic start --whkd`.** A whkd started
> any other way is alive, parses its config, and silently drops every hotkey
> (LGUG2Z/komorebi#956). If hotkeys die: `komorebic stop --whkd`, then
> `komorebic start --whkd`. Restarting whkd alone can NEVER repair it; the
> pairing is set at komorebi start. Fixed at three levels: the fallback branch
> returns failure, `Get-Health` exposes a `WhkdPaired` probe, and
> `tests/sandbox-test-suite.ps1` `T04.1b` asserts the probe after a real
> install. Full write-up: `docs/POSTMORTEM-20261004-whkd-pairing.md`.

The elevated-window half of the same bug: an unelevated komorebi cannot manage
elevated windows (UAC integrity), so a non-elevated restart silently drops
elevated windows and the Hermes window from the layout. The reference account is
**not** an Administrator, so `-Verb RunAs` cannot elevate silently. Both
`restart-whkd.ps1` and `safe-restart.ps1` now stop the pair and hand the start
to the installer's `Komorebi` logon task, which is `RunLevel Highest`.

## 5. The reference machine (Davood's)

Three displays — **Komorebi and Windows number them differently**, and that is
expected (monitor indexing is an enumeration artefact, not a config value):

| Windows name | Native px | Scale | Position | Role |
|---|---|---|---|---|
| `\\.\DISPLAY1` (Dell P27) | 1920x1080 | 100% | (0, 0) | primary, in front |
| `\\.\DISPLAY2` (Dell P23) | 1920x1080 | 125% | (0, -1080) | portrait, **above** the primary |
| `\\.\DISPLAY3` (Samsung LS27) | 1080x1920 | 100% | (1920, -853) | portrait, right of the primary |

In `komorebic state` the order is `DISPLAY1, DISPLAY2, DISPLAY3`; in Windows
Display Settings the P23 is monitor 2 and the Samsung is monitor 3. Hotkeys that
address a monitor by **name** are the reliable ones; index-based addressing
(`focus-monitor 1`) does not address the monitor Windows calls 1.

## 6. The standing rules (Davood's, binding)

### Language

- **ALL shipped text is ENGLISH** — GUI, CLI output, comments, published docs,
  specs, tickets, tests. The source material may be Persian; the shipped
  artifact is English.
- **The final report to Davood is PERSIAN**, technical terms kept in English.
- **NEVER Chinese** — banned outright.

### Testing

- **Do not run any test on the live Windows machine** unless Davood explicitly
  asks for it. Nothing that could disturb Komorebi, WHKD, YASB or AutoHotkey is
  executed there.
- Sandbox work happens in a throwaway copy — for scripts that derive `$RepoRoot`
  from `$MyInvocation`, run the **SANDBOX COPY** and pass
  `-StartupDirOverride $sandbox`. Running the real path has deleted the live
  Startup VBS twice already.
- Sandbox/VM-requiring tests are written to the test file and **Davood runs them
  manually** after the tickets are done. Do not attempt to launch the Windows
  Sandbox yourself.
- Tests live in `~/projects/komorebi-1click/tests`; the publish copy is
  `/mnt/h/Repo/komorebi-1click/tests`.

### Bugs and fixes

- **Do not create new problems.** The system is in a perfect state; only fix the
  described problem. Verify the fix leaves everything else untouched (process
  counts, bindings, files) before committing.
- Any script change must stay **Windows PowerShell 5.1** compatible — the
  installer targets the inbox shell (a real ticket-01 bug was a PS7-only
  ternary).
- When you fix a bug, **write a document** explaining why it happened and how it
  was fixed, so the same class of bug is prevented in the installer for target
  machines.

## 7. How everything is verified

Two independent layers; nothing is verified by eye.

**Layer 1 — static, on the dev machine (no Sandbox):**
- `tests/ticket05-06-07.tests.ps1` — **65 assertions, 0 failures, exit 0**
  (was 61/1/exit 1 — the stale assertion was fixed in commit `a72f57c`)
- `tests/ticket08-ahk.tests.ps1` — 17 assertions, exit 0, sandbox copy
- `tests/ticket-monitor.tests.ps1` — 12 assertions, exit 0
- PS parse sweep — **31 shipped `.ps1`**, 0 failures under **both** PS 5.1 and PS 7

**Layer 2 — the Sandbox suite (real install on a clean machine):**
`tests/sandbox-test-suite.ps1`, including `T03f.1–T03f.2` (the repaired whkdrc
bindings), `T04.1b/c/e` (whkd pairing, elevation, restart path) and
`T07.1–T07.3` (a real export→import round trip). **Davood runs this manually.**

**Not yet done:** a full `Install.ps1` run inside `sandbox.wsb`. That is the
outstanding verification step for tickets 02–08 and needs no decisions, only
launching the Sandbox.

## 8. Real bugs found in earlier sessions (still worth knowing)

1. `New-Whkdrc` rewrote nothing — double-escaped regex. Now `[regex]::Escape()`d.
2. PS5.1 ternary in `Assert-ArchitectureSupported` — now `if/else`.
3. `CreateEntryFromFile` is an extension method — must go through
   `[ZipFileExtensions]::…`.
4. `komorebi.json` restored to the wrong directory (it lives in
   `%USERPROFILE%`, not `.config`).
5. `safe-restart.ps1` could not find `komorebi-service.ps1` after being copied
   to `.config` — now reads the repo path from `safe-restart.repo.txt`.

## 9. Where to start next

0. **Read `handoff/` first** — especially `komorebi-1click-knowledges.md`. It lists
   the traps (whkd pairing, monitor geometry, the watchdog-freeze pattern, PATH
   capture, elevation) that this document only summarises.
1. **Ticket 09** — the EXE wrapper. Read
   `~/projects/komorebi-1click/.scratch/komorebi-1click-installer/issues/09-exe-wrapper.md`.
   A thin single-file C# EXE built with `csc.exe` (.NET Framework) that locates
   `Install.ps1` next to itself, relaunches itself elevated via
   `Process.Start(..., "runas")`, runs
   `pwsh -NoProfile -ExecutionPolicy Bypass -File Install.ps1` and forwards the
   exit code. All logic stays in `Install.ps1`; the wrapper is thin. It unblocks
   ticket 14 (the Sandbox verification harness).
2. **A Sandbox run** of the full suite would clear the "awaits a Sandbox run"
   column for tickets 02–08 in one shot — but that is Davood's manual step.

## 10. Suggested skills

Call these with `skill_view` before starting:

- `ticket-implementation` — implementing sequential project tickets end to end
- `systematic-debugging` — 4-phase root cause debugging; use before any fix
- `verification-levels` — the 5-level evidence system; apply the highest level
  the change admits
- `hermes-agent` — if anything about the Hermes runtime itself is unclear
- `obsidian` (note-taking) — if a decision needs to outlive the session in the
  vault rather than the repo

---

## Session 2 — Tickets 09 + 10, recovery, and the two open questions

### RECOVERY FIRST

A parallel session had run `git reset --hard` back to `origin/main`, discarding
**seven** commits (`a72f57c`, `488b995`, `dd25680`, `69c6c2c`, `8618dd7`,
`e979919`, `c124d59`) — the whole audit-remediation record. The tree looked
clean and every test passed, so nothing on screen revealed it.

Restored with `git reset --hard c124d59`. That SHA still contains the other
session's own commits, so nothing of theirs was lost. Re-verified: 4 suites
green, D4 `try/finally` present in all four restart scripts,
`7-YASB-RESTART.ps1` still deleted, watchdog `Ready`. Dev ↔ publish `tests/`
then drifted by CRLF only and was re-synced.

**If work of yours is ever missing from a shared repo with a clean tree: check
`git reflog` first.**

### Tickets implemented

| Ticket | Commit | State |
|---|---|---|
| 09 — EXE install wrapper | `f5363e6` | done, 26/26 |
| 10 — Admin Dashboard shell | `7b9a045` | done, 123/123 |
| — `-DiagnoseOnly` × 5 scripts | `1106bfa` | done |
| — `SCRIPTS-GUIDE.md` English | `afc365b` | done (D11 closed) |

Artifacts:
- Installer EXE source: `scripts/komorebi-install.cs`, built by
  `scripts/build-exe.ps1`. The EXE is gitignored — build it where `csc.exe` is.
- Dashboard EXE: `src/KomorebiDashboard/bin/Release/net8.0-windows/KomorebiDashboard.exe`
  (151 KB, `dotnet build` only, no Visual Studio needed).

### Bugs found and fixed during implementation

- **D12 HIGH** — the `git reset` above.
- **D15 HIGH** — six dashboard verbs pointed at `.ps1` files that were never
  written; every Kill/Start button would have done nothing.
- **D13/D14 MEDIUM** — `safe-restart.ps1` has no `$RepoRoot`; the guide
  documented a backup path ticket 06 had already retired.
- **D16 MEDIUM** — a `WinExe` CLI twin produced no output (an `AttachConsole`
  "fix" made it worse) then hung on a blocking `OnStartup`.
- **D17 MEDIUM** — three assertions in my own tests asserted the wrong
  invariant; each is documented in `bugs-issues.md`.

### Deliberately NOT done — belongs to ticket 14 (Windows Sandbox)

- Running the installer EXE for real (it would install over the live stack).
- Opening the WPF window (needs an interactive desktop).
- Clicking GUI buttons — though a click takes the same code path the CLI was
  proven to take end to end.

### Environment note

`delegation.model` is set to `auto` in the Hermes config, which is not a valid
model on the Nous provider; subagent dispatch fails immediately with HTTP 404
and the per-task override is ignored. Ticket 10 was done directly instead of
being delegated. Worth fixing separately.

**Live stack after everything:** `komorebi=25136 whkd=38808 yasb=47100
ahk=30420,35436`, watchdog `Ready`, `LastTaskResult=0x0`. Untouched throughout.

---

## Ticket 11 — no-lag execution (2026-10-05, `da42d3a`)

`ScriptService` now attaches its output handlers and sets `EnableRaisingEvents` **before**
`Process.Start`, uses no `Task.Run`, carries a per-run `CancellationTokenSource`, kills
the **whole tree** on cancel (`Kill(entireProcessTree: true)`), enforces a 300 s default
budget, and distinguishes timeout from user-cancel. `TabViewModelBase` buffers streamed
output and flushes it with **one** `BeginInvoke` per ~50 ms window instead of one per
line. `ScriptResult` carries `StandardError` / `Cancelled` / `TimedOut`.

**D18 — the GUI had never been launched.** `MainWindow.xaml` set no `x:Name` on any of
the six views; `FindName` therefore returned null for all six and the constructor threw
`NullReferenceException` at startup. The null-forgiving operator hid it and ticket 10's
123 static assertions could not see it, because none of them started the app. Now fixed,
and `tests/ticket11-threading.tests.ps1` (67 assertions) launches the EXE and requires a
non-zero window handle.

**Spec correction, recorded not papered over.** The ticket's "async reads started before
`Process.Start`" is impossible — `BeginOutputReadLine()` before `Start()` throws
`InvalidOperationException: StandardOut has not been redirected or the process hasn't
started yet`. The suite asserts the achievable contract and documents the probe output.

**Verified:** 67/67 × 4 consecutive runs · build 0/0 · startup 553 ms · timeout kills a
100,000-line script at 3.1 s leaving no orphan · 65+12+17+26+123 still pass · live
komorebi/whkd/yasb PIDs and both scheduled tasks unchanged throughout.
