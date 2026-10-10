# Handoff — Rust translation track (sessions 1–15)

This document is the handoff for the **Rust/Tauri dashboard translation** track only
(`docs/rust-translate`, tickets `01`–`13`). The installer track has its own
`docs/rust-translate/handoff.md`; this file exists so the two tracks' state can
never be confused. Written 2026-10-11, session 15.

## 0. THE HEADLINE FOR THE NEXT SESSION

**The Rust translation track is CODE-COMPLETE.** Session 15 implemented the last
two tickets — `12-packaged-deliverable` and `13-verification-regression`. The
deliverable is built, published to `releases\rust\`, measured, and the
regression net is green at every level that can run unattended.

**What remains is Davood's manual pass (§1)** — the visual, scale, clean-machine
and sandbox lines — and the installer track's bundling half of ticket 12 (icons
+ the packaged deliverable), which belongs to `docs/rust-translate/handoff.md`.

**Full ticket audit (verified against the code, not memory):**

| Ticket | Status | Evidence |
|---|---|---|
| 01 scaffold + first verb | done | shell, registry, CLI twin, console — all live |
| 02 execution contract | done | `lib.rs` + `tests/dispatch.rs` (4) + `tests/execution_contract.rs` (9) |
| 03 registry / CLI twin | done | registry parity suites |
| 04 eight tabs | done | `App.svelte` + `tabs.spec.ts` |
| 05 elevation | done via installer ticket 12 | gate + exit-740 + relaunch + generated dialog |
| 06 settings | done — session 12 | `settings.rs` (11) + settings store/pane (12) |
| 07 visual system | done — session 12 | `theme.ts`, `app.css` `[data-accent="Custom"]`, Toggle Color |
| 08 typography scale | done — session 13 | `fonts.rs` (5) + `list_installed_fonts`, `fonts.spec.ts` (6), `applyTypography` (+3) |
| 09 console pane | done — session 13 | drag handle + `percentFromDrag` (+3), `consolePercent` persisted |
| 10 AutoHotkey tab | done — session 14 | `ahk.rs` (5) + `list_ahk_scripts`, `ahk.spec.ts` (9), `AutoHotkeyPane.svelte` |
| 11 Customization/About | done — session 14 | `CustomizationPane.svelte`, `AboutPane.svelte` + `about.spec.ts` (4) |
| 12 packaged deliverable | **done — session 15** | `build.rs` (SHA + logo extraction), `crashlog.rs` (2), `public/favicon.ico`, `rust-release-measure.ps1`, pins updated, measured |
| 13 verification/regression | **done — session 15 (automated)** | cargo 53, vitest 117, CLI suite 6/6 on the published EXE, registry parity 11/11, all ps1 suites parse |

## 1. ⚠ TEST OWNERSHIP — READ THIS FIRST

**Davood runs the full test pass himself.** The per-ticket automated suites are
the implementing agent's evidence; the live, visual, scale, clean-machine and
sandbox passes are his, recorded UNCHECKED in `tests-reminded.md`. The track is
now complete — **this is the reminder to run it.**

- The LIVE-MACHINE RULE still holds: never run anything that touches the live
  Komorebi/WHKD/YASB configuration on this Windows host; Windows Sandbox or
  `-DryRun` only.
- `tests/ticket13-publish.tests.ps1` reports ONE failure — "releases/ holds 2
  extra item(s) beside the EXE" — and that is the INSTALLER track's working
  state (`releases\new-installation`, `releases\KomorebiDashboard.exe` = the
  WPF publish), not this track's. The Rust deliverable's own folder
  (`releases\rust\`) holds exactly the EXE + `.gitkeep`.

## 2. What session 15 actually built

**Ticket 12 — the packaged deliverable:**
- `build.rs` — `tauri_build::build()` FIRST (unchanged; dropping it compiles but
  ships a binary that dies before `main` — see §3), then the compile-time
  stamps: `DASHBOARD_GIT_SHA` (commit SHA / `+dirty` / `development`) and the
  logo's 48x48 PNG entry extracted into `OUT_DIR/about-logo.png`.
- `crashlog.rs` — the panic hook appending one record per crash beside the
  executable, naming the action underway (`note_action` + a Drop guard around
  every dispatched run). 2 cargo tests.
- `main.rs` — `crashlog::install()` first thing; `app_info.logoDataUrl` (a
  hand-rolled base64 of the embedded PNG); crate version aligned to the WPF's
  `1.0.0`.
- Frontend — `public/favicon.ico` (the same logo file) linked from `index.html`;
  `AboutPane` shows the logo beside the identity block.
- **Measured and recorded** (`tests/rust-release-pins.json`): runtime-up 544 ms,
  working set 29.5 MB, size 6,642,176 B — inside the 553 ms baseline and the
  18 MB / 45 MB targets. Published EXE hash `c0d0ea05…`.

**Ticket 13 — the regression net (audited, not rebuilt):**
- Every load-bearing assertion area in the ticket maps to a behavior-observing
  test (the suite-by-suite map is in the ticket).
- Ran against the PUBLISHED executable: `rust-ticket01-cli.mjs` 6/6 (help 0,
  unknown 2, override-refused 2, status 0, batched stream, failure 7) and
  `ticket10-registry-parity.tests.ps1` 11/11 (the Rust and C# registries agree
  field-by-field: 35 verbs, 20 fixed-argument rows, 6 tabs).
- All PowerShell suites parse cleanly; the live-machine ones stay sandboxed.
- Roadmap DoD closed line-by-line with cited evidence (below).

## 3. Environment & protocol facts for the next agent

- **A Tauri `build.rs` is not decoration**: the original script was
  `tauri_build::build()` — the call that generates the context
  `generate_context!` embeds. Extending the script without keeping it compiles
  cleanly and produces a binary that dies BEFORE `main` with
  `STATUS_CONTROL_C_EXIT` (0xC000013A). Symptom: help prints nothing, no panic,
  no crash log. Bisect build-script vs source before anything else, and
  `git show HEAD:<crate>/build.rs` is the first thing to read.
- Gates per ticket: `cargo test`, `npx vitest run`, `npx tsc --noEmit`,
  `npm run check` (svelte-check), `node tests/check-shipped-text.mjs`,
  `cargo tauri build --no-bundle -- --locked`, and `tests/rust-release-measure.ps1`
  to publish (it updates nothing — feed its JSON into the pins file).
- Rebuild + republish means: update `sizeBytes`, `sha256`, `builtAt` in
  `tests/rust-release-pins.json` and NOWHERE else (the sandbox suite §T13 reads
  that file).
- The measure script's runtime-up probe exists because a GUI window launched
  from this bridge renders on another desktop — polling `MainWindowHandle`
  reports a false timeout. Window-latency is a desktop measurement (Davood's).
- Stores: `busy()`, `loaded()`, `status()`, `settingsPath()` are exported
  FUNCTIONS; `settingsDocument` / `console_` are `$state` objects.
- Svelte 5: no reassigned exported `$state`; `export function get x()` is invalid.
- All shipped text is English; the final REPORT to Davood is Persian with English
  technical terms.
- Full suite state at session-15 commit: cargo **53/53** (crashlog 2 new),
  vitest **117/117**, tsc clean, svelte-check **0 errors** (5 warnings — the
  known ARIA-separator pair and the About author anchor), shipped-text PASS,
  release build green, CLI suite 6/6 on the published EXE, registry parity 11/11.

## 4. Roadmap definition of done — closed with evidence

| Roadmap DoD line | Evidence |
|---|---|
| All 8 tabs render and every one of the 35 verbs dispatches through the same registry | registry suite (35 verbs, one registry; the GUI/CLI row agreement test) + `tabs.spec.ts`; the visual render is Davood's pass |
| CLI twin: `--help` generated from the registry; exit codes 0 / script / 740 / 2 / 127 proven | `help_is_generated_from_the_table…`, `a_missing_script_reports_127…`, `the_refusal_is_a_structured_result…` (740), CLI suite (0/2/7) |
| `demo-stream` proves streaming with a responsive UI; cancel and timeout each kill the tree | `a_high_line_count_run_stays_batched…`, `cancel_stops_the_child…`, `a_run_that_overruns_its_budget…`, `no_process_survives_a_stop…`, CLI suite's 30-chunk stream |
| Elevation dialog matches ADR-0012 exactly; gate ordering asserted by a test | `elevation.rs` (6) — gate names the registry's features, ordering, structured refusal |
| Settings round-trip, quarantine and Factory Reset behave as the WPF build does | `every_settings_key_round_trips_across_a_restart`, `a_corrupt_file_is_quarantined_not_silently_replaced`, `a_quarantined_load_then_save_keeps_the_quarantine` |
| Theme/accent/typography/console settings all persist and apply **before** first paint | the settings store applies the document before the shell renders; the typography/console suites pin the writers |
| Size, RAM and startup measured against §0 and reported | 6.33 MB / 29.5 MB / 544 ms runtime-up vs 18 MB / 45 MB / 553 ms |
| No `.ps1` script was modified | the track touched no script; `git status` shows the only foreign script edits belong to other sessions |

## 5. Known-good constraints that must survive every future change

- `settings.json` is the single writer of appearance, typography, console height
  and the AHK state mirror; the disk `ahk-state.json` remains the scripts' own
  state and wins on disagreement.
- WPF file compatibility: `camelCase` serde names, same directory, same
  normalization rule — a disagreement fails a test, never drifts silently.
- No literal colours in components; tokens only. One typography writer; the
  console height lives in the settings document.
- The font sentinel is a picker ACTION, never a persisted value.
- New backend actions that take a destination are CLOSED ENUMS the backend
  resolves (`reveal_folder`, `open_link`).
- Success is the backend's three verdict facts (exit 0, not cancelled, not
  timed-out). Preview is not persistence.
- `build.rs` keeps `tauri_build::build()` first — always.
- All shipped text is English; the final report to Davood is Persian.

## 6. Suggested next session

1. **Remind Davood to run his manual pass** — `tests-reminded.md` §session 15
   is the script (eight tabs at 100 %/125 %, the icon in all four places in the
   running window, a deliberate crash's log, clean-machine first launch).
2. Finish ticket 12's installer bundling in the INSTALLER track
   (`docs/rust-translate/handoff.md` owns that).
