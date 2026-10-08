# 02: Execution contract — batching, cancel, timeout, tree kill

**What to build:** For every verb, execution honours the no-lag contract. Cancel tears down the whole
process tree and is recorded as cancelled; a hung run is recorded as timed out at its timeout (300 s
default) rather than as a failure; a non-zero exit surfaces exit code, duration and the raw output; a
missing script reports 127 with its path instead of ever launching PowerShell. The window stays
responsive throughout.

**Blocked by:** 01 — Scaffold and the first tracer bullet

**Status:** ready-for-agent

- [ ] Cancel during `demo-stream` stops child and grandchild processes; no orphaned PowerShell remains afterwards
- [ ] A deliberately hung 3-second run reports `TIMED OUT` with its exit code and duration, not `FAILED`
- [ ] Cancellation and timeout are distinct recorded facts and neither overwrites the other
- [ ] A non-zero exit surfaces exit code, duration and the full raw output in the console pane
- [ ] A missing script reports exit 127 and the path, and no PowerShell process is ever created
- [ ] A high-line-count run keeps the window responsive — no UI freeze, no per-line emit
- [ ] A runtime probe artifact records the batching, cancel and timeout evidence
