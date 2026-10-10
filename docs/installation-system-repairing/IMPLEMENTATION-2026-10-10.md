# Implementation log — 2026-10-10 (installer repair, session 1)

Everything below was executed and observed on the machine; nothing is assumed.
All host-side work was live-machine-safe (parse checks, read-only probes, `%TEMP%`
tests, hash reads). The full install is verified in Windows Sandbox only — see
`handoff.md` §4 for the next action.

---

## Change 1 — the EXE wrapper argument order (`scripts/komorebi-install.cs`)

**Before** (the bug): the wrapper's argument string was
`-NoProfile -ExecutionPolicy Bypass <InstallerSwitch> -File "<installer>" ...`.
PowerShell's parser owns everything before `-File`, so it tried to consume
`-SkipElevationCheck` itself and exited **before** the installer ran.

**After:**
```csharp
Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + quotedInstaller
          + " " + InstallerSwitch + " " + BuildArgs(args),
```
Plus: stderr is captured (`RedirectStandardError`), drained before `WaitForExit`,
and any non-empty stderr on a non-zero exit is logged and reported — a GUI parent
with no console can never again show "nothing happened".
Plus: a build-time hook `/define:K1C_TEST_FORCE_ELEVATED` that skips the UAC
relaunch so `tests/ticket09-exe-wrapper.tests.ps1` can execute the wrapper without
a prompt. Production builds never define it.

**Evidence:**
1. Control runs before the fix (same harness): PS 5.1 → exit **1** ("The term
   '-SkipElevationCheck' is not recognized"); pwsh 7 → exit **64** ("not recognized
   as the name of a script file") — the stub installer **never ran**.
2. After the fix, compiled through the same harness: test EXE exit **0**, stub ran,
   stub recorded `bound=[SkipElevationCheck]` (the switch lands as a script parameter,
   not as a host argument).
3. Production EXE strings (`strings -el`): contains `-NoProfile -ExecutionPolicy
   Bypass -File ` and ` -SkipElevationCheck `; the old `-Bypass -SkipElevationCheck`
   is absent.

## Change 2 — self-elevation (`scripts/Install-Common.ps1`, `Install.ps1`)

New `Invoke-InstallerElevation`:
- elevated → print "Running as Administrator." and continue;
- not elevated → relaunch self via `Start-Process -Verb runas`
  (`-NoProfile -ExecutionPolicy Bypass -File "<self>"` + forwarded switches),
  `WaitForExit()`, `exit $child.ExitCode` (the elevated run's code is this run's code);
- decline/launch failure → loud report + throw;
- second non-elevated round (marker `KOMOREBI_1CLICK_ELEVATED_LAUNCH=1`) or no
  `$PSCommandPath` (pure `iex`) → refuse via `Assert-RunningElevated` (report + throw),
  never a prompt loop.

`Install.ps1` calls it when `-SkipElevationCheck` is absent; the wrapper passes the
switch, so the double-click path is: EXE elevates → script skips re-prompting.

**Evidence:** refusal path executed with the marker set — printed the elevation
report and threw (no UAC prompt, no side effects).

## Change 3 — ASC path repair + guard (finding F3)

`New-KoreiConfig` no longer rewrites `app_specific_configuration_path` to
`%USERPROFILE%\applications.json`. It keeps the template's portable
`%USERPROFILE%\.config\komorebi\applications.json` (komorebi expands `%VAR%` itself —
verified against the incident analysis in `docs/Access-Denied-Solving/`), and only
writes an absolute deployed path when `KOMOREBI_CONFIG_HOME` overrides the layout.

`Install-Configuration` gained a guard: after applications.json is ensured, it
expands the generated `app_specific_configuration_path` and **fails the config
phase** if the file does not exist (komorebi would die at startup reading it;
`komorebic check` would not catch it).

**Evidence (function-level, `%TEMP%\k1c-wrap\func-verify.ps1`, T1–T5):**
- T1 generated config: `app_specific_configuration_path == %USERPROFILE%\.config\komorebi\applications.json`, 3 monitors, 9 workspaces each, prefs generated, no `C:\Users\` in the file.
- T2 full `Install-Configuration` against a **temp** config home: ASC path is the deployed absolute path, applications.json deployed, `komorebic check` **exit 0**.
- T3 guard: hand-crafted config (up-to-date displays, ASC → non-existent file) → step fails with the report; same config with the fixed ASC path → passes.
- T4 `Install-KorebiPatch` on the **live machine, read-only path**: detected the already-patched build by hash and skipped — no process touched, nothing written.
- T5 elevation refusal with the marker: loud report + throw.

## Change 4 — the installer now applies the access-denied patch (finding F6)

New step in `Install.ps1` primary steps (runs right after the Komorebi MSI):
```
@{ Name = 'Komorebi patch'; Action = { Install-KorebiPatch -RepoRoot $RepoRoot -PatchedSha256 $payloads['komorebi.exe'].sha256 } }
```
`Install-KorebiPatch` (in `Install-Common.ps1`):
1. `C:\Program Files\komorebi\bin\komorebi.exe` must exist (the MSI ran first);
2. the repo copy `docs\Access-Denied-Solving\Komrebi-Patched\komorebi.exe` must exist and match the pinned SHA256 (`52b631cd…b7e3abb`);
3. already patched (installed hash == pin) → skip;
4. otherwise preserve the stock binary as `komorebi.exe.orig` (once), stop a running
   komorebi gracefully (`komorebic stop --whkd`, `Stop-Process` fallback), deploy,
   re-verify the deployed hash against the pin, and restart when it had been stopped.

`binaries/payloads.sha256.json` (+ `.txt`) carry the entry, so the pre-install
`Test-PayloadIntegrity` gate verifies it automatically.

## Change 5 — tests that actually execute

`tests/ticket09-exe-wrapper.tests.ps1` rewritten (grep-only → execution):
compiles the wrapper production-style and with the elevation hook, runs it beside a
recording stub in `%TEMP%`, and asserts:
- the stub **starts** (this is the regression the old grep-only test could not see),
- `-SkipElevationCheck` arrives as a script parameter with no stray arguments,
- exit codes 0 and 10 are forwarded verbatim,
- extra wrapper arguments reach the installer,
- the source argument order (`-File … + InstallerSwitch`), thin-wrapper rules,
  GUI subsystem, csc compile, self-elevation, patch step wiring, irm|iex bootstrap.

**Result on the host: 40 passed, 0 failed.**

Sandbox suites extended (`tests/sandbox-verify-install.ps1` P2 and
`tests/sandbox-test-suite.ps1`):
- installed komorebi.exe hash == the pinned patched build (with both hashes printed on failure),
- `komorebi.exe.orig` preserved,
- the EXE entry point: built-in-repo assert + real execution **when the sandbox
  context is already elevated** (auto-note otherwise, since a UAC prompt would hang
  the suite; ticket 09 covers execution on the host),
- P3 asserts the patched build survives a reinstall unchanged.

## Repo state

- commit `2616c89` — vendored the patched binary + fixing toolchain + pins.
- working tree: fixed `.cs` (rebuilt EXE), rewritten `Install.ps1`, patched
  `Install-Common.ps1`, manifests, three test files, this doc set.
- 90/90 `.ps1` files parse clean under the 5.1 parser.
