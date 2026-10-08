# 02: Execution contract — batching, cancel, timeout, tree kill

**What to build:** For every verb, execution honours the no-lag contract. Cancel tears down the whole
process tree and is recorded as cancelled; a hung run is recorded as timed out at its timeout (300 s
default) rather than as a failure; a non-zero exit surfaces exit code, duration and the raw output; a
missing script reports 127 with its path instead of ever launching PowerShell. The window stays
responsive throughout.

**Blocked by:** 01 — Scaffold and the first tracer bullet

**Status:** implemented-verified

- [x] Cancel during `demo-stream` stops child and grandchild processes; no orphaned PowerShell remains afterwards
- [x] A deliberately hung 3-second run reports `TIMED OUT` with its exit code and duration, not `FAILED`
- [x] Cancellation and timeout are distinct recorded facts and neither overwrites the other
- [x] A non-zero exit surfaces exit code, duration and the full raw output in the console pane
- [x] A missing script reports exit 127 and the path, and no PowerShell process is ever created
- [x] A high-line-count run keeps the window responsive — no UI freeze, no per-line emit
- [x] A runtime probe artifact records the batching, cancel and timeout evidence

## Implementation result (2026-10-08, session 2)

Worked on the Windows side in the publish tree `H:\Repo\komorebi-1click`; the
tracker lives in WSL and this file is mirrored byte-identically to
`docs/rust-translate/tickets/02-execution-contract.md`.

**What changed.** `stop_flag` handling became two recorded booleans rather than one
inferred exit code: `ScriptResult` and `Outcome` now carry `cancelled` and
`timedOut`, both set by the backend that actually observed the stop. The runner
gained a per-run-id registry (`HashMap<String, mpsc::Sender>` behind a `LazyLock`)
so a run is cancellable by id and concurrent runs do not disturb each other; the
new Tauri command `cancel_run` deliberately does not consult the busy flag, because
a cancel has to land while a run is live. Every stop path kills the whole process
tree (`taskkill /PID <pid> /T /F`) through a `TreeGuard` whose `Drop` is the safety
net, with the main path killing and awaiting before returning. The console pane
gained a Cancel action, rendered only while a run is in flight, and the frontend
reads the verdict from the flags rather than inferring it from `exitCode`.

**Evidence (all measured against the published artefact, 6,420,992 bytes).**

```text
cargo test --locked        exit 0    4 + 9 = 13 passed / 0 failed
cargo fmt --check          exit 0
cargo clippy --locked -D warnings   exit 0    no warnings
npm run check              exit 0    0 errors, 0 warnings
npm test                   exit 0    44 passed / 0 failed
tests/rust-ticket02-probe.ps1      exit 0   26/26 probes
tests/rust-ticket02-ui.ps1         exit 0   11/11 rendered-UI checks
tests/rust-ticket01-cli.mjs        exit 0   6/6   (regression, unchanged)
tests/rust-ticket01-ui.ps1         exit 0   23/23 (regression, unchanged)
```

Measured facts, not restatements of the code:

* **Cancel.** 600 lines at 50 ms (a 30 s run) stopped after **976 ms**; recorded
  `cancelled=true`, `timed_out=false`, exit **130**; it never reached line 600. In
  the window, the same thing through the real Cancel button: verdict on screen
  **1285 ms** after the click.
* **Timeout.** A 200-line run with a 3 s budget stopped after **3382 ms** with exit
  **124** and verdict `Demo Stream TIMED OUT — exit 124 in 3.38s`; `FAILED` was
  never printed. On the shipped binary: exit 124 in **3868 ms**.
* **Tree kill.** 4 fixture pids alive before the stop, **0** after — including the
  grandchild.
* **Missing script.** Exit **127** with `komorebi-service.ps1` named in stderr and
  **0** batches streamed, so no PowerShell was ever created.
* **Batching.** 1000 lines arrived as **9** batches with a worst inter-batch gap of
  **65 ms**, so it is neither per-line emission nor a stall. All 1000 lines were
  present on the shipped binary.

**Probe artifact.** `tests/rust-ticket02-probe.ps1` writes
`test-results/rust-ticket02/probe-results.json`. It is built from two independent
sources — `[probe] key=value` lines printed by the Rust tests that took each
measurement, plus runs of the shipped binary — so no number in it is hand-typed.
`tests/rust-ticket02-exe-driver.mjs` drives the binary.

**Two things learned the hard way, both now encoded.**

1. The release EXE is a windows-subsystem app, so PowerShell cannot read its stdio
   at all: `& $exe demo-stream` returned exit 0 with **zero bytes**. Node's
   `child_process.spawn` is what actually observes the output, which is why the
   driver exists. Ticket 01's CLI suite already used this technique.
2. Cancelling has to be reachable *while a run is live*. A global busy flag cannot
   express that, which is why cancellation is keyed by run id.

**Deliberately not done here.** Spec US 55 (Ctrl+C cancels the child rather than
orphaning it) is **not** implemented in this ticket: it cannot be verified from the
library, and it was not provable in a non-interactive session. It is recorded with
its findings on ticket 03, which owns the CLI surface — including the two Windows
facts that make it non-trivial (the binary has no console, so it must
`AttachConsole`; and `GenerateConsoleCtrlEvent` can deliver Ctrl+Break but not a
targeted Ctrl+C).

### Proof technique: two corrections

**Do not prove a clean build with file hashes.** A `git worktree add --detach` at
`9932623` held **0 dirty files** and built to a 6,420,992-byte artifact, so the commit
is self-sufficient. But two consecutive builds of that *identical* commit produced
different SHA-256 hashes (`1CBD4C3D…BBDDEE0`, then `7E8FA9D3…D72F6439`). The build is
not byte-reproducible: `build.ps1` stamps HEAD's short sha in via `DASHBOARD_GIT_SHA`
and the PE carries linker metadata. A hash mismatch between an in-tree and a clean
build is expected and proves nothing; 0-dirty-files plus build exit 0 plus a
functional run is the valid proof. (Also: rebuild in-tree after committing, or the
artifact's `gitSha` still names the previous commit.)

**Timing thresholds are load-sensitive.** With three concurrent release builds
running, one probe pass showed 3 of 26 failing and one UI pass 1 of 11; both re-ran
26/26 and 11/11 on an idle machine. The tight tolerance assertions (3 s budget
honoured, worst inter-batch gap < 250 ms, cancel-to-verdict) are the ones that move.
A failure there on a loaded machine is inconclusive — re-run before believing it.
