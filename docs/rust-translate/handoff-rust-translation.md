# Handoff — Rust translation track (sessions 1–13)

This document is the handoff for the **Rust/Tauri dashboard translation** track only
(`docs/rust-translate`, tickets `01`–`13`). The installer track has its own
`docs/rust-translate/handoff.md`; this file exists so the two tracks' state can
never be confused. Written 2026-10-11, session 13.

## 0. THE HEADLINE FOR THE NEXT SESSION

**Two tickets were implemented in session 13: `08-typography-scale` and
`09-console-pane`** (the two session 12 named as the next work, in the order
Davood asked for). Every Rust-translate ticket except `10`, `11`, the installer
bundling half of `12`, and Davood's own manual pass on `13` now has code and
automated evidence:

| Ticket | Status | Evidence |
|---|---|---|
| 01 scaffold + first verb | done | shell, registry, CLI twin, console — all live |
| 02 execution contract | done | `src-tauri/src/lib.rs` + `tests/dispatch.rs` (4) + `tests/execution_contract.rs` (9) |
| 03 registry / CLI twin | done | registry parity suites |
| 04 eight tabs | done | `App.svelte` + `tabs.spec.ts` |
| 05 elevation | **done via installer ticket 12** (sessions 10–11) | gate + exit-740 + relaunch + generated dialog; ticket-12's static suite 48/48 |
| 06 settings | done — session 12 | `src-tauri/src/settings.rs` (11 cargo tests) + `settings.ts` / `settings.svelte.ts` / `SettingsPane.svelte` (12 vitest) |
| 07 visual system | done — session 12 | `theme.ts` hex/cycle additions, `app.css` `[data-accent="Custom"]`, Toggle Color button |
| 08 typography scale | **done — session 13** | `src-tauri/src/fonts.rs` (5 cargo tests, one live-registry) + `list_installed_fonts` command, `src/lib/fonts.ts` + `fonts.spec.ts` (6), `theme.ts` `applyTypography` (+3 theme tests), `TypographyControls.svelte` rendered by `SettingsPane` |
| 09 console pane | **done — session 13** (completing the 01–06 base) | drag handle + `percentFromDrag` (+3 console tests), `consolePercent` persisted through the document and applied at startup, console font/size from the document |
| 10 AutoHotkey tab | not implemented | — |
| 11 customization/about | not implemented | — |
| 12 packaged deliverable | partial | release build + pins exist (installer t13); icons/installer bundling remain |
| 13 verification/regression | partial | automated coverage exists (§4); **the visual/scale/clean-machine/elevation confirmations are Davood's manual pass** |

**Remaining work order:** `10-autohotkey-tab` → `11-customization-about` →
finish `12`'s bundling → then **tell Davood the Rust translation is complete so
he runs his full test pass** (§1) — including the 125 % visual check on the
portrait monitor that ticket 08 leaves to him.

## 1. ⚠ TEST OWNERSHIP — READ THIS FIRST

**Davood runs the full test pass himself, after the Rust translation is
complete.** He stated this as a standing answer (2026-10-11, session 12) and
re-confirmed it for this pair of tickets (session 13): tests as a whole are
executed by him at the end of the Rust translate work — **remind him when the
translation is finished**, and until then do not claim the translation is
"tested" beyond the automated evidence each ticket leaves.

What that means for the implementing agent:
- Automated suites (cargo/vitest/tsc/svelte-check/static) ARE run per ticket and must be green
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

## 2. What session 13 actually built

**Ticket 08 — Typography and UI scale** (preview live, persist on Apply — the
WPF's Settings tab without the WPF's dialog):

- `src-tauri/src/fonts.rs` — the installed-font enumeration with **no new
  dependency** (the WPF calls `Fonts.SystemFontFamilies` via DirectWrite; this
  crate has no DirectWrite binding). Both `HKLM` and `HKCU` `...\Fonts` keys
  through `reg query`, face names parsed by dropping the key header and the file
  descriptor, trailing parenthesized type tokens stripped **in a loop** (the
  registry writes e.g. `110_Besmellah_1(MRT) (TrueType)`), case-folded dedupe
  (HKLM + per-user both list Segoe UI), case-folded sort. Known trade-off,
  documented in the module: registry granularity is FACE-level, so multi-face
  families appear once per face — the tier-1 standard list covers the common
  families. 5 cargo tests, including one that observes the live registry and
  asserts the shape (deduped, sorted, no trailing descriptor), never a fixed
  list. The Tauri command is `async` — the enumeration runs off the UI thread.
- `src/lib/fonts.ts` — the standard tier in the WPF's exact order with the mono
  faces spliced mid-list, `ALL_FONTS_SENTINEL = "Custom (All Fonts)..."` last in
  both lists, and `enumerateInstalledFonts()` behind a module-level promise so
  it happens **once** and later opens are instant. `fonts.spec.ts` (6 tests)
  pins: sentinel last, sentinel never applied, mono ⊆ standard exactly once,
  console list monospaced-only.
- `src/lib/theme.ts` — `applyTypography(root, values)` writes the five CSS
  properties the sheet already declares; `scaleMultiplier(100|125|150)` → the
  unitless `--ui-scale` the CSS multiplies by (never zero); a monospaced /
  sans-serif fallback rides under the chosen face. `theme.svelte.ts`'s applier
  calls it on every document load, so the document applies typography like
  theme and accent. `theme.spec.ts` gained 3 tests.
- `src/components/TypographyControls.svelte` — five controls in the Settings tab.
  A change writes the CSS properties immediately (preview; the document is
  untouched); **Apply** writes all five through one `updateSettings`; **Revert**
  re-reads the document. The sentinel option triggers the cached enumeration and
  is never itself applied — after it fires, the previous real font stays
  selected.

**Ticket 09 — console pane** (the session-12 base plus the two remaining halves):

- The drag handle: a 6px strip on the pane's top edge, `role="separator"` with
  the live `aria-valuenow`/min/max, pointer capture (the drag never leaves the
  handle), arrow keys ±5%. Geometry is the pure
  `percentFromDrag(containerTop, containerHeight, clientY)` — the pointer's
  offset from the TAB BODY, clamped to 10–60; a degenerate rect returns the
  default instead of NaN (pinned by 3 new `console.spec.ts` tests).
- Persistence: `consolePercent` is a settings-document field (ticket 06) — the
  drag writes it on pointer-up only when it changed, and `App.svelte`'s applier
  applies it at startup. One writer, one reader, identical on every tab.
- The console's own font and size come from ticket 08's `--console-font` /
  `--console-font-size`, written from separate document fields.

## 3. Environment & protocol facts for the next agent

- **Publish tree** `H:\Repo\komorebi-1click` (WSL `/mnt/h/...`) is the source of
  truth; the dev tree `~/projects/komorebi-1click` carries the scratch copies of
  the issues. The publish `docs/rust-translate/tickets/*.md` mirror the scratch
  `issues/*.md`; update statuses in **both**.
- Building/testing from WSL goes through the Windows host via
  `~/.hermes/scripts/win-exec.sh` (vintage: `Set-Location 'H:\Repo\...\src-tauri';
  & cargo test`). Path from WSL: `real = glob(...)[0]` then
  `H:` + tail — **do not hand-type the crate directory name**; it contains a
  non-ASCII character that transcription has repeatedly mangled.
- The frontend's gates are `npm run check` (**svelte-check — it catches template
  type errors `tsc --noEmit` cannot**) and `npx vitest run` (include is
  `src/tests/**/*.spec.ts`). `SettingsPane`'s `status` is a FUNCTION
  (`status()`) while `settingsDocument` is a `$state` object — call the
  function-shaped exports (`busy()`, `loaded()`, `status()`), read the object
  ones. A union status must be read once into a const so the switch narrows it.
- Svelte 5 module rules that cost time: a module-level `$state` export may not
  be reassigned (private `let` + exported functions), and `export function get
  x()` is invalid — reactive reads are plain functions.
- Rust doc-comment fences are compiled: a `` ``` `` example block runs as a
  doctest, so non-runnable examples must be fenced as `` ```text ``.
- Both suites green at commit: **cargo 46** (fonts 5, settings 11, dispatch 4,
  elevation 6, execution_contract 9, registry 11) — the five fonts tests are the
  new ones; **vitest 104/104** (fonts 6, theme +3, console +3 are new),
  `tsc --noEmit` clean, `npm run check` 0 errors (4 warnings — two on the new
  separator, two pre-existing on `ElevationDialog`), release build green
  (2m06s).

## 4. Where `13-verification-regression` stands (automated half)

The ticket's first checkbox names the tests that must exist; current coverage:
cargo settings (11) covers **settings round-trip, clamping/reset, quarantine**;
`tests/dispatch.rs` + `tests/execution_contract.rs` cover **batching, cancel,
timeout, tree kill, argument splitting, script resolution**; `tests/elevation.rs`
covers the **elevation gate ordering and exit 740**; `tests/fonts.rs` (in-module)
pins the **registry parse**; the vitest console/typography suites pin the
**clamp band, sentinel semantics, and the typography writer**. The remaining
lines (all eight tabs visually confirmed, 100 %/125 % scale, clean-machine run,
sandbox confirmation) are **manual and are Davood's** — do not check them.

## 5. Known-good constraints that must survive every future ticket

- `settings.json` is the single writer of appearance AND typography; nothing
  else persists theme/accent/font/scale. The console's height is a field of the
  same document.
- WPF file compatibility: `camelCase` serde names, same directory, same
  normalization rule. A disagreement fails a test, never drifts silently.
- No literal colour values in components; tokens only (`tokens.spec.ts` guards).
  The typography writer's five CSS properties are the same seam — one writer.
- The font sentinel is a picker ACTION, never a persisted value; tier 1 opens
  instantly and the enumeration happens once, off the UI thread.
- Preview is not persistence: typography previews write CSS properties only;
  the document moves on Apply.
- All shipped text is English; the final REPORT to Davood is Persian with English
  technical terms.
- `/mnt/*` stays read-under-approval; commands go through `win-exec.sh`.

## 6. Suggested next session

1. `10-autohotkey-tab`.
2. `11-customization-about`.
3. Finish `12`'s bundling (icons + installer).
4. When the last Rust ticket lands: **remind Davood** that the Rust translation
   is complete so he runs his full test pass (§1) — including ticket 08's 125 %
   visual check on the portrait monitor.

## 7. Session-13 review note (post-commit)

Session 13 was reviewed inside the same commit. What it caught, so the next
agent does not re-learn it:

- **`status` is a function** (`SettingsPane` read `status.file` / `status.message`
  without the call — a real type error `svelte-check` caught and `tsc` cannot,
  because it is a template). Fixed by reading the status once into a const and
  narrowing the union inside the switch. Run `npm run check`, not just `tsc`.
- The shipped convention for the settings store is mixed: `busy()`, `loaded()`,
  `status()` are functions; `settingsDocument` is a `$state` object. Importing
  the function-shaped ones as values compiles nowhere useful — call them.
- The live registry contains faces with parenthesized groups inside their own
  names (`2  Mitra_1 (MRT)Bold`); the strip is a loop of trailing descriptors
  only, and the test asserts what is actually gone (a TRAILING descriptor), not
  "no parens anywhere".
- The console handle is a `role="separator"` div with `tabindex="0"` — the ARIA
  window-splitter pattern. `svelte-check`'s a11y warnings about it are expected
  noise, recorded here so they are not "fixed" into a worse widget.

