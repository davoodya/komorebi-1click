# installation-system-repairing

Working folder for the **audit and repair of the komorebi-1click installation
system** (the `Install.ps1` / `komorebi-1click-install.exe` entry points),
started 2026-10-10.

| File | What it is |
|---|---|
| **`HANDOFF-2026-10-10.md`** | **Read this first.** Project summary, current state, and the ordered repair plan for the implementation phase. |
| `AUDIT-2026-10-10-entry-points-and-config.md` | The full audit: every finding with its runtime evidence, the hypotheses that were eliminated, and the requirements the new installer version must satisfy. |

## The problem this folder exists for

Both documented entry points are currently broken on a fresh launch:

1. `komorebi-1click-install.exe` — **proven** to never launch the installer at
   all (fatal argument-order bug in the C# wrapper; exit 64, zero output, the
   child PowerShell never runs).
2. `Install.ps1` — no code defect, but it stops at its own elevation gate when
   launched directly by a non-admin user (which is the reference account).

Plus one latent install-time bug that recreates the 2026-10-10
`applications.json` crash class on any fresh machine, and the new requirement:
**after the Komorebi MSI step the installer must deploy the patched
`komorebi.exe`** (`docs/Access-Denied-Solving/Komorebi-Patched/komorebi.exe`)
instead of leaving the pristine MSI binary in place.

See the two documents above for the evidence and the plan.
