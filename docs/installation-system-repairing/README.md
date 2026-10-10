# installation-system-repairing

Working folder for the **audit and repair of the komorebi-1click installation
system** (the `Install.ps1` / `komorebi-1click-install.exe` entry points),
started 2026-10-10.

| File | What it is |
|---|---|
| **`handoff.md`** | **Read this first. Always current.** The live-machine rule, owner decisions, what is fixed and verified (with evidence), the exact next action, traps, and open questions. |
| **`final-report.md`** | **Build / verification / debug guide.** Final deliverable paths, architecture and data flow, the dry-run subsystem and its root-cause bug, host verification evidence, the manual tests A/B/C with expected output, known issues and the debugging checklist. |
| `AUDIT-2026-10-10-entry-points-and-config.md` | The full audit: every finding with its runtime evidence, the hypotheses that were eliminated, and the requirements the new installer version must satisfy. |
| `IMPLEMENTATION-2026-10-10.md` | Implementation log: each change with the commands run and the observed output. |
| `HANDOFF-2026-10-10.md` | The audit-phase handoff (superseded in part by `handoff.md`). |

## The problem this folder exists for

Both documented entry points were broken on a fresh launch:

1. `komorebi-1click-install.exe` — **proven** to never launch the installer at
   all (fatal argument-order bug in the C# wrapper; exit 64, zero output, the
   child PowerShell never runs). **FIXED 2026-10-10** (switch moved after `-File`;
   verified by executing the rebuilt wrapper next to a stub).
2. `Install.ps1` — no code defect, but it stopped at its own elevation gate when
   launched directly by a non-admin user (which is the reference account).
   **FIXED 2026-10-10** (self-elevates via UAC and forwards the child exit code).

Plus one latent install-time bug that recreated the 2026-10-10
`applications.json` crash class on any fresh machine (**FIXED**: portable ASC path +
existence guard), and the new requirement — **after the Komorebi MSI step the
installer deploys the patched `komorebi.exe`**
(`docs/Access-Denied-Solving/Korebi-Patched/komorebi.exe`, pinned in
`binaries/payloads.sha256.json`) instead of leaving the pristine MSI binary.
**DONE 2026-10-10**; end-to-end proof is the pending Windows Sandbox run.

See `handoff.md` for the current state and the next action.
