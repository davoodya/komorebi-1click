# 03: Registry completeness and the CLI twin

**What to build:** All 35 verbs live in one registry carrying tab, description, script reference,
read-only and admin flags, and CLI help text. The CLI twin dispatches them headlessly, generates
`--help` from the registry, and returns the complete exit-code contract. This makes the command line
a full alternate surface over the same code path the GUI will use, which is also the project's primary
test seam.

**Blocked by:** 01 — Scaffold and the first tracer bullet

**Status:** done — verified against the published artefact

> **Implemented 2026-10-09 (session 3).** The registry carries **35** verbs (ADR-0018 §1: the
> earlier 28 was a stale count copied forward, and `VerbRegistry.cs` parses to 35 — 31 GUI rows
> plus 4 CLI-only). All seven criteria below are met except where noted for US 55, whose
> *delivery* could not be proven on this host (a ConPTY pseudo-console cannot receive a console
> control event — measured, four topologies, reported as SKIP not as a pass).
> Evidence: `docs/rust-translate/implement/handoff.md`, session 3.

- [x] All **35** verbs are registered, each grouped under exactly one of the eight tabs
- [x] Every declared verb resolves to an existing script file; no verb leaves the registry to find its script
- [x] `--help` is generated from the registry and lists exactly the registered set, with help text and category headers — there is no second hand-maintained copy
- [x] Every verb dispatches headlessly with exit 0, the script's own code, 2 on parse failure, or 127 on a missing script
- [x] An unknown verb or malformed arguments print usage on stderr and exit 2
- [x] Adding a verb requires one registry entry and nothing else (the extension rule holds)
- [x] Read-only and admin flags are exposed on every verb so later tickets can gate on them

## Carried over from ticket 02

Ticket 02 landed the stop path (cancel, timeout, tree kill) and verified it through
the window and through the shipped binary. One CLI rule from the spec belongs here
instead, because it is about the CLI surface this ticket owns rather than the
execution contract:

* **US 55 — Ctrl+C cancels the child rather than orphaning it.** Not implemented in
  ticket 02, and deliberately so: it cannot be verified from the library, and it was
  not provable in the non-interactive session the work was done in. Two Windows
  facts make it non-trivial, both confirmed while investigating:
  1. The release EXE is a windows-subsystem binary (`windows_subsystem = "windows"`)
     so the GUI never flashes a console. A process with no console can never receive
     a console signal, so the CLI path has to call `AttachConsole(ATTACH_PARENT_PROCESS)`
     before it can be interrupted at all.
  2. `GenerateConsoleCtrlEvent` cannot deliver a plain Ctrl+C to a chosen process
     group, but it can deliver Ctrl+Break. So the verifiable harness is: spawn the
     CLI with `CREATE_NEW_PROCESS_GROUP` (Node `detached: true`), then send
     `CTRL_BREAK_EVENT` addressed to that pid.
  The child is already registered under the run id `"cli"`, so once the interrupt is
  received it only has to call the existing `request_cancel("cli")` path — the same
  one the window's Cancel button uses — and the tree kill is then already correct.
  Acceptance for this ticket should include a real interrupt test, not a reasoned
  claim.

  **Implemented, delivery unprovable in this session (measured).** `main.rs` gained
  `run_cli`, which selects on `tokio::signal::ctrl_c()` and calls the existing
  `request_cancel("cli")`, so the tree kill and exit 130 still come from the one
  stop path the window's Cancel button uses. `console::ensure_console` attaches the
  parent console **only** when stdout is a real terminal, because `AttachConsole`
  rebinds the standard handles and would otherwise destroy output capture
  (`dashboard status | grep up` would return nothing).

  `tests/rust-ticket03-interrupt.mjs` drives the real artifact. Its interrupt case
  reports **SKIP** with the measured OS error, because this host runs on a ConPTY
  pseudo-console where Windows delivers no console control event: `GetConsoleWindow()`
  is 0, and `GetConsoleProcessList` reports only the calling process. Four spawn
  topologies were probed with a child that installs a real `SetConsoleCtrlHandler`
  and writes a marker file the instant an event arrives — **none** delivered one,
  and under `CREATE_NO_WINDOW` (the flag the launcher uses) the signal call itself
  fails with `ERROR_INVALID_HANDLE` (6). Run the harness from an interactive console
  to convert the SKIP into a PASS. The other eight cases pass here, including
  "a cancelled run leaves 0 fixture processes behind".
