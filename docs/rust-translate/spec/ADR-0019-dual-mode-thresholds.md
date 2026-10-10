# ADR-0019: Dual-mode timing thresholds (strict / relaxed)

**Status:** Accepted
**Date:** 2026-10-10
**Decides:** How the Rust translation's timing assertions tolerate machine load
**Supersedes:** the single hard-coded tolerance set in `tests/rust-ticket02-probe.ps1`
**Referenced by:** `docs/rust-translate/tickets/03-registry-cli-twin.md`, BUILD-CHECKLIST.md

## Context

Ticket 02's execution-contract probe asserted timing properties against a single
set of hard-coded constants:

- a 3 s timeout honoured between 3000 ms and 15000 ms
- worst inter-batch output gap below 250 ms
- a cancel landing inside half the run budget
- 1000 lines batched within 30 s

These values were measured on an idle machine: the timeout lands at ~3.4 s, the
worst observed gap is 65 ms, the cancel lands at ~976 ms of a 30 s budget.

Under load the same assertions become unreliable. With three concurrent builds
running, the tightest of them failed 3/26 and 1/11, then passed again on an idle
machine. The behaviour did not change — the machine did.

This is a classic trade-off, posed to the project owner and answered as a
**dual-mode** scheme rather than a single compromise number.

## Decision

The probe takes an explicit mode that selects the tolerance set. The assertions
themselves are identical in both modes — only the margins differ.

| | strict | relaxed |
|---|---|---|
| `$MinTimeoutMs` | 3000 | 2900 |
| `$MaxTimeoutMs` | 15000 | 45000 |
| `$MaxWorstGapMs` | 250 | 900 |
| `$MaxBatchingMs` | 30000 | 90000 |
| cancel budget ratio | `/2` | `/4` |

**strict is the default.** An unset parameter, an unset environment variable, an
empty string, and no switch at all all resolve to strict. A release or a clean
checkout runs strict; a pass recorded in strict is a real pass.

**relaxed is opt-in and named.** It is chosen with `-Relaxed`,
`-ThresholdMode relaxed`, or `DASHBOARD_THRESHOLD_MODE=relaxed`. A relaxed run
prints `threshold mode: relaxed` in its first line, every assertion message
carries `(mode relaxed)`, and the evidence file records the mode — so a relaxed
pass can never be mistaken for a strict one.

**The modes conflict loudly, not silently.** `-Strict` combined with a relaxed
parameter or environment value exits 3 with an error rather than picking one.

## Rules for callers

- **CI/CD and release gates use strict, and may only run strict.** The gate is
  only meaningful on an idle or isolated runner; on a loaded shared runner the
  correct response is a dedicated runner, not a relaxed gate.
- **Local development may use relaxed** when the machine is busy, and it stays
  honest because the mode is recorded with the result.

## Consequences

- **A pass is never ambiguous.** The mode is a first-class, recorded input to the
  result, not an unstated ambient fact about the machine.
- **The strict numbers stay honest.** They were measured, and they are not
  loosened to accommodate a loaded development machine.
- **The relaxed numbers stay meaningful.** They are ~3-3.5x the strict ceilings,
  above the worst observed under load, not a `MAX_INT` escape hatch.
- **The `DASHBOARD_THRESHOLD_MODE` environment variable does not cross the
  WSL-to-Windows interop boundary** through `win-exec.sh`, so it is not a
  reliable way to set the mode from WSL. Use the parameter or the switch when
  invoking the probe from WSL; the variable is retained for native Windows
  invocations.
- **The cancel ratio is the one assertion whose *logic* changes with the mode**,
  not just its margin: strict requires the cancel inside half the budget, relaxed
  inside a quarter, because on a loaded machine the cancel-to-kill path itself
  takes longer and the ratio is what makes the assertion meaningful.
