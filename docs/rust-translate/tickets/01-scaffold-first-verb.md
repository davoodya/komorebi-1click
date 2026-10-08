# 01: Scaffold and the first tracer bullet — two verbs end to end

**What to build:** Launching the new app shows a window — header with the project logo, product name
and version, and the first tab carrying a working shared row component. The registry mechanism exists
with two verbs: a read-only health verb (`status`) and a chatty test verb (`demo-stream`). Clicking
either dispatches the real shipped script, streams output into a console pane in ~50 ms batches, and
ends with a status line showing exit code and duration. The CLI twin dispatches exactly the same two
verbs headlessly and returns the same exit codes. The build produces one self-contained executable in
`releases\rust\`.

**Blocked by:** None (can start immediately) — this ticket is the prefactor: it establishes the build
pipeline, the IPC shape, the batching pattern and the row/console layout once, so later tickets extend
them instead of inventing them.

**Status:** implemented-verified

- [x] `cargo tauri build` on Windows produces exactly one executable in `releases\rust\`, with no companion files
- [x] Executing it opens a window showing header (logo, product name, version) and one tab — no blank or black window (D21 must not return)
- [x] The registry table is the single source: one declaration drives the row, the IPC payload and the CLI dispatch
- [x] Clicking `status` runs the shipped script and streams its output live; status line shows exit code 0 and duration
- [x] `demo-stream` output arrives in ~50 ms batches — one emit per window, never one per line
- [x] CLI twin: dispatching `status` exits 0 and prints the script output; an unknown verb exits 2 with usage
- [x] An automated suite covers the registry's structural contract: unique verb identifiers and every declared script resolving to an existing file
- [x] No component contains a literal colour value — theme tokens only
- [x] All shipped text is English
- [x] The four phases of the local build checklist pass from a clean checkout

---

## Implementation evidence (2026-10-08)

Work done on the Windows side, in the publish tree `H:\Repo\komorebi-1click`
(publish is the source of truth; this file is the WSL tracking mirror).

### What was missing when the session started

The backend tracer bullet existed and passed `cargo test`, but there was **no
frontend at all** (no `package.json`, no `vite.config.ts`, no `index.html`) and
`releases\rust\` was empty, so no artefact and no runtime evidence existed.

### Built

* Frontend scaffold: Svelte 5 + Vite 7 + TypeScript 5 + Tailwind 4, exact-pinned
  versions, committed `package-lock.json`.
* Design system (`src/app.css`) in three layers: raw scales, semantic tokens,
  `@theme` bridge so utilities such as `bg-surface` resolve from tokens. The dark
  theme is the default and the light override sits behind an explicit
  `.theme-light` selector so both themes are addressable without OS coupling.
* `src/lib/tokens.ts` — the single token catalogue. It exports the token contract
  that a test locks to `app.css`, so a component and the palette cannot drift
  apart silently.
* `src/lib/ipc.ts` / `dispatch.ts` — the IPC edge, isolated in one module.
* `src/lib/registry.svelte.ts` + `rows.svelte.ts` + `console.svelte.ts` — reactive
  state; argument assembly reproduces the WPF behaviour exactly (fixed arguments
  first, then a selected non-negative numeric option range, then the free text
  box; a selected blank option contributes nothing).
* `src/components/TabLayout.svelte`, `VerbRow.svelte`, `ConsolePane.svelte`.
* `src/App.svelte` — header (logo, product name, version) and tab shell.
* `src-tauri/src/main.rs` — `run_verb` now returns `Result`; a Tauri 2.12
  constraint requires it for async commands that borrow `State`, and without it
  the release build fails.

### Verification actually run

Local build checklist (`docs/rust-translate/implement/BUILD-CHECKLIST.md`), all four
phases green from a clean state:

```unknown
npm ci                      exit 0
npm run check               exit 0   0 errors, 0 warnings
npm test                    exit 0   33 passed / 0 failed
cargo fmt --check           exit 0
cargo clippy --locked       exit 0   no warnings
cargo test --locked         exit 0   4 passed / 0 failed
```

Artefact: `releases\rust\KomorebiDashboard.exe`, **6,386,176 bytes**, and it is
the **only** file in that directory — no companions. The WPF
`releases/KomorebiDashboard.exe` (170,176,020 bytes) is untouched, as ADR-0017
requires.

Runtime, against that published artefact:

* `tests/rust-ticket01-cli.mjs` — **6/6 pass**. `status` exits 0 and prints the
  script output (1183 bytes read back); unknown verb exits 2 with usage;
  `status -Action install` is refused with exit 2; `demo-stream` emits its 100
  lines in 29–32 discrete reads rather than 100, which is the batching contract;
  `-FailWith 7` propagates as exit code 7 with nothing after it.
* `tests/rust-ticket01-ui.ps1` — **23/23 pass**. Reads the live window through
  UI Automation: header product name plus its component list, exactly one tab
  and one rendered tab panel, both rows present with their action labels, both
  read-only badges, exactly one value box on the demo-stream row (the
  privilege-gated row correctly has none), console empty-state then Clear, one
  real click dispatched through the row action that streamed output and reported
  exit 0, exactly one real window (the Tauri message-loop helper is filtered),
  and no process left behind.

### Two measurements worth carrying forward

* **Footprint** (idle, 45 s after launch, whole tree): Rust parent 28.5 MB
  working set / 6.3 MB private; WebView2 child 126.8 MB / 38.3 MB. Total
  **155.3 MB working set / 44.6 MB private**. The window shell is tiny; the
  WebView2 runtime dominates. Relevant to ticket 12, which compares footprints.
* **`status` runs unelevated.** No UAC prompt appeared when dispatching it, which
  matches its `RequiresAdmin: false` declaration. The row renders no value box,
  consistent with its `options` being a non-numeric `Action` set.
