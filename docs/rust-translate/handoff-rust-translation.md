# Handoff — Rust translation track (sessions 1–12)

This document is the handoff for the **Rust/Tauri dashboard translation** track only
(`docs/rust-translate`, tickets `01`–`13`). The installer track has its own
`docs/rust-translate/handoff.md`; this file exists so the two tracks' state can
never be confused. Written 2026-10-11, session 12.

## 0. THE HEADLINE FOR THE NEXT SESSION

**Two tickets were implemented in session 12: `06-settings` and `07-visual-system`.**
Ticket `05-elevation` was already implemented by the installer track's ticket 12
(sessions 10–11) and is now marked as such here. The next un-implemented tickets,
in dependency order, are:

1. **`09-console-pane` (partial)** — the remaining checks are the pane's **drag
   handle** (clamped 10–60 %) and the **restart persistence** of the chosen
   height. The settings document already carries `consolePercent` (written by
   ticket 06), so this ticket is: add the handle, apply the value from the
   document at startup, save on drag end.
2. **`08-typography-scale`** — the document already carries `fontFamily`,
   `fontSize`, `uiScale`, `consoleFontFamily`, `consoleFontSize` (ticket 06's
   fields) and the CSS already exposes `--ui-font`, `--ui-font-size`,
   `--console-font`, `--console-font-size`, `--ui-scale`; what remains is the
   Settings-tab UI to change them plus applying them from the document.
3. **`10-autohotkey-tab`**, **`11-customization-about`**, **`12-packaged-deliverable`
   (finish)**, **`13-verification-regression`** (its automated checks are largely
   satisfied — §4 — the rest is Davood's manual pass).

**Full ticket audit (verified against the code, not memory):**

| Ticket | Status | Evidence |
|---|---|---|
| 01 scaffold + first verb | done | shell, registry, CLI twin, console — all live |
| 02 execution contract | done | `src-tauri/src/lib.rs` + `tests/dispatch.rs` (4) + `tests/execution_contract.rs` (9) |
| 03 registry / CLI twin | done | registry parity suites |
| 04 eight tabs | done | `App.svelte` + `tabs.spec.ts` |
| 05 elevation | **done via installer ticket 12** (sessions 10–11) | gate + exit-740 + relaunch + generated dialog + ticket-12's static suite 48/48; this refers the same implementation |
| 06 settings | **done — session 12** | `src-tauri/src/settings.rs` (11 cargo tests) + `src/lib/settings.ts`, `settings.svelte.ts`, `SettingsPane.svelte` (12 vitest) |
| 07 visual system | **done — session 12** | `theme.ts` hex/cycle additions, `app.css` `[data-accent="Custom"]`, Toggle Color button, `--accent-custom` token |
| 08 typography scale | **not implemented** | document fields + CSS tokens exist (from 06/07); no UI yet |
| 09 console pane | **partial** | batching, pinned autoscroll, cancel, status line, cap exist; **drag handle + persist remain** |
| 10 AutoHotkey tab | not implemented | — |
| 11 customization/about | not implemented | — |
| 12 packaged deliverable | partial | release build + pins exist (installer t13); icons/installer bundling remain |
| 13 verification/regression | partial | automated coverage exists (§4); visual/scale/sandbox confirmations are **Davood's manual pass** |

## 1. ⚠ TEST OWNERSHIP — READ THIS FIRST

**Davood runs the full test pass himself, after the Rust translation is
complete.** He stated this as a standing answer (2026-10-11, session 12): tests
as a whole are executed by him at the end of the Rust translate work — **remind
him when the translation is finished**, and until then do not claim the
translation is "tested" beyond the automated evidence each ticket leaves.

What that means for the implementing agent:
- Automated suites (cargo/vitest/static) ARE run per ticket and must be green
  before a ticket is marked done — that is the ticket's evidence, and it is what
  the review and commit gates require.
- The end-to-end passes — every tab clicked in the built executable, 100 % and
  125 % scale on the portrait monitor, a clean-machine first launch, elevation
  UAC accept/decline, and anything that touches the live Komorebi/WHKD/YASB
  stack — are **Davood's manual pass**. Record them in `tests-reminded.md` and
  leave them unchecked.
- The LIVE-MACHINE RULE still holds: never run anything that touches the live
  Komorebi/WHKD/YASB configuration on this Windows host; Windows Sandbox or
  `-DryRun` only.

## 2. What session 12 actually built

**Ticket 06 — Settings** (WPF parity: `SettingsStore.cs`, same file name and
writes):

- `src-tauri/src/settings.rs` — the typed document (`DashboardSettings`, serde
  `rename_all = "camelCase"` so the two builds' files are exchangeable), defaults
  declared on the type, `normalize()` on every load and save with the WPF
  store's exact out-of-band rule (reset to the field's default — *not* a silent
  clamp), atomic writes (temp + rename), corrupt files **quarantined**
  (`.settings.corrupt-<timestamp>.json`) with the quarantine reported through
  `LoadOutcome.quarantined`.
- Commands `get_settings` / `save_settings` / `reset_settings` /
  `reveal_settings_folder` (folder, not file — a `.json` would open in whatever
  program JSON is associated with); `app_info` also carries `settingsPath`.
- Frontend: `src/lib/settings.ts` (document shape + the sliders' presentation
  clamps), `src/lib/settings.svelte.ts` (the injected-backend store: load,
  update, reset, reveal; quarantine surfaced; a failed save leaves the document
  untouched), `src/components/SettingsPane.svelte` (Open Folder + Factory Reset
  with the inline confirmation — "Restore every default? No restart is needed." —
  plus the custom-accent colour input).
- Tests: 11 cargo (round-trip/clamp-reset/quarantine/atomic) + 12 vitest
  (fake backend; appearance applied on load; quarantine surfaced; failed save
  inert; defaults parity with `theme.ts`).

**Ticket 07 — Visual system** (completed from the 12-built base):

- `theme.ts`: `nextAccent()` cycles the eight swatches (a hex lands back on
  `Blue` — the switch always lands on a declared value); `parseStoredAccentHex()`
  accepts `#rrggbb` only (three-digit **rejected**, not expanded); `applyAppearance`
  writes a hex accent as `data-accent="Custom"` + `--accent-custom`.
- `app.css`: `[data-accent="Custom"]` derives its companions from the one hex
  with `color-mix` and flips contrast with `oklch(from … calc(1 - l) c h)` — no
  second table of overrides. `--accent-custom` is a registered token
  (`tokens.spec.ts` pins the CSS↔TS parity).
- The header's **Toggle Color** button (App.svelte) and the pane's colour input
  both write through the settings document — the document is the appearance's
  single writer now. `theme.svelte.ts` was rewritten as the document's appearance
  view (no second source of truth, no localStorage drift).

## 3. Environment & protocol facts for the next agent

- **Publish tree** `H:\Repo\komorebi-1click` (WSL `/mnt/h/...`) is the source of
  truth; the dev tree `~/projects/komorebi-1click` carries the scratch copies of
  the issues. The publish `docs/rust-translate/tickets/*.md` mirror the scratch
  `issues/*.md`; update statuses in **both**.
- Building/testing from WSL goes through the Windows host via
  `~/.hermes/scripts/win-exec.sh` (vintage: `Set-Location 'H:\Repo\...\src-tauri';
  & cargo test`). Path from WSL: `real = glob(...)[0]` then
  `H:` + tail — **do not hand-type the crate directory name**; it contains a
  non-ASCII character that transcription has repeatedly mangled (one stray
  directory had to be deleted mid-session).
- The frontend's vitest include is `src/tests/**/*.spec.ts` — specs live under
  `src/tests/`, imports are `../lib/...`.
- Svelte 5 module rules that cost time this session: a module-level `$state`
  export may not be reassigned (use `let x = $state()` privately + exported
  **functions** that read it), and `export function get x()` is invalid syntax —
  the reactive reads are plain functions called from templates/`$derived`.
- Both suites green at commit: **cargo 41** (lib 11 + dispatch 4 + elevation 6 +
  execution_contract 9 + registry 11), **vitest 90/90**, `tsc --noEmit` clean,
  `check-shipped-text.mjs` PASS, `cargo build --release --locked` green
  (3m20s).

## 4. Where `13-verification-regression` stands (automated half)

The ticket's first checkbox names the tests that must exist; current coverage:
cargo settings (11) covers **settings round-trip, clamping/reset, quarantine**;
`tests/dispatch.rs` + `tests/execution_contract.rs` cover **batching, cancel,
timeout, tree kill, argument splitting, script resolution**; `tests/elevation.rs`
covers the **elevation gate ordering and exit 740**; registry completeness is the
registry suite + the PowerShell static suites (kept, still runnable). The
remaining lines (all eight tabs visually confirmed, 100 %/125 % scale,
clean-machine run, sandbox confirmation) are **manual and are Davood's** — do not
check them.

## 5. Known-good constraints that must survive every future ticket

- `settings.json` is the single writer of appearance; nothing else persists
  theme/accent (the ticket-12 localStorage path is retired by design).
- WPF file compatibility: `camelCase` serde names, same directory, same
  normalization rule. A disagreement fails a test, never drifts silently.
- No literal colour values in components; tokens only (`tokens.spec.ts` guards).
- All shipped text is English; the final REPORT to Davood is Persian with English
  technical terms.
- `/mnt/*` stays read-under-approval; commands go through `win-exec.sh`.

## 6. Suggested next session (05→07 done)

1. `09-console-pane`: the drag handle + `consolePercent` persistence from the
   document (the field already round-trips).
2. `08-typography-scale`: Settings-tab controls that write `fontSize`, `uiScale`,
   `consoleFontFamily`, `consoleFontSize` + applying them at startup (the CSS
   tokens already exist).
3. Then `10`, `11`, finish `12`, and let **Davood** close `13` with his manual
   pass — remind him when the last Rust ticket lands so he can run it.

## 7. Session-12 review pass (post-commit note)

A two-axis review (standards + spec, parallel sub-agents) ran over the diff
before commit. Two findings were REAL and fixed in the same commit; four were
mis-reads or judgement calls, recorded here so the next agent does not re-litigate
them:

- **Cross-layer constant drift (real).** `src/lib/settings.ts` mirrored the Rust
  defaults from memory and was wrong on five fields (uiScale, consolePercent,
  consoleFontFamily, consoleFontSize, accentColor) and three bands — a scale
  below 50 that the UI offered was silently reset to 100 on save. Fix: the
  mirror now lists the Rust constants verbatim, and `settings.spec.ts` pins
  every key AND every band against a literal copy of the Rust table ("mirrors
  the Rust constants key by key"). The Rust suite pins the same pair.
- **`reveal_settings_folder` treated explorer's exit code as failure (real).**
  explorer.exe routinely exits 1 having opened the folder; only a failed SPAWN
  is now an error.
- **`parseStoredAccent`'s local swatch list** now imports `ACCENTS` from
  tokens.ts — the table the CSS declares and tokens.spec pins. One list.
- **Theme strings crossing modules as case-shifted primitives** (theme.svelte's
  `'dark' ? 'Light' : 'Dark'`): kept as-is deliberately — a real enum refactor
  is a ticket of its own, and the document is the contract that keeps them
  aligned; noted as the known smell.
