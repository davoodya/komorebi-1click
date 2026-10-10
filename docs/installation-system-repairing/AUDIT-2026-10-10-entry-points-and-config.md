# Audit — komorebi-1click installation system (entry points + config generation)

**Date:** 2026-10-10
**Auditor:** Hermes (Daya) for Davood Yahay (DavoodSec)
**Machine:** DAVOIDPC — Windows 11 26H2 (build 26300), Kali WSL2 via `/init` interop
**Scope:** `Install.ps1`, `komorebi-1click-install.exe` (source `scripts/komorebi-install.cs`),
library `scripts/Install-Common.ps1`, payload manifest, config templates, the
`docs/Access-Denied-Solving/` patch machinery, and the test coverage around all of it.

---

## 1. Method (and the live-machine rule)

**Live-machine rule (user mandate, 2026-10-10):** the live Komorebi/WHKD/YASB/
AutoHotkey stack on this machine is in a known-good state and must not be
disturbed. Nothing in this audit installed, ran, reconfigured or restarted any
component. Every check was one of:

- read-only probes (file hashes, registry ARP reads, task state, process list);
- **offline** configuration validation (`komorebic check`) against **copies** of
  configs in `%TEMP%`;
- parse checks of every shipped `.ps1` (no execution);
- isolated wrapper experiments: two **test-only** builds of the C# wrapper
  (elevation forced, stub `Install.ps1`) executed from `%TEMP%`.

Anything that would touch the live stack belongs to the implementation phase and
must run in **Windows Sandbox** (the harness at `sandbox.wsb` /
`tests/start-sandbox.ps1`) or as a `-DryRun`.

**Second-method rule:** every load-bearing claim was verified by a method
different from the one that first suggested it. That rule earned its keep here
(see §5, H5: a first-method result that looked like a komorebic defect was
actually a harness artifact).

---

## 2. Architecture as built (what the audit confirmed)

One installer, three documented entry points, one library:

```
komorebi-1click-install.exe   (GUI wrapper; scripts/komorebi-install.cs, ADR-0004)
        \  elevates via runas when needed, then launches:
Install.ps1                   (the only file with installer logic)
        |  dot-sources
scripts/Install-Common.ps1    (payload verify, MSI/AHK install, config generation,
        |                     startup tasks, AppRunner.vbs)
irm <url>/install.ps1 | iex    (bootstrap branch: fetches the repo zip, re-execs Install.ps1)
```

Stages in `Install.ps1`: architecture check → elevation check → payload SHA256
verification (6 payloads) → PRIMARY steps (Komorebi, WHKD — abort on failure) →
SECONDARY steps (YASB, AHK v1, AHK v2 — continue on failure, exit 10 at the end)
→ `Install-Configuration` (exit 2 on failure) → `Install-StartupTasks`
(exit 3) → `Install-AutoHotkeyStartup` (exit 4) → footer (exit 0).

Verified inventory (all green today, must not regress):

| Check | Result |
|---|---|
| Payload hashes vs `binaries/payloads.sha256.json` | 6/6 match (sha256sum, independent of PowerShell) |
| All 45 shipped `.ps1` parse clean | OK (PowerShell 7 parser sweep) |
| Exec policy on host | `RemoteSigned` (CurrentUser + LocalMachine) — not a blocker |
| Zone.Identifier on repo files | none marked |
| Live stack | komorebi, whkd, yasb, 2× AutoHotkey v1, AutoHotkey64 v2 all running |
| Installed `komorebi.exe` | byte-identical to `docs/Access-Denied-Solving/Komorebi-Patched/komorebi.exe` (SHA256 `52b631cd…`) — the patch is live on this machine but **the installer does not deploy it** |
| Scheduled tasks | `Komorebi`, `KomorebiWatchdog` both `Ready` |
| Prior end-to-end proof | `test-results/install.log` — full run, all stages, 2026-10-05; `test-results/verification-result.json` — Sandbox P2-install exit 0, 2026-10-05 |

---

## 3. Verified findings

### F1 — CRITICAL (proven): the EXE can never launch the installer. It has never once run it.

`scripts/komorebi-install.cs` `RunInstaller` builds this argument string:

```
-NoProfile -ExecutionPolicy Bypass -SkipElevationCheck -File "<installer>"
```

`-SkipElevationCheck` is a parameter of **Install.ps1**, but it sits **before**
`-File`, so `powershell.exe` / `pwsh.exe` parse it as **their own** parameter
and die before the script file is ever opened.

**Evidence (real executions):**

| Invocation | Result |
|---|---|
| `powershell.exe … -SkipElevationCheck -File test.ps1` | `The term '-SkipElevationCheck' is not recognized…` — **exit 1**, child script never ran |
| `pwsh.exe … -SkipElevationCheck -File test.ps1` | `The argument '-SkipElevationCheck' is not recognized as the name of a script file` + usage dump — **exit 64**, child never ran |
| same, switch **after** `-File` (control) | child ran, `SkipElevationCheck=True` bound — exit 0 |

The shipped binary contains exactly this string (UTF-16 string heap:
`-NoProfile -ExecutionPolicy Bypass -SkipElevationCheck -File `), so the
published EXE is built from the current buggy source.

**Why the user sees nothing at all:** the wrapper is a GUI-subsystem process
with no console, starts the shell with `UseShellExecute = false` and **no
output redirection**. The child's fatal error goes nowhere a double-clicking
user can see; the wrapper only forwards the child's exit code. That is precisely
the reported symptom «با اجرای فایل EXE هم هیچ خروجی مشاهده نمیشود».

**End-to-end reproduction (test-only build, elevation forced, stub installer):**

```
=== orig (as shipped logic): wrapper exit 64; stub ran: False
=== fixed (switch after -File): wrapper exit 0; stub ran: True
    ran 2026-10-10T16:56:30+03:30 SkipElevationCheck=True args=[]
```

**Fix (verified):** move the switch after the script path —
`-NoProfile -ExecutionPolicy Bypass -File "<installer>" -SkipElevationCheck
[extra args]`. On this machine the wrapper selects `pwsh.exe` (PowerShell 7 is
installed), so the observable exit code is 64, not 1.

### F2 — CRITICAL (diagnosed): no working one-click path remains; the .ps1 path stops at its own elevation gate

`Install.ps1` itself is healthy — but every **direct** user launch on this
machine dies at `Assert-RunningElevated`, because the account is not an
Administrator. Verified by dot-sourcing the library and running the real
assert (read-only):

```
INSTALL STOPPED
  Failing step: Elevation check
  Cause:        This installer is not running with administrator privileges, but the MSIs install into C:\Program Files.
  How to fix:   Relaunch as administrator: right-click Install.ps1 (or Install.exe) and choose "Run as administrator", …
[caught] Installer is not elevated        → script exits 1, nothing installed
```

When launched from Explorer ("Run with PowerShell" / double-click), that report
prints into a window that closes immediately — the user experiences exactly
«عملیات نصب اصلا انجام نمیشود و پیش نمیرود». With F1 killing the EXE (the only
path that used to elevate for the user), **there is currently no working
one-click entry point at all**.

### F3 — HIGH (proven latent bug): the config generator writes a path it does not populate

`New-KomorebiConfig` sets

```
app_specific_configuration_path = C:\Users\<user>\applications.json
```

while `New-ApplicationsJson` copies the file to

```
C:\Users\<user>\.config\komorebi\applications.json
```

The shipped template `config/komorebi.json` already carries the **correct**
value (`%USERPROFILE%\.config\komorebi\applications.json`); the generator line
(introduced in ticket 03, commit `adb050b`, never touched since — it was the
"fix" for handoff bug #4) overwrites it and drifted from the template.

**The install-time validator does not catch it.** `komorebic check` was run
against both variants (offline, against temp copies):

```
=== variant gen-path (C:\Users\DavoodYa\applications.json — file does NOT exist) -> exit 0
=== variant tpl-path (%USERPROFILE%\.config\komorebi\applications.json — exists)   -> exit 0
```

Both exit 0. So on a fresh machine the installer would: write the wrong path →
copy the file somewhere else → pass validation → declare success → and komorebi
then dies at `asc.rs:40` on first start (the **exact 2026-10-10 incident class,
recreated by the installer itself**). The live machine escaped only because its
config was hand-restored from the template on 2026-10-10.

**Fix:** drop the `app_specific_configuration_path` rewrite in
`New-KomorebiConfig` (keep the template's `%USERPROFILE%`-form value; komorebi
expands `%USERPROFILE%` itself), and make `Test-GeneratedConfig` verify the
referenced file exists — or add an explicit pre-flight check.

### F4 — HIGH: no test ever executes the EXE wrapper — the gap that shipped F1

- `tests/ticket09-exe-wrapper.tests.ps1` only **greps** the C# source
  (`$src -match '-SkipElevationCheck'` passes no matter where the switch sits)
  and compiles it. It never runs the built binary.
- The Sandbox suite runs `Install.ps1` directly
  (`tests/sandbox-test-suite.ps1:104`) and never the EXE.
- `tests/sandbox-verify-install.ps1` likewise only drives `Install.ps1`.

This is the D17 class exactly ("assert the behaviour, not the shape of the
code"). The ticket-09 suite needs a live execution assertion: build the wrapper,
place it beside a **stub** installer, run it, and require that the stub ran and
received the switch (the technique used for F1's proof above).

### F5 — MEDIUM: the `irm | iex` entry point is dead until a release is published

The bootstrap downloads
`https://github.com/davoodya/komorebi-1click/releases/latest/download/komorebi-1click.zip`
→ **HTTP 404** (no release published yet; the repo itself is public and
returns 200). Entry point 3 therefore fails for every anonymous user until a
release with that asset exists. Also note the bootstrap still applies the
elevation gate after re-exec.

### F6 — MEDIUM: the patch machinery is untracked, machine-specific, and unused by the installer

- `docs/Access-Denied-Solving/` (patched `komorebi.exe`, `.orig`, the fixing
  script, `patch_final2.py`) is **untracked in git** (`git ls-files` → empty;
  status shows `?? docs/Access-Denied-Solving/`). An installer that depends on
  it cannot ship until the files are committed.
- `Access-Denied-0x80070005-fixing.ps1` hard-codes machine paths
  (`H:\Repo\komorebi-1click\config\applications.json`, the service script, the
  backup dir) — fine as a one-off repair on this box, not reusable as an
  installer step.
- The patched binary is 14.6 MB and currently lives under `docs/`. A
  ship-safe design must pin its SHA256 (verified value:
  `52b631cdcc5e5495342542740a52f57594b9b540e24e2888bd23f1d41b7e3abb`) in the
  payload manifest and deploy it from the repo path (or a dedicated payload
  directory), with backup + post-deploy hash verification.

---

## 4. Requirements for the new installer version

1. **R1 — EXE argument order fixed** (F1): the wrapper must launch
   `pwsh/powershell -NoProfile -ExecutionPolicy Bypass -File <installer>
   -SkipElevationCheck [args]`. Rebuild via `scripts/build-exe.ps1`; the
   rebuild must be verified by *executing* it (stub-installer technique).
2. **R2 — one working entry point**: after R1 the EXE is the one-click path
   (elevates via UAC runas for non-admins; forwards exit codes verbatim). The
   elevation report for direct `Install.ps1` runs stays (it is correct
   behaviour) — the double-click path is what changes.
3. **R3 — deploy the patched komorebi after the MSI step** (user's new
   requirement): verify the patched binary's SHA256, back up the installed
   `komorebi.exe`, copy the patched binary over it, then verify the deployed
   file's hash. Reference the binary at its repo path; commit the patch
   artifacts (F6). Idempotent: skip when the installed binary already matches
   the pinned hash.
4. **R4 — fix the ASC path bug** (F3) and add the missing-file check to
   config validation.
5. **R5 — gate 2 hardening (cheap)**: remove/rename any
   `komorebi.exe.manifest` beside the installed binary (the MSI does not ship
   one; the rename is idempotent). Gate 1/3 arrive via R3's binary; gate 4 via
   the installer's own `applications.json` step + R4.
6. **R6 — entry-point tests that execute**: extend the ticket-09 suite with a
   live wrapper execution stub test, and add the EXE path to the Sandbox suite
   so a future wrapper regression can never ship again.
7. **R7 — release plumbing** (F5): publish a GitHub release containing
   `komorebi-1click.zip` so the `irm | iex` path works, or document the path as
   unavailable until then.
8. **R8 — everything above verifies in Sandbox or DryRun only** (user mandate):
   no install/config run against the live machine at any point.

---

## 5. Eliminated hypotheses (recorded so they are not re-chased)

| # | Hypothesis | How it was eliminated |
|---|---|---|
| H1 | PowerShell syntax error stops the script at dot-sourcing | Parser sweep of all 45 shipped `.ps1`: zero errors (PS 7) |
| H2 | Payload hash mismatch aborts verification | Independent `sha256sum` of all 6 payloads: 6/6 match the manifest |
| H3 | Execution policy blocks the `.ps1` | Host policy is `RemoteSigned`; no `Zone.Identifier` on any repo file |
| H4 | The shipped EXE is stale vs its source | The shipped binary contains the exact buggy argument string — it is built from the current source |
| H5 | `komorebic check -k` is broken in komorebi 0.1.41 (would break install validation) | **First-method artifact.** Bare `/init exe arg arg` interop mangles multi-argument Windows binaries (clap saw shifted argv). Re-run via `powershell.exe` + `Start-Process` with a proper `ArgumentList`: `check -k` exits 0 with the expected report. **Method note for all future harness work: never invoke a multi-arg Windows binary through bare `/init` — always through `Start-Process`/`-Command` so argv is assembled by Windows itself.** |
| H6 | The script hangs before the first step | No hang observed in any read-only exercise; the body is proven end-to-end by the 2026-10-05 Sandbox run (install exit 0) and the host log (all stages completed) |

---

## 6. Risk register for the implementation phase

- **Elevated relaunch on a non-admin account:** DavoodYa is not an
  Administrator, so `runas` shows a credential prompt; that path cannot be
  exercised without Davood's consent (or inside Sandbox, where the account is
  admin). Keep the `ExitElevateRefused = 5` behaviour and its message.
- **Patching `komorebi.exe` in `C:\Program Files`:** requires admin and must
  stop the processes first; on the live machine this is **forbidden** — the
  patch step is a fresh-install step and is verified in Sandbox only.
- **Post-patch verification:** compare deployed hash against
  `52b631cd…`; additionally assert the two 6-byte patch sites are present
  (offsets `0x2898E9`, `0x28D7E4`, bytes `B8 01 00 00 00 90`) so a future
  komorebi version cannot be silently mis-patched.
- **The `.gitignore` ignores `komorebi-1click-install.exe` by design** — the
  EXE ships as a build artifact of `scripts/build-exe.ps1`, not as a commit.
