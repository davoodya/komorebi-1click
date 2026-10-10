# Handoff — komorebi-1click installer repair (implementation phase)

**Last updated:** 2026-10-10 (end of implementation session 1)
**Repo:** `H:\Repo\komorebi-1click` (publish copy; source of truth) · dev copy: `~/projects/komorebi-1click` (handoff docs only — its `src/` does NOT build)
**Phase:** implementation — code fixes complete and host-verified; **Windows Sandbox end-to-end verification is the next action**
**For the next agent:** read this file top to bottom before touching anything. It is written so you can continue without the previous conversation.

---

## 0. THE RULE (non-negotiable, from the project owner)

> **NEVER run the install/config-transfer scripts or the installer EXE on the live Windows machine.** Komorebi, WHKD, YASB and AutoHotkey are installed there and in their best state. Any action that would disturb the live stack or modify the live configs is forbidden — use **Windows Sandbox or dry-run only**. This holds for every future session.

Everything done so far obeys it: host-side work was parse checks, read-only probes, temp-dir tests, hash reads, and a stub-based wrapper execution test. The only machine-wide reads were `Get-FileHash` / `Test-Path` / `komorebic check` against **temp** configs.

What is SAFE on the host:
- `komorebic check -k <temp config>` (read-only parser; never point it at the live config and never start/stop the WM)
- compile + execute the wrapper EXE **next to a stub Install.ps1 in %TEMP%** (ticket 09 does this)
- `Get-FileHash`, `git`, parse checks (`[Parser]::ParseFile`), writes under `%TEMP%`, reads of the repo
- tests that only touch `%TEMP%` (func-verify style)

What is FORBIDDEN on the host:
- running `Install.ps1` / `komorebi-1click-install.exe` (they write Program Files, configs, tasks)
- `komorebic stop/start`, `komorebic restart`, killing/stopping komorebi/whkd, touching `.config\komorebi`
- running `tests/sandbox-verify-install.ps1` or `tests/sandbox-test-suite.ps1` (they install)

---

## 1. Decisions already made by the owner (do not re-ask)

1. The pre-patched komorebi.exe **is committed** to the repo (done: commit `2616c89`).
2. The installer deploys the **pre-patched binary directly** (copy + SHA256 verification). The fixing script stays as a standalone repair tool; it is not executed by the installer.
3. UAC credential prompt for a non-admin double-click: **acceptable** (the EXE wrapper already elevates).
4. GitHub release for `irm | iex` bootstrap: **only after** the installer is complete and passes Sandbox verification. Not done yet.
5. Non-elevated UX: the installer **self-elevates** through the UAC prompt (both the EXE wrapper — already did — and `Install.ps1` — new).

Old deliverables were renamed by the owner: `komorebi-1click-install-old.exe`, `Install-old.ps1`. New deliverables: `Install.ps1` (rewritten) and `komorebi-1click-install.exe` (rebuilt by `scripts/build-exe.ps1`).

---

## 2. The two bugs that were fixed (with evidence)

### BUG 1 — the EXE never ran the installer (CRITICAL, root cause of "EXE shows nothing")

`scripts/komorebi-install.cs` built the argument string as
`-NoProfile -ExecutionPolicy Bypass <InstallerSwitch> -File "<installer>" ...`, so
`-SkipElevationCheck` sat **before** `-File`. PowerShell's own argument parser
owns everything before `-File`, so the host rejected the switch and exited **before**
the installer ran: exit **64** (pwsh 7) / exit **1** (5.1). Because the wrapper is a
GUI binary with no console, the error was invisible → "no output at all".

Fix: the switch now comes after the installer path:
`"-NoProfile -ExecutionPolicy Bypass -File " + quotedInstaller + " " + InstallerSwitch + " " + BuildArgs(args)`
plus stderr capture + logging so a host-level launch failure can never be silent again.

Evidence (host, safe):
- fresh E2E stub run: test EXE exit **0**, stub ran, `bound=[SkipElevationCheck]`
- production EXE now contains the new literal order (`strings -el`)
- old literal `-Bypass -SkipElevationCheck` absent

### BUG 2 — a direct `.\Install.ps1` died at the elevation gate with no visible result

`Assert-RunningElevated` threw immediately for non-admin, and the console window
closed right after → "installation does not happen and does not proceed".
The account (`DavoodYa`) is **not** an Administrator.

Fix: `Invoke-InstallerElevation` (scripts/Install-Common.ps1): when not elevated, it
relaunches itself via `Start-Process -Verb runas`, waits, and **forwards the child's
exit code**. Loop-guarded by the `KOMOREBI_1CLICK_ELEVATED_LAUNCH` env marker
(second non-elevated round → loud report, no prompt loop). `-SkipElevationCheck`
bypasses (EXE wrapper + automation). Evidence: refusal path executed with the marker
(loud report + throw, no prompt — safe run).

### Also fixed (project findings F3/F4/F6)

- **F3 ASC path drift:** `New-KoreiConfig` rewrote `app_specific_configuration_path`
  to `%USERPROFILE%\applications.json` while deploying applications.json into
  `%USERPROFILE%\.config\komorebi\` — komorebi would die reading it at startup, and
  `komorebic check` cannot see the problem (verified). Now: the generator keeps the
  template's portable `%USERPROFILE%\.config\komorebi\applications.json` (an absolute
  path only when `KOMOREBI_CONFIG_HOME` overrides), and `Install-Configuration`
  validates that the referenced ASC file exists, failing loudly otherwise.
- **F6 patch not installed by the installer:** new `Install-KorebiPatch` step
  (primary step, runs right after the Komorebi MSI): verifies the repo patched
  binary against its pin, backs up the MSI stock binary as `komorebi.exe.orig`,
  stops a running komorebi gracefully (`komorebic stop --whkd`) when present,
  deploys the pinned binary, re-verifies the hash, restarts when it had to stop.
  Pinned in `binaries/payloads.sha256.json` (+ `.txt`) → the existing integrity gate
  covers it automatically.
- **F4 no test executed the wrapper:** `tests/ticket09-exe-wrapper.tests.ps1` was
  grep-only and even accepted the buggy order. It now compiles the wrapper twice
  (production + `/define:K1C_TEST_FORCE_ELEVATED` test hook) and **executes** it
  beside a recording stub in `%TEMP%`: asserts the stub ran, the switch bound as a
  parameter, no stray args, exit codes 0/10 forwarded verbatim, extra args
  forwarded. **40/40 green on the host.**

---

## 3. Current repository state (verified, not remembered)

| Item | State |
|---|---|
| `scripts/komorebi-install.cs` | fixed (order + stderr + test hook), compiles |
| `komorebi-1click-install.exe` | **rebuilt** from fixed source (repo root, git-ignored) |
| `Install.ps1` | rewritten: self-elevation + patch step + updated docs |
| `scripts/Install-Common.ps1` | ASC fix + guard + `Install-KoreiPatch` + `Invoke-InstallerElevation` |
| `binaries/payloads.sha256.json` / `.txt` | patched binary pinned (7 entries) |
| `docs/Access-Denied-Solving/**` | committed (`2616c89`) — patched binary + toolchain |
| `tests/ticket09-exe-wrapper.tests.ps1` | rewritten, execution-based, **40/40 green** |
| `tests/sandbox-verify-install.ps1` | patch-hash + `.orig` + EXE-entry asserts added (elevation-aware) |
| `tests/sandbox-test-suite.ps1` | same asserts added (older suite, still wired to sandbox-test-harness.ps1) |
| All 90 `.ps1` files | parse clean under Windows PowerShell 5.1 parser |

Host-side verification already run (all safe):
1. Production build + stub E2E (exit 0, stub ran with the switch bound).
2. Function-level suite `%TEMP%\k1c-wrap\func-verify.ps1` — **T1–T5 all PASS**:
   ASC generator emits the portable path; `Install-Configuration` against a **temp**
   `KOMOREBI_CONFIG_HOME` works and `komorebic check` passes on the generated config;
   the ASC guard rejects a missing ASC file (and the fixed path passes); the patch
   step's "already patched" branch runs read-only on the live machine (hash compare,
   then skip — **no process was touched**); the elevation refusal path reports loudly.
3. `ticket09`: 40/40 green (includes the execution tests).

**NOT yet verified:** the full install end-to-end (only possible in Windows Sandbox).

---

## 4. Next steps, in order

```powershell
# From an ELEVATED PowerShell on the host (or double-click-equivalent launch):
# 1. Build the production EXE (already built, but re-run after any .cs change)
pwsh -NoProfile -ExecutionPolicy Bypass -File H:\Repo\komorebi-1click\scripts\build-exe.ps1

# 2. Host-safe regression: wrapper execution tests
powershell -NoProfile -ExecutionPolicy Bypass -File H:\Repo\komorebi-1click\tests\ticket09-exe-wrapper.tests.ps1

# 3. THE real verification — full install inside Windows Sandbox (safe by design)
H:\Repo\komorebi-1click\tests\start-sandbox.ps1
#    then read the report:
H:\Repo\komorebi-1click\tests\start-sandbox.ps1 -ReadExistingReport
```

The sandbox path: `start-sandbox.ps1` writes a temp `.wsb` mapping the repo
READ/WRITE at `C:\komorebi-src`, launches `WindowsSandbox.exe`, the LogonCommand runs
`tests\sandbox-bootstrap.ps1` which writes `test-results\.sandbox-marker` (the
un-spoofable signal) and runs `tests\sandbox-verify-install.ps1 -Repo C:\komorebi-src
-LogDir <repo>\test-results -ContinueOnFailure`. Results land back in the mapped
folder (`test-results\verification-result.json` + `.txt`).

**The sandbox suite refuses to run outside a sandbox** (three independent signals:
marker file, `WDAGUtilityAccount`, no real GPU) — never weaken that gate.

Expected new asserts to watch in the sandbox report (P2-install):
- *the installed komorebi.exe is the patched build (pinned SHA256)*
- *the pristine MSI binary is preserved as komorebi.exe.orig*
- *the EXE wrapper was built into the repo* (+ execution if the sandbox context is elevated)
- *the ASC path resolves / applications.json was placed there* (already existed)

If the sandbox user context is not elevated, the EXE execution assert auto-skips
with a note (ticket 09 covers the execution path on the host) — that is by design,
not a failure.

After the sandbox is green: only then consider the GitHub release for `irm | iex`
(owner decision #4). The bootstrap itself (`Install.ps1` in-memory branch) already
detects `$PSScriptRoot -eq $null` and fetches the repo archive.

---

## 5. Traps that cost time here (read before editing)

1. **Never use the fuzzy `patch` tool with a hand-typed identifier** — it silently
   rewrote `KorebiBin`→`KoreiBin` style drifts in `tests/sandbox-verify-install.ps1`.
   Edit PowerShell with string replacement in Python (exact match, assert first),
   then parse-check. (The repaired file now has zero undefined `$script:` refs —
   keep it that way; a check script pattern is in the audit doc.)
2. **`/init` mangles Windows binary arguments with spaces.** Going through
   `powershell.exe -NoProfile -Command` with the whole call inside one string is the
   reliable route; `-File <path>` works when the path has no spaces.
3. **WSL grep/search tools can serve stale content on `/mnt`** (9p cache) — when a
   grep contradicts a read, trust read/od/PowerShell, then re-verify with another tool.
4. **The user's PowerShell profile loads** even with `-NoProfile` in this setup
   (profile messages at the top of every output). Ignore the noise; filter on your own markers.
5. Name spellings in tests must be extracted from the source (`-match` a regex for
   `function (Install-K\w*Patch)`), never hard-coded — the codebase spells the product
   name in ways that are easy to mistype (and the mistype is invisible).
6. `komorebic check` **cannot** see a missing ASC file (exit 0 with a non-existent
   `app_specific_configuration_path`) — that is why the installer has its own guard.

---

## 6. Open questions for the owner (answer in the next prompt, per project rule)

1. After the sandbox goes green: should I create the GitHub release for `irm | iex`
   (zip asset named exactly `komorebi-1click.zip` at the release root, since the
   bootstrap downloads `.../download/komorebi-1click.zip`)?
2. Repository hygiene: `docs/Access-Denied-Solving/__pycache__/patch_final2.cpython-313.pyc`
   got committed with the toolchain (commit `2616c89`). Remove it and add
   `__pycache__/` to `.gitignore`, or leave it?
3. `komorebi.exe.orig` (the stock MSI binary, 14.6 MB) is now also committed inside
   `Korebi-Patched/` — keep both copies (stock for restore, patched for deploy) or
   drop the `.orig`?

## 7. Doc map for this workstream

- `README.md` — index of this directory
- `AUDIT-2026-10-10-entry-points-and-config.md` — the full audit with evidence (findings F1–F6, rejected hypotheses)
- `HANDOFF-2026-10-10.md` — the audit-phase handoff (superseded in part by this file)
- `IMPLEMENTATION-2026-10-10.md` — implementation log with command-level evidence
- `handoff.md` — **this file, the always-current continuation doc**
