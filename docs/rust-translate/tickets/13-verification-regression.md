# 13: Verification and the translated regression net

**What to build:** The contract that was proven against the WPF build is proven again against this
one. The load-bearing assertions from the existing PowerShell suites are re-expressed as tests that
observe external behaviour only; runtime evidence exists for every claim in the specification's
testing decisions; all eight tabs are visually checked in the built executable at 100% and 125%; a
clean-machine run confirms first launch; and the definition of done in the roadmap is closed with
evidence for every line.

**Blocked by:** 12 — Packaged deliverable

**Status:** implemented — 2026-10-11 (session 15). The automated half is complete and green;
the visual/scale/clean-machine lines are Davood's manual pass (see `tests-reminded.md` §session 15).

## The regression net as it stands

**Cargo (53 tests, all green 2026-10-11):**
- `tests/registry.rs` (11) — the registry's invariants: unique verbs, one tab each, help
  generated from the table, documented counts == actual counts, every verb resolves to an
  existing script, GUI/CLI rows agree, read-only/admin flags on every verb.
- `tests/dispatch.rs` (4) — dispatch plumbing: exit-code surfacing, the caller's budget, a
  missing script reporting 127 without launching PowerShell.
- `tests/execution_contract.rs` (9) — batching (a high-line run stays batched), cancel,
  timeout, tree kill, argument splitting, the timeout option being the caller's.
- `tests/elevation.rs` (6) — gate ordering: a non-admin verb is never gated, an admin verb
  unelevated asks for a relaunch, the gate names the registry's features, the refusal is a
  structured result with exit 740.
- lib tests (23) — settings (round-trip across a restart, clamping, quarantine + save),
  fonts (the registry parse), the AutoHotkey manifest + state file, the crash log.

**Vitest (117 tests, all green):** console drag geometry + the clamp band, typography
(preview/persist + the sentinel), the AHK apply contract (serial, stop at first failure,
re-read after bulk), About's copy/version lines, the settings store's contract.

**Native suites against the PUBLISHED executable:**
- `tests/rust-ticket01-cli.mjs` — 6/6 PASS: help exit 0 (4449 B), unknown verb exit 2,
  an argument-less verb refusing an override exit 2, status exit 0 with streamed chunks,
  demo-stream batched (30 chunks), a script failure surfacing exit 7.
- `tests/ticket10-registry-parity.tests.ps1` — 11/11: the Rust and C# registries agree
  field-by-field (35 verbs, 20 with fixed arguments, 6 tabs).
- All PowerShell suites parse cleanly (parser-checked); the ones that touch the live machine
  (elevation relaunch, sandbox) stay with Davood.
- `tests/rust-release-measure.ps1` — the ticket-12 measurements.

## Checks

- [x] Registry completeness, CLI exit codes, batching, cancel, timeout, tree kill, settings
      round-trip, clamping, quarantine, argument splitting, script resolution, elevation gate
      ordering and generated help are each covered by a test that observes behaviour and never
      implementation detail (the suite-by-suite map above; every test drives the shipped
      seams — a spawned process, a parsed document, the registry table itself)
- [x] The existing PowerShell suites are kept and still runnable — nothing was deleted
      (all suites present on disk; parse-checked; the two read-only ones run green above)
- [ ] All eight tabs are visually confirmed in the built executable — **Davood's manual pass**
- [ ] Both 100% and 125% scale are confirmed on the portrait monitor — **Davood's manual pass**
- [ ] A clean-machine run verifies WebView2 availability and a successful first launch —
      **Davood's manual pass** (sandbox)
- [x] Risky or machine-state-altering tests ran in a sandbox, not on the live host — the
      elevation/sandbox suites are sandbox-gated by design and the live-machine rule holds;
      everything run this session was read-only or against the built binary
- [x] Every line of the definition of done in the roadmap is closed with cited evidence
      (see the handoff's DoD table — 6 lines closed with evidence, the 2 visual lines are
      Davood's)
