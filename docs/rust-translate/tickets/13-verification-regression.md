# 13: Verification and the translated regression net

**What to build:** The contract that was proven against the WPF build is proven again against this
one. The load-bearing assertions from the existing PowerShell suites are re-expressed as tests that
observe external behaviour only; runtime evidence exists for every claim in the specification's
testing decisions; all eight tabs are visually checked in the built executable at 100% and 125%; a
clean-machine run confirms first launch; and the definition of done in the roadmap is closed with
evidence for every line.

**Blocked by:** 12 — Packaged deliverable

**Status:** ready-for-agent

- [ ] Registry completeness, CLI exit codes, batching, cancel, timeout, tree kill, settings round-trip, clamping, quarantine, argument splitting, script resolution, elevation gate ordering and generated help are each covered by a test that observes behaviour and never implementation detail
- [ ] The existing PowerShell suites are kept and still runnable — nothing was deleted
- [ ] All eight tabs are visually confirmed in the built executable
- [ ] Both 100% and 125% scale are confirmed on the portrait monitor
- [ ] A clean-machine run verifies WebView2 availability and a successful first launch
- [ ] Risky or machine-state-altering tests ran in a sandbox, not on the live host
- [ ] Every line of the definition of done in the roadmap is closed with cited evidence
