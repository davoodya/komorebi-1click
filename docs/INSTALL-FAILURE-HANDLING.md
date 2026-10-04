# Installer failure handling and re-install semantics

Date: 2026-10-04
Status: implemented, asserted by `tests/sandbox-test-suite.ps1` T04.1d

---

## Requirement

The installer installs five payloads: Komorebi, WHKD, YASB, AutoHotkey v1 and
AutoHotkey v2. Not all of them are equally important:

- **Primary** — Komorebi and WHKD. Without these the product does nothing at
  all; there is no window manager and no hotkey layer.
- **Secondary** — YASB and AutoHotkey. These are conveniences layered on top of
  the window manager. A machine without them is still fully usable.

The failure behaviour must match that ranking:

1. A **primary** failure shows the user a prominent warning containing the
   **cause** and the **how to fix** it, then **stops** the install.
2. A **secondary** failure shows the same warning with cause and fix, but the
   install **continues** through the remaining steps.
3. On a **re-run** after the user has fixed the reported problem, everything
   that already succeeded is **detected and skipped**, so only the failed
   components are reinstalled.

## Implementation

`Install.ps1` — the two priority classes:

```powershell
$primarySteps = @(
    @{ Name = 'Komorebi';     Action = { Install-Komorebi    -Payload $payloads['komorebi-0.1.41-x86_64.msi'] } }
    @{ Name = 'WHKD';         Action = { Install-Whkd        -Payload $payloads['whkd-0.2.10-x86_64.msi'] } }
)

$secondarySteps = @(
    @{ Name = 'YASB';          Action = { Install-Yasb         -Payload $payloads['yasb-2.0.7-x64.msi'] } }
    @{ Name = 'AutoHotkey v1'; Action = { Install-AutoHotkeyV1 -Payload $payloads['AutoHotkey.1.1.30.00_setup.exe'] } }
    @{ Name = 'AutoHotkey v2'; Action = { Install-AutoHotkeyV2 -Payload $payloads['AutoHotkey_2.0.12_setup.exe'] } }
)
```

A primary failure aborts immediately. The user sees the failing step, the
underlying cause (unwrapped to the **innermost** exception message, because MSI
and .NET failures nest the real reason two or three levels deep) and the
concrete remedy, then `INSTALL ABORTED` and exit code 1.

A secondary failure is collected into `$secondaryFailures` and the loop moves
on. At the end of the run the user gets a summary naming exactly which optional
components are missing, a reminder that the window manager and its hotkeys are
installed and working, and the instruction to re-run. That path exits 10, so an
unattended run (the EXE wrapper) can distinguish "everything installed" from
"usable but incomplete".

## Re-install semantics (point 3)

This part already worked and is why the requirement is satisfiable at all.
Every `Install-*` function funnels through `Install-MsiProduct`, which calls
`Get-InstalledMsiVersion -ProductCode` before doing anything:

- The product is present at the expected version → `Write-StepSkipped`, the
  step is a no-op.
- The product is present at a different version → it is upgraded.
- The product is absent → it is installed.

So a re-run after a partial failure reinstalls exactly the missing pieces and
touches nothing else. Nothing had to change here; the guarantee comes from the
detection probe every step runs first.

## Where the failure text comes from

`Report-InstallerFailure` in `scripts/Install-Common.ps1` accepts either an
`ErrorRecord` (the normal case, from a `catch` block) or an explicit
`Cause`/`Remedy` pair, and normalises both to the same report. The innermost
exception is what gets printed, so the user sees `the MSI returned 1603` rather
than `the running command stopped because the preference variable "ErrorActionPreference"...`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Everything installed |
| 1 | A primary component (Komorebi or WHKD) failed — the run aborted |
| 2 | Configuration generation failed |
| 3 | Startup tasks failed |
| 4 | The AutoHotkey startup launcher failed |
| 10 | Install completed, but one or more secondary components failed |

## Tests

`tests/sandbox-test-suite.ps1`, section `T04.1d`:

- `Install.ps1` stops on a primary failure
- `Install.ps1` continues past a secondary failure
- secondary failures are collected, not thrown
- the user is told which secondary components are missing

All four are source-level assertions against the shipped `Install.ps1`, so a
regression to a single flat step list (which aborts on every failure) fails the
suite.
