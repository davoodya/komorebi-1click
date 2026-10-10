# Rust translation implementation handoff

## 2026-10-10 (session 5) — ticket 03 committed; installer ticket 04 audited and fixed

Two things happened, in the order the implement skill demands: verify first,
then complete what the verification says is incomplete.

**1. Ticket 03 verified, then committed.** The handoff §6 baseline was re-run on
the Windows host before any change. Measured, this session:

```text
cargo test --locked --no-default-features       exit 0   24 passed / 0 failed
npm run check                                   exit 0   0 errors, 0 warnings
npm test                                        exit 0   49 passed / 0 failed
tests/rust-ticket03-interrupt.mjs               exit 0   8 passed, 1 skipped, 0 failed
tests/rust-ticket01-cli.mjs                     exit 0   6/6   (regression)
tests/check-shipped-text.mjs                    exit 0   no foreign script (the file count moves with harness evidence; the assertion is the invariant)
tests/rust-ticket02-probe.ps1                   exit 0   26/26 strict
```

One regression was found on the way in: `check-shipped-text.mjs` had been
*recorded* as exit 0 at 190 files but actually failed at 194 — three lines of
Persian digits (U+06F1) in the session-4 documents (`handoff-last-session.md`
line 107, `ADR-0020` lines 43-44). Fixed by writing the illustrative Jalali
dates in ASCII digits; re-run clean. Recorded as defect R5 in
`bugs-fixing.md`, with the rule: **a baseline is a measurement with a
timestamp, not a status to copy forward.**

Then the work was committed in two focused commits, both scoped by explicit
pathspec so no pre-existing dirty entry could enter:

* `5df6f6d` — session 4's documents: ADR-0019 (dual-mode thresholds), ADR-0020
  (bilingual cheatsheets), the session-4 log, and the dual-mode probe. The first
  attempt at this commit swept the two pre-staged `docs/HANDOFF-*` deletions;
  it was reset and re-issued with pathspecs, so the commit is exactly the four
  intended files and those deletions remain staged for Davood to handle.
* `d64ec0c` — ticket 03: `registry.rs` (the 35-verb table + TABS +
  `render_help`), the registry-driven `run()`, `list_tabs`/`run_cli`/
  `ensure_console`, the frontend `TabDefinition` contract, 11 registry tests +
  5 frontend tests + the interrupt harness, ADR-0018, and the ticket-03 docs.
  22 files.

The tracker drift was repaired too: the dev mirror
(`~/.scratch/rust-translate/issues/03-registry-cli-twin.md`) had every box
ticked and a `done` status, while the publish copy
(`docs/rust-translate/tickets/03-registry-cli-twin.md`) had none — the publish
copy is now a byte-identical mirror again.

**2. Installer track, ticket `04-startup-tasks` — audited against the live
machine, two gaps fixed.** All thirteen boxes were already ticked in the dev
tracker, so this was an audit, and it split the machinery into a canonical path
and a legacy duplicate:

* Canonical — `Install-StartupTasks` in `scripts/Install-Common.ps1`, reached
  through `Install.ps1` (which requires elevation unless `-SkipElevationCheck`).
  Every box holds, and the live machine agrees: `Komorebi` is Running and
  `KomorebiWatchdog` Ready, both `RunLevel=Highest`, the logon action is
  `komorebic.exe start --whkd` with a logon trigger, the watchdog action is the
  windowless launcher pointing at `komorebi-service.ps1 -Action watchdog
  -WatchdogMinutes 5` on a 5-minute repetition, `C:\Program Files\komorebi\bin\`
  is on the machine PATH, and YASB autostarts through its own HKCU Run key.
  The sandbox verification harness (`tests/sandbox-verify-install.ps1`) already
  asserts both tasks' RunLevel and install idempotency.
* Legacy duplicate — `komorebi-service.ps1 -Action install`, reachable by
  double-clicking `scripts/2-ADD-TO-STARTUP.bat`. Two genuine gaps, both fixed:

  1. It registered the tasks at `-RunLevel Highest` **only when the shell was
     already elevated**; unelevated it silently registered Medium-integrity
     tasks — the exact delayed regression ADR-0016 exists to prevent, and on
     this host (standard user) that path always produced the broken state. It
     also skipped the `komorebic` PATH entry and YASB autostart entirely. It
     now refuses at the top of the action — before building the launcher or
     registering anything — naming the elevated entry points, and the
     unelevated fallback branch is deleted.
  2. `-Action status` reported komorebi and whkd but had zero YASB awareness,
     while the ticket requires status to confirm all three. `Get-Health` gained
     `Yasb`/`YasbUptime`/`YasbAutostart` (the same Run-key-or-shortcut test
     `Install-Common.ps1` uses), `Show-Status` prints them, and a missing bar
     or autostart entry counts as a problem.

  Verified: PowerShell parser 0 errors; live read-only `-Action status` printing
  `yasb (status bar): True (up 213m)` and `yasb autostart: True`, verdict
  HEALTHY; live unelevated `-Action install` throwing the refusal with nothing
  registered. The two `SCRIPTS-GUIDE` files (English and Persian) now document
  the elevation requirement and the YASB status lines. Details and the general
  rule are in `bugs-fixing.md` §1.9.

**Not done, honestly:**

* US 55's *delivery* proof still SKIPs on this ConPTY host — measured again this
  session (the harness reported the same ESRCH condition), unchanged, and still
  reported as a skip rather than a fake pass. Convert it by running
  `node tests\rust-ticket03-interrupt.mjs` from a real interactive console.
* The installer's Windows-Sandbox suites (`tests/sandbox-*.ps1`) cannot run
  from this session — they are Sandbox-gated and this host's shell is a
  non-interactive PTY — so the installer fixes are verified by parser plus
  targeted live runs, **not** by the full sandbox harness. A sandbox run of
  `sandbox-verify-install.ps1` remains the deferred proof for those changes.
* The next ticket is still `04-eight-tabs` (frontend). The installer track's
  frontier is separate: its `05-autohotkey-vbs` is blocked by 02, not by the
  audited 04.

---

## 2026-10-09 (session 3) — Ticket 03 complete and verified, except US 55's delivery proof

Ticket `03-registry-cli-twin` is **implemented and verified against the published
artefact**. All seven of its acceptance criteria are met; the one carried-over
item (US 55, Ctrl+C) is implemented and wired to the same cancel path the window
uses, but its *delivery* could not be proven in this session because the host
cannot deliver a console control event — measured, not assumed, and reported as a
`SKIP` rather than a pass. Details in "US 55" below. **The next ticket is
`04-eight-tabs`.**

Artefact: `releases/rust/KomorebiDashboard.exe` — **13,852,672 bytes** (debug
profile; the release build is phase 4 of `build.ps1`). The WPF
`releases/KomorebiDashboard.exe` (170,176,020 bytes) remains untouched.

### What was built

The registry is now the **single table** of 35 verbs, and both surfaces read it:

* `src-tauri/src/registry.rs` (**new**) — all **35** verbs with tab, label, help,
  script, argument shape, fixed arguments, and the `is_read_only` / `requires_admin`
  / `numeric_only` / `render_in_gui` flags. Plus the 8-entry `TABS` table and
  `render_help`, which generates `--help` from the rows (grouped by tab, `[admin]`
  suffix, fixed-width usage column, and the same four "Notes" lines the WPF
  builder emitted). `registry::find`, `verbs_in_tab`, `rows_in_tab`.
* `src-tauri/src/lib.rs` — `run()` resolves through the registry instead of a
  two-verb stub; help is generated, never hand-written; the two refusals are
  decided **before** anything is launched (see the ordering note below);
  `strip_timeout_option` consumes the caller's `-TimeoutSeconds`; `ahk enable
  <key>` / `ahk disable <key>` fold onto their own rows (ADR-0013).
* `src-tauri/src/main.rs` — `list_tabs` command; the CLI path became `run_cli`,
  which selects on `tokio::signal::ctrl_c()` and calls the existing
  `request_cancel("cli")` so the tree kill and exit code stay in one place;
  `console::ensure_console` attaches the parent console **only** when stdout is a
  real terminal (see the capture trap below).
* `src/lib/{ipc,registry.svelte,App}.ts`/`.svelte` — `TabDefinition` + `listTabs`;
  the four former optional fields are now **required**, so a row missing its tab
  is a type error rather than a row drawn in the wrong place; `rowsForTab` filters
  by tab **and** `renderInGui`.

### Evidence (measured, against the published artefact)

```text
cargo test --locked --no-default-features   exit 0    24 passed / 0 failed
cargo fmt --check                           exit 0
cargo clippy --locked --all-targets -D warnings  exit 0    no warnings
npm run check                               exit 0    0 errors, 0 warnings
npm test                                    exit 0    49 passed / 0 failed
tests/rust-ticket03-interrupt.mjs           exit 0    8 passed, 1 skipped, 0 failed
tests/rust-ticket01-cli.mjs                 exit 0    6/6   (regression)
tests/check-shipped-text.mjs                exit 0    190 files, no foreign script
```

The numbers that matter, and where they came from:

| Fact | Measured |
| --- | --- |
| Verbs in the registry | **35** (31 GUI rows + 4 CLI-only) |
| Verbs rendered by `--help` | **35** — the whole set, no second copy |
| Tabs carrying verbs | **6 of 8** (Customization and About are hand-built) |
| Admin verbs | **10** |
| Read-only verbs | **6** |
| Distinct `.ps1` files reached | **22** |
| Unknown verb | exit **2**, `Unknown verb '...'` + usage on **stderr** |
| A verb that declares no value, given one | exit **2** |
| A verb that requires a value, sent bare | exit **2** |
| Missing script | exit **127**, path named, nothing launched |
| `ahk enable <key>` folded | resolves to `ahk-enable` (proven by its refusal of a missing key) |
| `-TimeoutSeconds` | consumed by the caller, never forwarded, budget still honoured |

The registry suite asserts the counts **from the table**, not from a literal in a
document, and cross-checks them against the numbers ADR-0018 records. A row added
without updating the docs fails `the_documented_counts_are_the_counts_the_table_actually_has`.

### US 55 — Ctrl+C cancels the child: implemented, delivery not provable here

The implementation is complete and wired to the one stop path that already exists
(`request_cancel("cli")` → tree kill → exit **130**), so there is no second stop
mechanism to keep correct. What could **not** be produced is the "real interrupt
test" the ticket asks for, and the reason is a measured property of this host:

```text
GetConsoleWindow()        -> 0        (no console is attached)
AllocConsole()            -> False,   ERROR_ACCESS_DENIED (5)
GetConsoleProcessList()   -> 1        (this process only; a ConPTY pseudo-console)
```

The session runs on a **ConPTY pseudo-console**, and Windows does not deliver
`GenerateConsoleCtrlEvent` to a process group there. Four topologies were probed
with a child that installs a real `SetConsoleCtrlHandler` and writes a marker file
the instant an event arrives, so "delivered" means a marker on disk and not a
lucky termination:

| Case | Spawn flags | Signal call | Event received |
| --- | --- | --- | --- |
| shares the harness console | `CREATE_NEW_PROCESS_GROUP` | ok | **no** |
| own new console | `+ CREATE_NEW_CONSOLE` | ok | **no** |
| own new console, harness then attaches | `+ CREATE_NEW_CONSOLE` | ok | **no** (`AttachConsole` → `ERROR_ACCESS_DENIED`) |
| `CREATE_NO_WINDOW` (what the launcher uses) | `+ CREATE_NO_WINDOW` | **fails, `ERROR_INVALID_HANDLE` (6)** | **no** |

So `tests/rust-ticket03-interrupt.mjs` reports `SKIP` with the measured error
rather than asserting a pass it cannot earn. **To convert it to a PASS: run it
from a real interactive console** (`node tests\rust-ticket03-interrupt.mjs` in a
normal PowerShell window). The other eight cases in that file pass in this
session, including the invariant that a cancelled run leaves **0** fixture
processes behind.

A related trap the implementation deliberately avoids, because the WPF build
documented it: **`AttachConsole` rebinds stdout onto the attached console, so
calling it unconditionally destroys output capture.** `dashboard status | grep up`
would return nothing. `console::ensure_console` therefore attaches **only** when
`GetConsoleWindow()` is null *and* stdout is a real terminal; a redirected run
keeps its pipes and gives up interruptibility instead of losing its output.

### Two pitfalls found by implementing (both now encoded)

1. **The budget must be read before the option is stripped.** `-TimeoutSeconds` is
   the caller's option and is removed before dispatch — but `execute()` sourced
   the budget from those same arguments, so stripping first silently reverted every
   caller-specified timeout to the 300 s default. It failed the timeout tests
   immediately. The fix resolves the budget from the **original** arguments and
   passes it into `execute` explicitly; a regression test pins the ordering.
2. **`status` declares `RequiresAdmin: false` but carries the fixed
   `-Action status`.** It is the case that makes the no-arguments rule matter:
   accepting `status -Action install` would turn an unprivileged health check into
   an administrative operation with no elevation gate in front of it (that gate is
   ticket 05). `fixed_arguments` is deliberately **not** counted when deciding
   whether a verb takes user arguments, or the check would exempt exactly the verbs
   carrying the most dangerous fixed flags.

### Where the guard order lives (do not reorder)

In `run()`, in this order: (1) unknown verb → 2; (2) `ahk` two-part fold;
(3) read the budget; (4) strip `-TimeoutSeconds`; (5) a verb declaring a
**required** value sent bare → 2; (6) a verb declaring **no** value given one → 2;
(7) missing script → 127; (8) dispatch. Steps 5 and 6 must stay **after** step 4 or
a legitimate `-TimeoutSeconds` is refused as if it were a script argument.

### Files changed in this session

```text
src/KomorebiDashboardRust/src-tauri/src/registry.rs          (new, the 35-verb table + TABS + render_help)
src/KomorebiDashboardRust/src-tauri/src/lib.rs               (registry-driven run, guards, fold, timeout strip)
src/KomorebiDashboardRust/src-tauri/src/main.rs              (list_tabs, run_cli, console::ensure_console)
src/KomorebiDashboardRust/src-tauri/tests/registry.rs        (new, 11 tests incl. the extension rule)
src/KomorebiDashboardRust/src-tauri/tests/dispatch.rs        (tracer assertions retired to the registry suite)
src/KomorebiDashboardRust/src/lib/ipc.ts                     (TabDefinition, listTabs, required flags)
src/KomorebiDashboardRust/src/lib/registry.svelte.ts         (tabs state, rowsForTab by tab + renderInGui)
src/KomorebiDashboardRust/src/App.svelte                     (current tab from the backend's tab list)
src/KomorebiDashboardRust/src/tests/registry.spec.ts         (new, 5 frontend grouping tests)
src/KomorebiDashboardRust/src/tests/rows.spec.ts             (test helper carries the required flags)
tests/rust-ticket03-interrupt.mjs                            (new, the US 55 + CLI-contract harness)
docs/rust-translate/spec/ADR-0018-stabilization-decisions.md (verb count 35, CI, settings compat)
```

### Not done here, and carried forward

* **Ticket 04 (`04-eight-tabs`)** owns the real eight-tab strip. Until it lands the
  shell renders **one** tab (`CURRENT_TAB = 'Debugging'`) and that tab's own rows —
  which is the point: the tracer's placeholder returned the whole table, exact with
  two verbs and wrong with 35.
* **Ticket 05** owns the elevation gate. `requires_admin` is now on every verb and
  reachable from the frontend, which is what that ticket needs; the CLI still
  dispatches an admin verb without refusing (the WPF build gated here, so this is a
  live parity gap, recorded rather than hidden).

---

## 2026-10-08 (session 2b) — Ticket 02 complete and verified

Ticket `02-execution-contract` is **done and verified against the published
artefact**, and both ticket-01 commits are **pushed to `origin/main`**. The next
ticket is `03-registry-cli-twin`.

Artefact: `releases/rust/KomorebiDashboard.exe` — **6,420,992 bytes**, still the
only file in that directory. The WPF `releases/KomorebiDashboard.exe`
(170,176,020 bytes) remains untouched.

### What was built

The execution contract turned two *inferred* facts into *recorded* ones. Previously
a timeout was guessed from exit code 124 and a cancellation from 130; now the
backend that observed the stop sets `cancelled` / `timedOut` on `ScriptResult`
(and on the internal `Outcome`), and the frontend reads those flags instead of
deriving a verdict from a number. That is what keeps "cancelled" and "timed out"
from collapsing into "failed".

* `src-tauri/src/lib.rs` — a per-run-id registry (`HashMap<String, mpsc::Sender>`
  behind a `LazyLock`) so `request_cancel(run_id)` reaches a live run; `TreeGuard`,
  whose `Drop` kills the whole tree as a safety net while the main path kills and
  awaits first; `timeout_for(arguments)` reading `-TimeoutSeconds` with a 300 s
  default; `process_exists` / `kill_process_tree` for the orphan checks.
* `src-tauri/src/main.rs` — the new `cancel_run` command. It deliberately does
  **not** consult the busy flag: cancelling has to land while a run is live, which
  is the entire point. The busy flag keeps its original job of stopping a *second*
  verb from starting.
* `src/lib/{ipc,dispatch,console.svelte,format}.ts` — `cancelRun`, the
  `cancelled` / `timedOut` fields, a Cancel action rendered only while a run is in
  flight, and verdicts derived from the flags.

### Evidence (measured, against the published artefact)

```text
cargo test --locked                    exit 0    13 passed / 0 failed
cargo fmt --check                      exit 0
cargo clippy --locked -D warnings      exit 0    no warnings
npm run check                          exit 0    0 errors, 0 warnings
npm test                               exit 0    44 passed / 0 failed
tests/rust-ticket02-probe.ps1          exit 0    26/26 probes
tests/rust-ticket02-ui.ps1             exit 0    11/11 checks
tests/rust-ticket01-cli.mjs            exit 0    6/6   (regression)
tests/rust-ticket01-ui.ps1             exit 0    23/23 (regression)
```

The numbers that matter, and where they came from:

| Fact | Measured |
| --- | --- |
| Cancel stops a 30 s run | after **976 ms** (library), verdict on screen **1285 ms** after the real button click |
| Cancel is recorded as | `cancelled=true`, `timed_out=false`, exit **130**, work incomplete |
| Hung run with a 3 s budget | **3382 ms**, exit **124**, `TIMED OUT`, never `FAILED` (shipped binary: 3868 ms) |
| Tree kill | 4 fixture pids alive before, **0** after, grandchild included |
| Missing script | exit **127**, path named, **0** batches, no PowerShell created |
| 1000-line run | **9** batches, worst gap **65 ms**, all 1000 lines present |

`tests/rust-ticket02-probe.ps1` writes `test-results/rust-ticket02/probe-results.json`.
It is assembled from two independent sources — `[probe] key=value` lines emitted by
the Rust tests that took each measurement, and runs of the shipped binary — so
nothing in it is hand-typed (a hand-written summary drifts; a parsed measurement
cannot).

### Three pitfalls, all encoded in the tests now

1. **A windows-subsystem EXE has no readable stdio from PowerShell.** `& $exe
   demo-stream` returned exit 0 with **zero bytes**, which first looked like a
   broken binary and was not. Node's `child_process.spawn` gives the child real
   pipes, so `tests/rust-ticket02-exe-driver.mjs` drives it. Ticket 01's
   `rust-ticket01-cli.mjs` already relied on this.
2. **Cancel must be keyed by run id, not by a global busy flag.** A global flag
   cannot express it — it would refuse the cancel it exists to allow.
3. **Killing the direct child is not enough.** The grandchild holds the pipe
   handles, so only `taskkill /T` on the tree releases them. This is the hang the
   WPF build documented.

### Independent findings carried forward

* **Ticket 03 (CLI surface): US 55, Ctrl+C cancels the child rather than orphaning
  it.** Not implemented here, deliberately — it cannot be verified from the library
  and was not provable in a non-interactive session. Recorded on the ticket with the
  two Windows facts that make it non-trivial: the binary has no console, so it must
  call `AttachConsole(ATTACH_PARENT_PROCESS)` first; and
  `GenerateConsoleCtrlEvent` can deliver Ctrl-Break to a chosen process group but not
  a targeted Ctrl-C, so the harness must use `CREATE_NEW_PROCESS_GROUP` +
  `CTRL_BREAK_EVENT`. The child is already registered as run id `"cli"`, so the
  handler only has to call the existing `request_cancel("cli")`.
* **Ticket 09 (console pane)** owns the console-visual work; the `ScriptResult`
  payload now carries the stop flags it needs.

### Clean-checkout proof, and a correction to how it must be run

A `git worktree add --detach 9932623` checkout held **0 dirty files**, and the full
four-phase build contract ran there and exited **0**, producing a 6,420,992-byte
artifact. So the commit is self-sufficient: every file the build needs is committed.

**Do not use file hashes to prove this — the build is not byte-reproducible.** Two
consecutive builds of the *identical* commit (HEAD `9932623`, same tree, same
toolchain, only `-SkipRestore` differing) produced
`1CBD4C3D…BBDDEE0` and `7E8FA9D3…D72F6439` — different every time, because `build.ps1`
compiles HEAD's short sha in (`DASHBOARD_GIT_SHA`, displayed as `app_info.gitSha`)
and the PE image carries linker metadata. An in-tree/clean-checkout hash mismatch is
therefore expected and proves nothing either way. The valid proof is: **0 dirty
files in the checkout, build exit 0 from it, plus a functional run of the artifact**.
Note the in-tree artifact must be rebuilt after a commit, or the sha stamped in it
still names the previous commit.

### Honest limitations

* **Strict timing thresholds are load-sensitive.** Run under three concurrent release
  builds, one probe run reported 3 of 26 failing and one UI run reported 1 of 11 —
  both re-ran clean (26/26, 11/11) on an idle machine, twice. The affected assertions
  are the tightest tolerances (timeout-honoured-near-3 s, worst inter-batch gap under
  250 ms, cancel-to-verdict). Treat a failure there on a busy machine as inconclusive
  and re-run before believing it; a failure on an idle machine is real.
* `npm audit` reports **0 vulnerabilities** both with `--omit=dev` and across the full
  tree, so nothing needed fixing.
* Concurrency is bounded per run id by the registry, and the busy flag still stops a
  second *verb* from starting. The window therefore still runs one verb at a time;
  the registry's independence is proven by the Rust suite, not by the UI.

### Commits

* `b6b0a2f` — ticket 01, frontend + first verb (64 files).
* `d8d9906` — ticket 01, review findings fixed.
* `c23ea8c` — ticket 01, handoff documentation.
* Pushed to `origin/main` in this session (`de45b7a..c23ea8c`).
* Ticket 02 work is staged for the next commit, scoped to this module's own paths.

---

## 2026-10-08 (session 2) — Ticket 01 complete and verified

Ticket `01-scaffold-first-verb` is **done and verified against the published
artefact**. It is no longer "in progress". The next ticket is
`02-execution-contract`.

Work happened on the Windows side in the publish tree `H:\Repo\komorebi-1click`,
because the rule is that Rust/UI work runs on Windows. The WSL dev tree
(`~/projects/komorebi-1click`) holds the tracker only; the tracker file
`.scratch/rust-translate/issues/01-scaffold-first-verb.md` was updated and mirrored
byte-identically to `docs/rust-translate/tickets/01-scaffold-first-verb.md`.

### State at the start of this session

The backend tracer bullet existed and passed `cargo test`, but there was **no
frontend whatsoever** — no `package.json`, no `vite.config.ts`, no `index.html` —
and `releases/rust/` was empty. So there was no artefact and no runtime evidence,
and the previous handoff's "frontend delegated to an isolated worker" claim was
never true on disk. Treat similar claims in older handoffs as unverified.

### Built in this session

Frontend scaffold, Svelte 5 + Vite 8 + TypeScript 5 + Tailwind 4, versions pinned
exactly with a committed `package-lock.json` (vite 8.3.4 / svelte 5.57.2 / typescript
5.9.3 / tailwindcss 4.3.3 — read from the lockfile, not from memory).

* `src/app.css` — three-layer design system: raw scales, semantic tokens, and an
  `@theme` bridge so utilities such as `bg-surface` resolve from tokens. Dark is
  the default; the light override sits behind an explicit `.theme-light` selector
  so both themes stay addressable without coupling to the OS.
* `src/lib/tokens.ts` — single token catalogue, with a test that locks it to
  `app.css`, so the palette and the components cannot drift apart silently.
* `src/lib/ipc.ts`, `src/lib/dispatch.ts` — the IPC edge, isolated to one module.
* `src/lib/{registry,rows,console}.svelte.ts` — reactive state. Argument assembly
  reproduces the WPF behaviour exactly: fixed arguments first, then a selected
  non-negative numeric option range, then the free-text box; a selected blank
  option contributes nothing.
* `src/components/{TabLayout,VerbRow,ConsolePane}.svelte`, `src/App.svelte`.
* `src-tauri/src/main.rs` — `run_verb` now returns `Result<ScriptResult, String>`.
  This is a Tauri 2.12 requirement for async commands that borrow `State`; without
  it the release build fails to compile.

### Evidence (all measured this session, from the published artefact)

Local build checklist `docs/rust-translate/implement/BUILD-CHECKLIST.md`, four
phases green from a clean state:

```text
npm ci                      exit 0
npm run check               exit 0   0 errors, 0 warnings
npm test                    exit 0   33 passed / 0 failed
cargo fmt --check           exit 0
cargo clippy --locked       exit 0   no warnings
cargo test --locked         exit 0   4 passed / 0 failed
```

Artefact `releases/rust/KomorebiDashboard.exe` — **6,386,176 bytes**, and it is
the **only** file in that directory, so there are no companion files. The WPF
`releases/KomorebiDashboard.exe` (170,176,020 bytes) is untouched, per ADR-0017.

`tests/rust-ticket01-cli.mjs` — **6/6 pass, exit 0**. `status` exits 0 and prints
its script output (1183 bytes read back); an unknown verb exits 2 with usage;
`status -Action install` is refused with exit 2; `demo-stream` delivers 100 lines
in 29–32 discrete reads instead of 100, which is the batching contract; and
`-FailWith 7` propagates as exit code 7 with nothing after it.

`tests/rust-ticket01-ui.ps1` — **23/23 pass, exit 0**. Reads the live window over
UI Automation: header product name and its component list, exactly one tab and one
rendered tab panel, both rows with their action labels, both read-only badges,
exactly one value box on the demo-stream row (the privilege-gated row correctly has
none), console empty-state then Clear, one real click dispatched through the row
action that streamed output and reported exit 0, exactly one real window, and no
process left behind.

### Independent review, and what it changed

Two independent reviews (standards conformance; ticket faithfulness) ran against
`b6b0a2f`. Both cleared the binding rules — English-only text, no literal colours in
components, no unconditional vibrancy, exact version pins, no `.ps1` touched, and
comments that explain why. Both judged the single-tab reading defensible, because
acceptance item 2 asks literally for "one tab".

Three findings were real and are fixed in `d8d9906`:

* `build.ps1` phase 4 now throws if `releases/rust/` holds anything but
  `KomorebiDashboard.exe`. "No companion files" had been true only through
  directory hygiene, so a stray file could have shipped.
* `src/assets/logo.ico` was a byte-identical 353 KB copy of the WPF
  `Resources/logo.ico`, referenced by nothing; deleted. `tauri.conf.json` already
  points at the original for the window/taskbar icon and `App.svelte` imports the
  png, so this was pure repository weight.
* The recorded versions were wrong: vite is **8.3.4**, not 7. The handoff and the
  ticket both said "Vite 7"; both are corrected, and the numbers are now stated as
  read from `package-lock.json`.

Two findings are recorded as deferred shape, not defects: `ScriptResult` has no
explicit `cancelled`/`timedOut` field (a timeout is inferred from exit 124, and the
richer payload belongs with ticket 09's console work), and `--help` prints the
registry rows but hard-codes the `demo-stream` argument list, because per-verb
argument metadata arrives with ticket 03's registry.

### Clean-checkout proof

`git worktree add --detach` on `b6b0a2f` produced a checkout with 36 module files
and **zero** dirty files. The full four phases ran there, exited 0, and produced
`releases/rust/KomorebiDashboard.exe` at 6,386,176 bytes — the same size as the
in-tree artefact. The worktree was then removed and `git worktree list` shows only
the main tree. So the commit is self-sufficient — no file needed for the build was
left uncommitted — and the "clean checkout" acceptance is demonstrated rather than
merely caveated. All 36 project `.ps1` files also parse with zero errors, confirming
nothing in the module reaches into the script layer.

### Facts worth carrying into later tickets

* **Footprint**, idle 45 s after launch, whole process tree: Rust parent 28.5 MB
  working set / 6.3 MB private; WebView2 child 126.8 MB / 38.3 MB. Total
  **155.3 MB working set, 44.6 MB private**. The shell is tiny and the WebView2
  runtime dominates. Ticket 12 compares footprints and needs this baseline.
* **`status` runs unelevated** — no UAC prompt on dispatch, matching its
  `RequiresAdmin: false` declaration.
* **UI Automation technique.** WebView2 exposes the DOM as UIA `Group` elements
  (a button's class lands in `ClassName`), not as `ControlType.Text`. Walking the
  subtree with `TreeWalker` under `ControlViewCondition` is what actually reads the
  rendered window; the older `FindAll(ControlType.Text)` approach finds nothing and
  produces false failures. `tests/rust-ticket01-ui.ps1` documents this in its
  header — reuse it for every later tab.
* **Never walk the process tree recursively on Windows** when measuring or killing:
  parent/child links can cycle, so an unbounded walk hangs. Identify WebView2
  children directly via `ParentProcessId` and delete with `taskkill /PID <pid> /T /F`
  scoped to the app's own pid.

### Honest limitations

* Registry count is **35 verbs**, not the 28 written in the tickets and the ADR.
  Ticket 01 deliberately exposes only `status` and `demo-stream`; the count
  correction belongs to ticket 03.
* Only the single Debugging tab renders, because the two tracer verbs both live in
  that group. The ticket asks for "the first tab carrying a working shared row
  component"; the full eight tabs are ticket 04.
* Cancellation, Ctrl+C and tree-lifecycle completeness are **not** part of this
  ticket and remain with ticket 02. The current 300 s fallback is not its evidence.
* `npm audit` was not run; the dependency set is pinned but not audited.

### Not done, deliberately

No commit was made. The working tree still carries pre-existing unrelated changes —
`config/komorebi.json`, `scripts/safe-restart.ps1`, two already-staged handoff
deletions, and several untracked files. Any commit must be **scoped** to this
module's own paths so none of that is swept in. Baseline HEAD before this work:
`ecb77354b2af9f706b3c2e401838c9eda7dc0f36`.

---

## 2026-10-08 — Ticket 01 in progress (superseded by the section above)

Kept for the record. User requested audit completion followed by Ticket 01 only.
Audit is at WSL `.scratch/rust-translate/audit-2026-10-08/REPORT.md` and
`evidence.json`. The full registry has 35 verbs, not the stale 28; Ticket 01
intentionally exposed only status/demo-stream. Preserve all pre-existing
dirty/staged files, especially `scripts/safe-restart.ps1`, `config/komorebi.json`
and the two staged handoff deletions.

Rust package, pinned dependencies and Cargo.lock; shared registry/runner, bounded
output channel, 50 ms batch emission, both streams, CLI usage and script exit
codes; `status` rejects arguments so it cannot be overridden into an administrative
operation. Tauri main/IPC, backend busy guard, narrow event-listener capability,
local CSP, existing logo resource. Windows build entry
`src/KomorebiDashboardRust/build.ps1`; CLI verification entry
`tests/rust-ticket01-cli.mjs`.

The earlier note that the frontend was "delegated to an isolated worker" was
mistaken: no frontend existed on disk. The remaining gates listed there were all
closed in this session, and the corresponding acceptance criteria in the ticket
were ticked only after the measurements above were taken.