# Handoff — komorebi-1click installer repair (implementation phase)

**Last updated:** 2026-10-10 (end of implementation session 2)
**Repo:** `H:\Repo\komorebi-1click` (publish copy; source of truth) · dev copy `~/projects/komorebi-1click` (handoff docs only — its `src/` does NOT build)
**Phase:** implementation — code fixes complete and **host-verified**; the **manual end-to-end test (Test B in `final-report.md`) is the next action**
**For the next agent:** read this file top to bottom before touching anything. It is written so you can continue without the previous conversation. `final-report.md` is the build/verify/debug companion — read both.

---

## 0. THE RULE (non-negotiable, from the project owner)

> **NEVER run the install/config-transfer scripts or the installer EXE on the live Windows machine.** Komorebi, WHKD, YASB and AutoHotkey are installed there and in their best state. Any action that would disturb the live stack or modify the live configs is forbidden — **Sandbox or `-DryRun` only**. Owner decision 2026-10-10 (restated): *no real test on this machine at all*; the owner runs the tests manually.

Everything here obeys it: host-side work was parse checks, read-only probes/hashes, `%TEMP%` copies, redirected-config-home runs, `-DryRun`, and a stub-based wrapper execution test.

What is SAFE on the host:
- `-DryRun` runs of the real installer **with `KOMOREBI_CONFIG_HOME` redirected** (the flag is now genuinely inert — verified, see §2.3)
- `komorebic check -k <temp config>` (read-only parser; never point it at the live config, never start/stop the WM)
- compile + execute the wrapper EXE **beside a stub `Install.ps1` in `%TEMP%`** (ticket 09 does this)
- `Get-FileHash`, `git`, parse checks, writes under `%TEMP%`, reads of the repo
- tests that only parse/read/execute stubs (`ticket05-06-07`, `ticket08-ahk`, `ticket09`)

What is FORBIDDEN on the host:
- a real install run of `Install.ps1` / `komorebi-1click-install.exe` (writes Program Files, configs, tasks)
- `komorebic stop/start`, `komorebic restart`, killing komorebi/whkd, touching `.config\komorebi`
- running `tests/sandbox-verify-install.ps1` / `sandbox-test-suite.ps1` (they install)

---

## 1. Decisions already made by the owner (do not re-ask)

1. The pre-patched komorebi.exe **is committed** (`2616c89`).
2. The installer deploys the **pre-patched binary directly** (copy + SHA256 verify). The fixing script stays a standalone repair tool; the installer does not run it.
3. UAC credential prompt for a non-admin double-click: **acceptable**.
4. GitHub release for `irm | iex`: only after the installer passes end-to-end verification.
5. Non-elevated UX: the installer **self-elevates** via UAC (both EXE and `Install.ps1`).
6. **Configs must never change on the owner's machine**, and the deployed set must transfer **exactly** to the target machine (see §6.1 — one drift found).
7. Testing is **manual by the owner**; the agent's job is to state method + expected output (Test A/B/C in `final-report.md`).

Old deliverables were renamed by the owner: `komorebi-1click-install-old.exe`, `Install-old.ps1`.

---

## 2. What is fixed, with evidence

### 2.1 BUG 1 — the EXE never ran the installer (root cause of "EXE shows nothing")
`scripts/komorebi-install.cs` built `… -Bypass -SkipElevationCheck -File …`, so the switch sat **before** `-File`. PowerShell's parser owns everything before `-File` → exit **64** (pwsh 7) / **1** (5.1) before the installer ran; a GUI binary shows nothing.
Fix: switch after the installer path + stderr capture + logging. Evidence: fresh stub run exit 0 with `bound=[SkipElevationCheck]`; production EXE literal order verified with `strings -el`.

### 2.2 BUG 2 — direct `.\Install.ps1` died silently at the elevation gate
`Assert-RunningElevated` threw for a non-admin (this account is not an Administrator) and the console closed.
Fix: `Invoke-InstallerElevation` — self-elevate via `Start-Process -Verb runas`, forward the child's exit code, loop-guarded by the `KOMOREBI_1CLICK_ELEVATED_LAUNCH` marker. `-SkipElevationCheck` bypasses.

### 2.3 `-DryRun` was inert (fixed this session, commit `93cd9f8`) — read the lesson
The library executed `$script:DryRun = $false` at dot-source time. `Install.ps1`'s `-DryRun` **switch parameter lives in the same script scope**, so the library silently reset it: parameter bound (`DryRun=True`) yet banner missing, header in real mode, **and the writes ran** — a misconfigured probe regenerated machine paths into three live config files before it was caught (detected and reported; live state proven intact and matching a fresh generation, §6).
Fixes (all in the commit): flag initialises only when absent; `Install.ps1` captures `$script:DryRunRequested` **before** the dot-source; `New-AppRunnerVbs` now writes through the guarded path (it used `[System.IO.File]::WriteAllText`, bypassing every guard — could rewrite the Start Menu `AppRunner.vbs` in dry mode); `Remove-LegacyStartupShortcut` wrapped in `Invoke-InstallerAction`; all post-action verifications that read back a never-written file now report intent instead of throwing (komorebic check, resize state, patch hash, MSI detection, AHK interpreter, task runlevel); step status lines now print the honest `would …` form.
Verification: isolated lab run (`%TEMP%` copy + redirected empty config home + `-DryRun -SkipElevationCheck`) → **exit 0, stderr 0 bytes, banner + `[DRY-RUN] would …` everywhere, 0 bytes written to the redirected home, 27/27 live-state keys byte-identical before/after** (Startup files + hashes, Machine PATH, HKCU Run, the three tasks).

### 2.4 Project findings F1–F6 (earlier sessions, evidence in the audit doc)
F1 wrapper arg order (§2.1) · F2 elevation gate (§2.2) · F3 ASC path drift (generator keeps the portable path + installer validates it) · F4 no test executed the wrapper (ticket 09 now compiles **and executes** stubs) · F6 patch installed by the installer (`Install-KoreiPatch`, hash-pinned, `.orig` backup, graceful stop/restart).

---

## 3. Current repository state (verified, not remembered)

| Item | State |
|---|---|
| `Install.ps1` | rewritten: self-elevation, patch step, `-DryRun`, arg forwarding — commit `93cd9f8` |
| `scripts\Install-Common.ps1` | ASC fix + dry-run guards + `Install-KoreiPatch` + elevation + `Write-StepOutcome` — `93cd9f8` |
| `scripts\komorebi-install.cs` | fixed order + stderr + `/define:K1C_TEST_FORCE_ELEVATED` test hook |
| `komorebi-1click-install.exe` | rebuilt from fixed source, 9,728 B, GUI subsystem, sha256 `fa1dae08…` |
| `binaries\payloads.sha256.json` / `.txt` | patched binary pinned (7 entries) |
| `docs\Access-Denied-Solving\**` | committed (`2616c89`) |
| `tests\ticket09-exe-wrapper.tests.ps1` | execution-based — **all checks green** |
| `tests\ticket08-ahk.tests.ps1` | **26/26 green** · `ticket05-06-07` exit 0 |
| `Install.ps1` + library | parse clean under 5.1 **and** 7 |

Host verification already run (all safe): the lab dry run (§2.3), the three suites,
parse checks, the wrapper build, and a **config-fidelity comparison** — fresh
generation vs live: `whkdrc`, `restart-whkd.cmd`, `toggle-transparency.ps1`,
`safe-restart.ps1`, yasb files **BYTE-IDENTICAL**; `komorebi.json` semantically
identical (ASC path is per-machine by design); `applications.json` differs by one
live rule (§6.1).

**NOT yet verified:** the full install end-to-end (Test B) — manual, owner-run, on a
fresh machine or Sandbox.

---

## 4. Next steps, in order

1. Owner runs **Test A** (`komorebi-1click-install.exe -DryRun`) — the safe pre-flight.
   Expected output is written out line-shape-by-line-shape in `final-report.md` §5.
2. Owner runs **Test B** on a fresh machine / Sandbox: full install, then a second run
   for idempotency (every step must report `already …`).
3. Resolve §6.1 (the `applications.json` rule drift) before any target deployment.
4. Only then consider the GitHub release for `irm | iex` (owner decision #4).
5. Optional hardening ideas for later: run the payload-integrity gate before state
   detection (already the order), add `-WhatIf` parity tests for the remaining
   registry/PATH helpers.

Windows Sandbox is **not usable on this host** (§6.2) — it crashed on launch and the
account is non-admin; do not spend a session retrying it here.

---

## 5. Traps that cost time here (read before editing)

1. **A dot-sourced library owns the caller's scope.** Never unconditionally assign
   `$script:<Name>` at library top level when a caller may hold `<Name>` as a
   parameter — that is exactly how `-DryRun` stayed inert. Initialise only when absent.
2. **Never use the fuzzy `patch` tool with a hand-typed identifier** on this codebase —
   it silently rewrote `KorebiBin`→`KoreiBin`-style drifts before. Edit PowerShell with
   exact-match replacement in Python (assert the match count), then parse-check under
   5.1 **and** 7. Extract function/identifier names from the source (`re.findall`),
   never from memory — several near-identical spellings of the product name exist and
   a mistyped name costs a full debugging cycle (three cases this session: the function
   name, the resize function, and the monitor status line).
3. **`$home` is a read-only automatic variable** in PowerShell — a script assignment to
   it does not abort (with `$ErrorActionPreference='Continue'`) and silently leaves the
   user-profile path in place. Never name a local `$home`.
4. **`/init` may load the user's PowerShell profile even with `-NoProfile`**, and the
   profile can dump huge directory listings on error. Direct invocation works:
   `'/mnt/c/Program Files/PowerShell/7/pwsh.exe' -NoProfile …` after
   `export ALLOW_WINDOWS=1` — prefer it.
5. **`/init` mangles Windows binary arguments with spaces**; `-File <path>` works when
   the path has no spaces.
6. **WSL grep/search can serve stale content on `/mnt`** (9p cache) — when a grep
   contradicts a read, trust the PowerShell-side read, then re-verify with another tool.
7. `komorebic check` **cannot** see a missing ASC file (exit 0 with a non-existent
   `app_specific_configuration_path`) — that is why the installer has its own guard.
8. Post-action "verify the result" blocks are the usual dry-run landmine: they read back
   a file the dry run never wrote and throw. Every new one must ask "does this hold in
   dry mode?" before you trust it.

---

## 6. Open questions / decisions for the owner (answer in the next prompt)

1. **`applications.json` drift:** the live file carries an `ignore` rule
   (`explorer.exe` / `CabinetWClass` / `"Network Connections"`, ~17 lines) that the
   repo template lacks. Copy live → repo template (so the target gets your exact
   config), or keep the repo template canonical?
2. **Commit `4d670dd`** (ticket 08 auto-fix series) — keep as history, or revert it in
   favour of the current state? It is already superseded by `93cd9f8` behaviour-wise.
3. **Repo hygiene:** `docs/Access-Denied-Solving/__pycache__/*.pyc` is committed;
   `config\last-backup\*` deletions and `backup\`, `config\backup-*`,
   `scripts\step5\`, `autohotkey\ahk-state.json`, `scripts\safe-restart-*.ps1` are
   uncommitted local artifacts. Remove / keep / gitignore?
4. Windows Sandbox on this host is broken (see `final-report.md` §6.2) — provide a
   sandbox/VM host for Test B, or run Test B on a spare machine?

## 7. Doc map for this workstream

- `README.md` — index of this directory
- `AUDIT-2026-10-10-entry-points-and-config.md` — the full audit (findings F1–F6, rejected hypotheses)
- `final-report.md` — **build/verification/debug guide** (deliverables, architecture, dry-run subsystem, manual tests A/B/C with expected output, known issues)
- `handoff.md` — **this file, the always-current continuation doc**
- `HANDOFF-2026-10-10.md`, `IMPLEMENTATION-2026-10-10.md` — audit/implementation logs of the earlier sessions
