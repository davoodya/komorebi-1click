# Local build checklist — the four phases

Ticket 01 requires that "the four phases of the local build checklist pass from a clean checkout".
This file is that checklist, and `src/KomorebiDashboardRust/build.ps1` is its executable form: the
four phases below are the four blocks in that script, in order. Run it, do not emulate it.

```
pwsh -File H:\Repo\komorebi-1click\src\KomorebiDashboardRust\build.ps1
pwsh -File ...\build.ps1 -SkipRestore     # phases 2-4 only, for a fast re-run
```

| Phase | Command it runs | What passing proves |
|---|---|---|
| 1 — Reproducible restore | `npm ci` then `cargo fetch --locked` | The frontend and Rust dependency sets resolve from the committed `package-lock.json` and `Cargo.lock` alone. A floating or unpinned dependency fails here, not in a user's build. |
| 2 — Static checks | `npm run check` (svelte-check) then `cargo fmt --check` | Zero type errors and zero diagnostics across every `.svelte` and `.ts` file, and Rust formatting is canonical. This is the phase that catches the class of fault which, in the WPF build, escaped the compiler and only appeared at first render (defect D21). |
| 3 — Safe behaviour tests | `npm test` (vitest) then `cargo test --locked --no-default-features` | The frontend's pure rules (argument splitting, console batching and cap, run-verdict wording, the token contract, the literal-colour ban) and the backend's registry/runner contract hold. No state-changing management verb is executed by either suite. |
| 4 — Windows release build and promotion | `cargo tauri build --no-bundle -- --locked`, then copy the executable to `releases\rust\` | The MSVC link step succeeds, the frontend bundle is embedded, and exactly one executable lands in `releases\rust\KomorebiDashboard.exe`. Runtime verification is a separate step and is never inferred from a successful build. |

## After the build

Runtime verification is deliberately not part of the four phases, because a build that links is not a
program that works:

| Evidence | Entry point |
|---|---|
| CLI twin: `--help`, unknown verb, refused override, `status`, streaming, script exit code | `tests\rust-ticket01-cli.mjs` (Windows `node`) |
| Rendered window: header, tab, both rows, READ-ONLY badge, a real button click streaming to completion | `tests\rust-ticket01-ui.ps1` (Windows PowerShell, UI Automation) |
| **Ticket 03** — US 55 interrupt behaviour and the full CLI contract: `--help` as generated, unknown verb, both refusals, the caller's `-TimeoutSeconds`, the two-part `ahk enable` fold, and no orphan after a cancel | `tests\rust-ticket03-interrupt.mjs` (Windows `node`) |

Ticket 01's suites write JSON evidence under `test-results\rust-ticket01\`; ticket 03's
writes per-case `.txt` files plus `summary.json` under `tests\.build\ticket03-interrupt\`.

### Ticket 02 probe: dual-mode timing thresholds

`tests\rust-ticket02-probe.ps1` asserts timing properties (timeout honoured near
3 s, output keeps streaming, cancel lands well inside the budget) and those
assertions are sensitive to machine load. It takes an explicit threshold mode —
**ADR-0019** — so a pass is never ambiguous:

| Invocation | Mode | Use |
|---|---|---|
| `.\tests\rust-ticket02-probe.ps1` | **strict** (the default) | release gate, clean checkout, idle machine |
| `.\tests\rust-ticket02-probe.ps1 -Relaxed` | relaxed | local development on a busy machine |
| `.\tests\rust-ticket02-probe.ps1 -ThresholdMode relaxed` | relaxed | same, explicit |
| `$env:DASHBOARD_THRESHOLD_MODE='relaxed'; .\tests\rust-ticket02-probe.ps1` | relaxed | **native Windows only** — the variable does not cross the WSL→Windows interop boundary |

The mode is printed on the probe's first line and carried in every assertion
message, and `-Strict` combined with a relaxed parameter exits **3** rather than
silently choosing one. **A release may only pass strict.** A relaxed pass is
recorded as a relaxed pass.

### Ticket 03: the interrupt case can legitimately report SKIP

`tests\rust-ticket03-interrupt.mjs` exits **0** with a mix of PASS and SKIP, and **1** only on a
real FAIL. Its `delivered-interrupt` case prints SKIP when the host cannot deliver a console
control event at all — a ConPTY pseudo-console cannot, and this was measured rather than assumed:
`GetConsoleWindow()` is 0, `GetConsoleProcessList` reports one process, and four spawn topologies
(including the launcher's own `CREATE_NO_WINDOW`, where the signal call fails with
`ERROR_INVALID_HANDLE`) delivered no event to a child with a real `SetConsoleCtrlHandler` and a
marker file to prove receipt.

**A SKIP is not a pass.** It is the honest report of a capability that is absent from the runner.
To turn it into a PASS, run the harness from a real interactive console — a normal PowerShell
window, not an agent/PTY session.

## Clean-checkout caveat

Phase 1 is what makes the clean-checkout claim meaningful. The working tree is not a clean checkout:
`config/komorebi.json`, `scripts/safe-restart.ps1` and two staged handoff deletions pre-date this
work and are deliberately preserved. A clean-checkout run of phases 1-4 requires those to be committed
or stashed first; until then the honest statement is "the four phases pass in this working tree".
