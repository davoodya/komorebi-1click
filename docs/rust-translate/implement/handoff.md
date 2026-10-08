# Rust translation implementation handoff

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