# Final report — komorebi-1click installer (build, verification, debug guide)

**Date:** 2026-10-10 · **Repo:** `H:\Repo\komorebi-1click` (publish copy, source of truth)
**Audience:** whoever continues development or debugs this installer next.
**Read with:** `handoff.md` (always-current continuation doc) and `AUDIT-2026-10-10-entry-points-and-config.md`.

---

## 1. Final deliverables (verified on disk 2026-10-10)

| Deliverable | Path | State |
|---|---|---|
| PowerShell installer | `H:\Repo\komorebi-1click\Install.ps1` | rewritten: self-elevation, `-DryRun`, patch step, arg forwarding |
| Launcher EXE | `H:\Repo\komorebi-1click\komorebi-1click-install.exe` | rebuilt by `scripts/build-exe.ps1`, 9,728 bytes, GUI subsystem, sha256 `fa1dae08…` |
| Shared library | `scripts\Install-Common.ps1` | all install logic; guarded writes + dry-run |
| Wrapper source | `scripts\komorebi-install.cs` | single-file C#, compiled with the in-box `csc.exe` |
| Pre-patched binary | `docs\Access-Denied-Solving\Komedei-Patched\komorebi.exe` | sha256 `52B6313659467B0E…`, pinned in `binaries\payloads.sha256.json` |
| Old deliverables | `Install-old.ps1`, `komorebi-1click-install-old.exe` | owner-renamed, superseded |

Both shipped entry points are in the repo root on purpose: the wrapper looks for
`komorebi-1click-install.exe` beside itself and for `Install.ps1` beside it.

---

## 2. Architecture

```
komorebi-1click-install.exe      (GUI subsystem, no console — nothing is silent)
  └─ resolves Install.ps1 beside itself
  └─ if NOT elevated  → Start-Process -Verb runas (UAC prompt, owner-approved)
  └─ if elevated      → runs it directly
      pwsh -NoProfile -ExecutionPolicy Bypass -File "…\Install.ps1" [-SkipElevationCheck] [-DryRun] …
        └─ Install.ps1  (orchestration + UX + exit codes)
            └─ scripts\Install-Common.ps1  (all logic, dot-sourced into script scope)
```

**Argument forwarding (this was BUG 1).** PowerShell owns everything before `-File`,
so the wrapper must append installer switches *after* the installer path:

```
-NoProfile -ExecutionPolicy Bypass -File "<quoted installer>" <switch> <extra args…>
```

Wrong order = host rejects the switch, exit **64** (pwsh 7) / **1** (5.1), and a GUI
binary shows nothing. Verified in the shipped binary with `strings -el`.

**Exit codes** (documented in the code, forwarded by the wrapper verbatim):
`0` success · `2` config/environment failure · `4` startup-setup failure ·
`10` generic. Self-elevation propagates the child's code back.

**What the install actually writes** (the full list, for impact review):

| Target | Content |
|---|---|
| `C:\Program Files\komorebi\…` | komorebi + whkd + yasb MSI payload (silent MSI) |
| `C:\Program Files\komorebi\bin\komorebi.exe` | **the pinned patched binary** (stock preserved as `komorebi.exe.orig`) |
| `~\.config\komorebi\` | `komorebi.json` (generated), `applications.json`, `whkdrc` (one level up, `~\.config\whkdrc`), `restart-whkd.cmd`, `komorebi-resize.json` (empty state), companions |
| `~\.config\yasb\config.yaml`, `styles.css` | YASB config (copied when absent/not up to date) |
| Start Menu `…\Startup\` | `AppRunner.vbs` (generated from `autohotkey\AppRunner.vbs` template) |
| Registry PATH (Machine) | `%ProgramFiles%\komorebi\bin` |
| Scheduled tasks | `Komrebi` (logon, RunLevel **Highest**), `KomedeiWatchdog` (logon, Highest) |
| `%TEMP%\komorebi-pid` | watchdog state file |
| `…\Startup\komorebi.lnk` | **removed** if present (races the scheduled task) |

Config generation is machine-aware: monitor count/workspaces are detected, display
preferences carried over from an existing file, `app_specific_configuration_path`
kept portable (`%USERPROFILE%\.config\komorebi\applications.json`) or absolute when
`KOMOREBI_CONFIG_HOME` overrides the home. `applications.json` is deployed verbatim
except target-user path rewrites inside whkdrc rules.

---

## 3. The `-DryRun` subsystem — and the bug that made it inert (documented lesson)

### Design
A single script-scope flag, `$script:DryRun`, set by `Set-InstallerDryRun -Enabled:$DryRun`
after the library is dot-sourced. Every mutation goes through one of three helpers:

- `Write-InstallerFile` (files), `New-InstallerDirectory` (directories),
  `Invoke-InstallerAction` (registry/tasks/processes/yasbc/arbitrary script blocks).

Each prints `[DRY-RUN] would …` and does nothing when the flag is set. Post-action
verifications that read a file back detect dry mode and report their intent instead
of failing on the absent file.

### Root cause found (2026-10-10, commit `93cd9f8`)
The library executed **`$script:DryRun = $false`** at dot-source time. `Install.ps1`
declares `-DryRun` as a **switch parameter**, and a script's parameters live in the
**same script scope** a dot-sourced file writes to. So the library's unconditional
initialisation silently overwrote the caller's requested `$true`. Symptoms were
exactly the ones you saw: the parameter proved bound (`DIAG2: DryRun=True`), yet the
banner never printed, the header showed real mode, and the writes ran — a misconfigured
probe regenerated machine paths into three live config files before it was caught.

**Rule worth keeping:** a dot-sourced library must never unconditionally assign a
matching top-level variable — it owns the caller's scope. The flag now initialises
only when absent (`Test-Path variable:script:DryRun`), and `Install.ps1` additionally
captures the requested value into `$script:DryRunRequested` **before** the dot-source.

### Full dry-run safety list (all verified inert on a live machine)
`Test-PayloadIntegrity` · state detection (MSI/process/PATH/tasks hash reads) ·
`Install-KorebiPatch` (stop, copy, post-hash) · MSI installs · `New-KomedeiConfig` ·
`New-Whkdrc` · `restart-whkd.cmd` · resize state · companions · YASB config and
autostart (incl. the `.lnk` fallback) · `AppRunner.vbs` generation and its read-back
verification · watchdogs · scheduled tasks · Machine PATH · legacy shortcut removal ·
AutoHotkey startup marker and state file · `komorebic start/stop`, `komorebic check`,
`yasbc enable-autostart` (never run in dry mode when not already applied).

---

## 4. Verification evidence (host, 2026-10-10 — nothing live was touched)

### 4.1 Isolated lab run — the strongest single proof
Repo copy at `%TEMP%\drylab`, `KOMOREBI_CONFIG_HOME` redirected to an empty temp home,
`pwsh -File …\drylab\Install.ps1 -DryRun -SkipElevationCheck`:

- **exit 0** · stderr 0 bytes
- banner `DRY RUN: nothing will be installed, written, or changed.` · header `Mode: DRY RUN`
- payload integrity **7/7** (real reads) · komorebi `0.1.41` / whkd `0.2.10` / YASB `2.0.7` / AHK v1 `1.1.30.00` / AHK v2 `2.0.12` detected as already installed
- every mutation emitted `[DRY-RUN] would …`; all step lines in the honest `would …` form
- `komorebic check` **skipped with the reason stated** (nothing was written)
- **redirected config home: 0 bytes written**
- **live state: 27/27 keys byte-identical before and after** — every Start Menu `Startup\` file with its SHA256, Machine PATH, `HKCU\…\Run`, and the `Komrebi` / `KomedeiWatchdog` / `YASB` scheduled tasks (name, state, runlevel)

### 4.2 Regression suites (host-safe; they only parse, read the repo, or use `%TEMP%`)
- `tests\ticket05-06-07.tests.ps1` → exit 0, 0 failures
- `tests\ticket08-ahk.tests.ps1` → exit 0, **26/26 assertions green**
- `tests\ticket09-exe-wrapper.tests.ps1` → exit 0, **all checks green** (compiles the wrapper production *and* test-signature, then **executes** it beside a recording stub in `%TEMP%`: exit codes 0/10 forwarded, switch bound, args forwarded)
- parse: `Install.ps1` + `scripts\Install-Common.ps1` clean under **both** 5.1 and 7

### 4.3 Config deployment fidelity (owner requirement: configs must transfer *exactly*)
Fresh generation into an empty temp home, compared against the live machine:

| File | Result |
|---|---|
| `whkdrc` | **BYTE-IDENTICAL** |
| `restart-whkd.cmd` | **BYTE-IDENTICAL** |
| `toggle-transparency.ps1` | **BYTE-IDENTICAL** |
| `safe-restart.ps1`, `safe-restart.repo.txt` | **BYTE-IDENTICAL** |
| `yasb\config.yaml`, `yasb\styles.css` | BYTE-IDENTICAL |
| `komorebi.json` | semantically identical (3 monitors, all workspaces + display preferences match); bytes differ **by design** — the ASC path is written per-machine |
| `applications.json` | **DIFFERS — see §6.1** (one live rule missing from the repo template) |

The live `.config` is therefore intact and matches what the installer deploys, except
for the one `applications.json` drift flagged in §6.1.

### 4.4 Wrapper build
`scripts\build-exe.ps1` → 9,728 bytes, GUI subsystem; the shipped literal order is
`-NoProfile -ExecutionPolicy Bypass -File` **then** `-SkipElevationCheck`
(`strings -el` verified; the old `-Bypass -SkipElevationCheck` literal is gone).

---

## 5. Manual test procedure (for the owner) and expected output

> Do **not** run the real install on the current machine — Komorebi/WHKD/YASB/AutoHotkey
> there must not move. Test on a fresh machine or Windows Sandbox, or start with the
> dry run below, which is inert by design and safe *anywhere*.

### Test A — dry run (safe on any machine; the pre-flight check)
```
komorebi-1click-install.exe -DryRun
```
or
```
pwsh -NoProfile -ExecutionPolicy Bypass -File H:\Repo\komorebi-1click\Install.ps1 -DryRun
```
Expected (abbreviated, exactly this shape):
```
================================================================================
  DRY RUN: nothing will be installed, written, or changed.
================================================================================
Korei-1click installer
Architecture:   x64
Mode:           DRY RUN
Repository root: H:\Repo\komorebi-1click

  Verifying payload integrity...
  Payload verified: komorebi.exe
  … (7 payloads)
  Komorebi 0.1.41 …
    komorebic check skipped in dry run (the configuration was not written).
    [DRY-RUN] would write komorebi.json
    [DRY-RUN] would write whkdrc
    [DRY-RUN] would write AppRunner.vbs into the Startup folder.
    [DRY-RUN] would register the 'Komrebi' logon task (RunLevel Highest) …
  Installation complete.   ← exit code 0
```
Pass criteria: banner present, every action line starts with `[DRY-RUN] would`,
`komorebic check skipped in dry run`, no Start Menu / Program Files / task / PATH
change afterwards, exit code 0.

### Test B — full install (fresh machine or Windows Sandbox ONLY)
```
komorebi-1click-install.exe          ← double-click: UAC prompt, then the console window
```
Expected sequence (each line prints as its step completes):
1. `Repository root: …` · `Architecture check: x64 confirmed.`
2. `Payload verified: <name>` ×7 — any mismatch aborts **before** touching the system
3. MSI detections: `komorebi x.y.z - already installed.`
4. `Korei configuration generated for N monitor(s): DISPLAY1, DISPLAY2…` (a fresh machine writes; this machine says *already matches*)
5. `komorebic check passed.`
6. `whkdrc copied with the target user paths.` · `applications.json copied.`
7. `Windows Defender Firewall rule 'komorebi' present.` (if the profile allows it)
8. `Korei patch installed` **or** `Korei already carries the access-denied patch.`
9. `Built the windowless watchdog launcher (no console flash).`
10. `Scheduled task 'Komrebi' registered (logon, RunLevel Highest).`
11. `AppRunner.vbs generated in the Startup folder.` + the `Generated files` audit lines
12. Final block: `Operating system … · Processors … · Total memory …` then
    `Installation complete.` and footer `Log file: …` — **exit code 0**

Re-run the EXE once more immediately: every step must report `already …` /
`skipped` and still exit 0 (idempotency — nothing rewrites, nothing duplicates).

### Test C — non-elevated PowerShell (no EXE)
```
pwsh -NoProfile -ExecutionPolicy Bypass -File Install.ps1
```
Expected: a UAC consent dialog appears (owner-approved UX); after consent the same
sequence as Test B runs elevated. `-SkipElevationCheck` skips the gate (automation).

---

## 6. Known issues and open decisions

### 6.1 `applications.json` drift (owner decision required)
The **live** `~\.config\komorebi\applications.json` contains one extra rule the repo
template lacks — an `ignore` entry for `explorer.exe` / `CabinetWClass` /
`"Network Connections"` (17 lines around line 3144). Deploying the repo template to a
target machine would lose that rule, which conflicts with "configs must transfer
exactly". Recommendation: copy the live file into `config/applications.json`
(repo-only change, no live write) — or confirm the repo template is canonical.

### 6.2 Windows Sandbox is not usable on this host
`start-sandbox.ps1` cannot launch here: Windows Sandbox errors on this machine and
the account is not an Administrator (elevated scheduled task is the only approved
elevation route, and the owner forbade touching the live stack). The sandbox suites
themselves stay valid — they refuse to run outside a sandbox by design. End-to-end
verification is therefore a manual test on a fresh machine/VM (Test B) until a
sandbox host exists.

### 6.3 Repo hygiene (unchanged from the audit phase)
`docs/Access-Denied-Solving/__pycache__/*.pyc` got committed with the toolchain;
`config\last-backup\*` deletions and `backup\`, `config\backup-*\`,
`scripts\step5\`, `autohotkey\ahk-state.json` are uncommitted local artifacts.
Nothing secret; decide keep/remove/ignore.

---

## 7. Debugging guide

1. **The EXE shows nothing** → it is a GUI binary: run `Install.ps1` directly with
   `-SkipElevationCheck` in a visible console; the wrapper also captures the host's
   stderr into its log. Check switch order first (the classic BUG 1).
2. **Nothing seems to be written** → check the `[DRY-RUN] would …` lines: the flag is
   on. It is set by `Set-InstallerDryRun` from the `-DryRun` **parameter** — if the
   banner is missing while you passed `-DryRun`, suspect a top-level variable
   collision again (§3). Never "fix" it by making the library assign unconditionally.
3. **`komorebic check` fails on a generated config** → look at the
   `app_specific_configuration_path` guard output; a portable path means an override
   (`KOMOREBI_CONFIG_HOME`) is redirecting the home.
4. **Exit code map** — 0 ok · 2 config/environment · 4 startup setup · 10 generic ·
   host-level 64/1 = the wrapper never reached the installer (swap order).
5. **Editing rule** — never use the fuzzy `patch` tool on PowerShell here; it rewrites
   identifiers silently. Use exact-match replacement (assert the match count) and
   `[Parser]::ParseFile` under 5.1 *and* 7 before committing.
6. **Safe probing on a live machine** — `Get-FileHash`, `komorebic check -k <temp>`,
   parse checks, `%TEMP%` copies, `KOMOREBI_CONFIG_HOME` + `StartupDirOverride`
   redirects, and `-DryRun`. Nothing else.

## 8. Repo map for this workstream

- `Install.ps1` — orchestration, UX, exit codes, self-elevation, `-DryRun`
- `scripts\Install-Common.ps1` — all install logic (the file you will edit most)
- `scripts\komorebi-install.cs` + `scripts\build-exe.ps1` — wrapper and its build
- `tests\ticket*.tests.ps1` — host-safe suites (parse/assert/execute-stub)
- `tests\start-sandbox.ps1`, `sandbox-verify-install.ps1` — sandbox pipeline (blocked on a sandbox host, §6.2)
- `docs\installation-system-repairing\` — this report, the current handoff, the audit
- `docs\Access-Denied-Solving\` — the patch toolchain and the pinned binary
