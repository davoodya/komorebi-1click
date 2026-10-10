# Next Agent — KomorebiDashboard Rust Translation

You are the next implementation agent on the **KomorebiDashboard** translation:
.NET 8 WPF → **Rust + Tauri 2** (Svelte frontend). This project follows the
**Matt Pocock** workflow: spec → tickets → implementation. You are in the
implementation phase, on ticket **`04-eight-tabs`**.

This prompt tells you what to read and what to do. Read the documents in the order
given — they were written so an agent with zero context can continue from them.

---

## 1. Read these, in this order

All paths are on the Windows publish tree, reached from WSL as
`/mnt/h/Repo/komorebi-1click/...` with `export ALLOW_WINDOWS=1`.

1. **`docs\rust-translate\handoff.md`** — **the continuation document.** Start here.
   It holds the current state, the verification baseline, the locked decisions, the
   known gaps, and the exact resume point.
2. **`docs\rust-translate\implement\BUILD-CHECKLIST.md`** — the build contract (the
   four phases of `build.ps1`) and the runtime verification that is separate from a
   successful link.
3. **`docs\rust-translate\knowledges.md`** — domain knowledge and invariants.
4. **`docs\rust-translate\codebase-inventory.md`** — per-file C# → Rust map.
5. **`docs\rust-translate\bugs-fixing.md`** — defects that must not return.
6. **`docs\rust-translate\spec\spec.md`** — the specification (84 user stories, the
   IPC contract, the seams).
7. **`docs\rust-translate\spec\ADR-0017` … `ADR-0020`** — the decisions:
   ADR-0017 the stack · ADR-0018 the 35-verb count and stale-prose corrections ·
   ADR-0019 dual-mode timing thresholds · ADR-0020 bilingual cheatsheets.
8. **`docs\rust-translate\tickets\04-eight-tabs.md`** — **your ticket.**
9. The tickets your ticket blocks or is blocked by (read its "Blocked by").
10. **`src\KomorebiDashboardRust\`** — the Rust codebase as it stands after ticket
    03.
11. **`src\KomorebiDashboard\`** — the .NET 8 WPF codebase, when the ticket you are
    on needs parity detail.

The tickets also exist on the WSL side at
`~/projects/komorebi-1click/.scratch/rust-translate/issues/`.

**Do not skip step 1.** The handoff is the document that knows what has already
been done and what has already gone wrong.

---

## 2. Confirm the baseline before you write a line of code

Anything red here means something changed since the handoff was written — find out
what before building on it.

```powershell
cd H:\Repo\komorebi-1click\src\KomorebiDashboardRust\src-tauri
cargo test --locked --no-default-features
cd ..\src\KomorebiDashboardRust
npm run check ; npm test
cd H:\Repo\komorebi-1click
node tests\rust-ticket03-interrupt.mjs
.\tests\rust-ticket02-probe.ps1
```

Expected, all green: 24 `cargo` tests, 49 `npm` tests, ticket 03's harness 8 pass /
1 skip, ticket 02's probe 26/26 in strict mode.

The one `SKIP` is `delivered-interrupt` — a measured ConPTY limitation, not a code
defect. `handoff.md` §8 explains it and how to convert it to PASS. **Do not weaken
that case to make it pass.**

---

## 3. Your ticket: `04-eight-tabs`

The eight-tab strip. **The backend is already built for it** — this is a frontend
task:

1. `registry.rs` already exposes `TABS` (8 entries, ordered),
   `verbs_in_tab(id)` / `rows_in_tab(id)`, and `main.rs` already serves
   `list_tabs` over IPC.
2. In `src/lib/registry.svelte.ts`, replace the `CURRENT_TAB` constant with real
   selected-tab state. **Keep `rowsForTab`** — the guard it applies (`tab` **and**
   `renderInGui`) is what stops an admin verb appearing in a read-only tab.
3. `App.svelte` reads the heading from `registry.tabs.find(...)`; extend that to
   render the strip.
4. **Customization and About carry no registry verbs** — they are hand-built
   surfaces (ticket 11).
5. **Order is the registry's order, not alphabetical.** `rowsForTab` preserves it,
   and the frontend test
   `preserves the order the registry declares rather than sorting` exists because
   sorting would break the parity this rewrite exists to preserve.

After the ticket: run the four build phases (`build.ps1`), then the runtime
verification, and append your results to `handoff.md`.

---

## 4. The rules that bind this project

These are recorded because each one was learned the hard way. They are in
`handoff.md` §11 with more detail — read them.

* **The build host is Windows.** `cargo` and `npm` run through
  `~/.hermes/scripts/win-exec.sh pwsh '<inline script>'`. A WSL-native build is not
  the contract.
* **`win-exec.sh` takes one inline script string** — not `-File`, not `-Command`:
  `win-exec.sh pwsh 'Get-Date'`.
* **`win-exec.sh` does not propagate WSL environment variables to Windows.** Pass
  parameters explicitly, not through the environment.
* **`win-exec.sh` reports `$LASTEXITCODE` unreliably across a pipe.** Do not pipe
  it through `Select-Object` — you will see `0` for a failing command.
* **The registry is the single source of truth.** Frontend and backend both derive
  from it. Never keep a second list.
* **Shipped text is English only** — `tests/check-shipped-text.mjs` enforces it.
* **No new dependency without justification.** The console FFI in `main.rs` is
  hand-rolled so `--locked` stays honest.
* **Questions are never asked interactively.** They go in the final report; Davood
  answers them in the next prompt. For anything ambiguous, do not act on your own
  initiative — record the question.
* **After every change:** build check, then `cargo test`, then `npm run test`, and
  only then a packaged build. Runtime verification is separate and is never
  inferred from a successful link.
* **The cheatsheets' source is the dev tree** at
  `~/projects/komorebi-1click/cheatsheets/`, which is newer than the published
  copies. Per ADR-0020 they are bilingual (`cheatsheets/fa/` + `cheatsheets/en/`),
  and the Persian file is authoritative.

---

## 5. What to do after each ticket

1. Check off every acceptance criterion in the ticket.
2. Run the four phases of `build.ps1`.
3. Run the runtime verification for the ticket.
4. Update the handoff documents: `handoff.md` (the continuation document) and, for
   a session log, `handoff-last-session.md`. Record what was done, what was
   verified, what was deliberately left, and the exact point to resume from. If the
   connection drops, the next agent must be able to continue from the handoff
   alone.
5. Update `knowledges.md` and `bugs-fixing.md` if you learned anything.
6. Put any question for Davood in your final report, not mid-work.

---

## 6. After ticket 04

The remaining tickets, in dependency order:

`05-elevation` → `06-settings` → `07-visual-system` → `08-typography-scale` →
`09-console-pane` → `10-autohotkey-tab` → `11-customization-about` →
`12-packaged-deliverable` → `13-verification-regression`.

Ticket **05 is the first one with a live parity gap**: the CLI still dispatches an
admin verb without refusing, where the WPF build gated with `ElevationService.CanRun`
before launch. That gap is recorded in `handoff.md` §8, not hidden.

---

## 7. Final-report language

Work and think in English. The final report to Davood is in **Persian**, with
technical terms kept in English.
