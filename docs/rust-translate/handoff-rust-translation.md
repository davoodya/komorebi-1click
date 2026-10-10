# Handoff — Rust translation track (sessions 1–14)

This document is the handoff for the **Rust/Tauri dashboard translation** track only
(`docs/rust-translate`, tickets `01`–`13`). The installer track has its own
`docs/rust-translate/handoff.md`; this file exists so the two tracks' state can
never be confused. Written 2026-10-11, session 14.

## 0. THE HEADLINE FOR THE NEXT SESSION

**Two tickets were implemented in session 14: `10-autohotkey-tab` and
`11-customization-about`** — the last two un-implemented track tickets. Every
Rust-translate ticket now has code plus automated evidence. What remains:

1. **Ticket `12`'s bundling half** — the release build and pins exist; the
   installer bundling (icons + the packaged deliverable) is the installer
   track's, finish it there.
2. **Ticket `13`'s manual pass — Davood's** (§1). When he is ready, he runs
   the full test pass recorded in `tests-reminded.md`.

**Full ticket audit (verified against the code, not memory):**

| Ticket | Status | Evidence |
|---|---|---|
| 01 scaffold + first verb | done | shell, registry, CLI twin, console — all live |
| 02 execution contract | done | `lib.rs` + `tests/dispatch.rs` (4) + `tests/execution_contract.rs` (9) |
| 03 registry / CLI twin | done | registry parity suites |
| 04 eight tabs | done | `App.svelte` + `tabs.spec.ts` |
| 05 elevation | **done via installer ticket 12** (sessions 10–11) | gate + exit-740 + relaunch + generated dialog |
| 06 settings | done — session 12 | `settings.rs` (11 cargo) + settings store/pane (12 vitest) |
| 07 visual system | done — session 12 | `theme.ts` hex/cycle, `app.css` `[data-accent="Custom"]`, Toggle Color |
| 08 typography scale | done — session 13 | `fonts.rs` (5 cargo) + `list_installed_fonts`, `fonts.ts`/`fonts.spec.ts` (6), `theme.ts` `applyTypography` (+3), `TypographyControls.svelte` |
| 09 console pane | done — session 13 | drag handle + `percentFromDrag` (+3 console tests), `consolePercent` persisted through the document, console font/size from the document |
| 10 AutoHotkey tab | **done — session 14** | `ahk.rs` (5 cargo) + `list_ahk_scripts`, `ahk.svelte.ts` + `ahk.spec.ts` (9), `onRunFinished`/`runSucceeded` seam, `AutoHotkeyPane.svelte` |
| 11 Customization/About | **done — session 14** | `CustomizationPane.svelte` (swatches + theme + console slider + reused TypographyControls + Apply/Reset), `AboutPane.svelte` + `about.ts`/`about.spec.ts`, `app_info` exePath/runtime, `reveal_folder`/`open_link` closed-enum commands |
| 12 packaged deliverable | partial | release build + pins exist (installer t13); installer bundling remains |
| 13 verification/regression | partial | automated coverage exists (§4); the rest is **Davood's manual pass** |

**The Rust translation track's code is COMPLETE.** Remind Davood so he runs
§1's full test pass.

## 1. ⚠ TEST OWNERSHIP — READ THIS FIRST

**Davood runs the full test pass himself.** He has stated this as a standing
answer (2026-10-11, sessions 12–14): the tests as a whole are executed by him
at the end of the Rust translate work — **remind him when the translation is
finished**, and until then do not claim the translation is "tested" beyond the
automated evidence each ticket leaves.

- Automated suites (cargo/vitest/tsc/svelte-check/static) ARE run per ticket
  and must be green before a ticket is marked done — that is the ticket's
  evidence.
- The end-to-end passes — every tab clicked in the built executable, 100 % and
  125 % scale on the portrait monitor, a clean-machine first launch, elevation
  UAC accept/decline, and anything that touches the live Komorebi/WHKD/YASB
  stack — are **Davood's manual pass**, recorded UNCHECKED in
  `tests-reminded.md`.
- The LIVE-MACHINE RULE still holds: never run anything that touches the live
  Komorebi/WHKD/YASB configuration on this Windows host; Windows Sandbox or
  `-DryRun` only.

## 2. What session 14 actually built

**Ticket 10 — AutoHotkey tab:**

- `src-tauri/src/ahk.rs` — the manifest transcribed from
  `scripts/Install-Common.ps1` (order and per-script interpreter pinned), the
  state file at `<repo>\autohotkey\ahk-state.json` (the scripts directory's
  sibling — the installer's own rule), missing/unreadable = all enabled,
  manifest keys only, real JSON bools only. 5 cargo tests.
- `list_ahk_scripts` serves manifest + CURRENT disk state; the pane re-reads at
  open and after every bulk verb — the tab never shows a cached guess.
- `ahk.svelte.ts` — the selection/applied split, serial Apply stopping at the
  first failure (reverting the failed row and naming it), persistence through
  the settings document's `ahkScriptStates`. Injected seams; 9 vitest.
- `dispatch.ts` gained `onRunFinished` (the completion seam) and
  `runSucceeded` (exit 0 AND not cancelled AND not timed-out). Bulk verbs are
  the registry's own rows through the shared `VerbRow`; completion triggers the
  re-read.
- `AutoHotkeyPane.svelte` — three staged rows + the registry's bulk and
  diagnostic rows through the shared component; `App.svelte` routes the tab to
  it.

**Ticket 11 — Customization + About:**

- `CustomizationPane.svelte` — theme toggle, eight accent swatches + custom
  colour input, console-height slider bound to the shared pane, ticket 08's
  `TypographyControls` reused, Apply Settings + Reset to defaults. Preview
  live; the pane-local state persists through the settings document.
- `AboutPane.svelte` + `about.ts` — product, version + Git SHA, exe path,
  scripts/settings paths, runtime; copy-to-clipboard; open-folder for the
  three paths; site/repository links.
- `app_info` gained `exePath` and `runtimeDescription`. Two new CLOSED-ENUM
  commands: `reveal_folder(scripts|settings|exe)` and
  `open_link(site|repository)` — a path or URL parameter from the frontend
  would be an injection surface for no benefit, and `open_link` spawns `https://`
  URLs only. `about.spec.ts` pins the version line and the copy line.

## 3. Environment & protocol facts for the next agent

- Publish tree `H:\Repo\komorebi-1click` is the source of truth; the dev tree
  `~/projects/komorebi-1click` carries the scratch trackers. Ticket statuses
  are mirrored in **both** trees.
- Builds/tests go through `~/.hermes/scripts/win-exec.sh`; resolve project
  paths in python (`real = glob(...)[0]`, then `H:` + tail) — the crate
  directory name contains a non-ASCII character transcription keeps mangling.
- Gates per ticket: `cargo test`, `npx vitest run`, `npx tsc --noEmit`,
  `npm run check` (**svelte-check** — it catches template type errors `tsc`
  cannot), `node tests/check-shipped-text.mjs`, `cargo tauri build --no-bundle
  -- --locked`.
- Store conventions (from sessions 12–13, still true): `busy()`, `loaded()`,
  `status()`, `settingsPath()` are exported FUNCTIONS; `settingsDocument` and
  `console_` are `$state` objects. A union status is read once into a const so
  the switch narrows it.
- Injection seams: the settings store and the AHK store take their backend/
  runner through `configure…`/`set…` seams, so the suites drive the shipped
  stores in plain node and Tauri is exercised by the built executable.
- Svelte 5 module rules: no reassigned exported `$state`, no
  `export function get x()`; reactive reads are plain functions.
- Rust doc fences compile: non-runnable examples are fenced ```text.
- All suites green at session-14 commit: **cargo 51/51** (ahk 5, fonts 5,
  settings 11, dispatch 4, elevation 6, execution_contract 9, registry 11),
  **vitest 117/117** (ahk 9, fonts 6, about 4, theme +3, console +3 new since
  session 12's 90), tsc clean, svelte-check 0 errors (4 warnings — the two
  known pre-existing ones plus the ARIA separator pair), shipped-text PASS,
  release build green (1m56s).

## 4. Where `13-verification-regression` stands (automated half)

Coverage that exists: cargo settings (11) — settings round-trip/clamp/
quarantine; `dispatch.rs` + `execution_contract.rs` (13) — batching, cancel,
timeout, tree kill, argument splitting, script resolution; `elevation.rs` (6)
— gate ordering and exit 740; `ahk.rs` (5) — the manifest, the state file,
the corrupt-file default; `fonts.rs` (5) — the registry parse. Frontend:
console/typography/ahk/about suites pin the clamp band, the sentinel
semantics, the typography writer, the AHK apply contract, and the About copy
line. The remaining lines (all eight tabs visually confirmed, 100 %/125 %
scale, clean-machine run, sandbox confirmation, every button clicked in the
built executable) are **manual and are Davood's** — do not check them.

## 5. Known-good constraints that must survive every future ticket

- `settings.json` is the single writer of appearance, typography, console
  height and the AHK state mirror; nothing else persists them. The disk
  `ahk-state.json` remains the SCRIPTS' own state — the document is the UI's
  mirror, and the disk wins on disagreement.
- WPF file compatibility: `camelCase` serde names, same directory, same
  normalization rule. A disagreement fails a test, never drifts silently.
- No literal colour values in components; tokens only. The typography
  writer's CSS properties are one seam; the console height lives in the same
  document.
- The font sentinel is a picker ACTION, never a persisted value; tier 1 opens
  instantly; the enumeration happens once, off the UI thread.
- New backend actions that take a destination are CLOSED ENUMS the backend
  resolves (`reveal_folder`, `open_link`) — never a path or URL string from
  the frontend.
- Preview is not persistence; success is the backend's three verdict facts
  (exit 0, not cancelled, not timed-out), not a plausible guess.
- All shipped text is English; the final REPORT to Davood is Persian with
  English technical terms.
- `/mnt/*` stays read-under-approval; commands go through `win-exec.sh`.

## 6. Suggested next session

The track's implementation is complete. What is left:

1. Finish ticket `12`'s installer bundling in the installer track
   (`docs/rust-translate/handoff.md` owns that).
2. **Remind Davood** that the Rust translation is complete so he runs his
   full test pass (§1) — his `tests-reminded.md` manual list is the script.

## 7. Session-14 review notes (post-commit)

- A `write_file`/patch of `ipc.ts` earlier in the session was lost between
  the in-memory edit and its write; `svelte-check` caught the missing exports
  immediately. Run the gates after every edit batch, not only at the end of a
  ticket — the per-ticket gate set in §3 is cheap and it is the only thing
  that caught this.
- The pane wiring order matters: a child component's `onMount` runs BEFORE
  the shell's, so a pane that needs the registry looks its verbs up in an
  `$effect` (once), not in `onMount`.
- The AHK store's runner seam builds lazily from the registry verbs; changing
  the verb table resets the cached runner (`setAhkVerbs`), or the first apply
  would close over stale verbs.
