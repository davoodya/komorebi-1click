# 10: AutoHotkey tab

**What to build:** The AutoHotkey tab shows the three shipped scripts from their manifest, annotated
with their real state on disk. Choosing an option stages it; nothing is written until Apply. Apply
writes serially and stops at the first failure, reporting which one failed. The bulk verbs in this tab
re-read state from disk afterwards so the UI reflects what actually happened instead of assuming
success. Diagnostics rows are rendered from the registry like every other row and stream their output.

**Blocked by:** 04 — Eight tabs rendered from the registry; 06 — Settings persistence and the Settings tab

**Status:** implemented — 2026-10-11 (session 14).

## What was built (session 14)

- `src-tauri/src/ahk.rs` — the manifest (transcribed from `scripts/Install-Common.ps1`, in its
  order, interpreter pinned per script) and the state read: `ahk-state.json` lives at
  `<repo root>\autohotkey\` (the scripts directory's sibling, the installer's own rule), a
  missing or unreadable file means **everything enabled** (the installer's default), only
  manifest keys are honoured, and only a real JSON bool counts. 5 cargo tests, including the
  live-registry shape and the corrupt-file default.
- `list_ahk_scripts` — the command serves the manifest plus the CURRENT disk state; the pane
  calls it at open time and again after every bulk verb, so the rows never show a cached guess.
- `src/lib/ahk.svelte.ts` — the row model (selection separate from applied state, exactly like
  the WPF's `AhkScriptRow`), the serial Apply that stops at the first failure and reverts the
  failed row, and the persistence through the settings document's `ahkScriptStates` (the UI's
  mirror; the disk state file remains the scripts' own). Both seams are injected — the suite
  drives the shipped store in plain node (9 tests).
- `src/lib/dispatch.ts` — a run-completion seam (`onRunFinished`) plus `runSucceeded` (success
  needs exit 0 AND not cancelled AND not timed-out). The bulk verbs are the registry's own rows
  rendered through the shared `VerbRow`; their completion is what triggers the re-read.
- `src/components/AutoHotkeyPane.svelte` — the three staged rows (hotkey badge, interpreter,
  status line), the Apply button with its hint, and the registry's bulk + diagnostic rows
  through the shared row component. `App.svelte` routes the tab to it, so the tab renders
  exactly one surface.

## Checks

- [x] Each script row shows state read from disk at read time, not a cached guess
      (`list_ahk_scripts` re-read per open AND after every bulk verb; the re-read test pins
      that a bulk flip on disk replaces the staged selection)
- [x] Selecting an option stages it only — no file is written before Apply (the radio pair
      moves the selection; `appliedEnabled` only changes after a successful run)
- [x] Apply writes the scripts serially and stops at the first failure, naming the failed
      script (the serial order, the stop, the revert and the naming are pinned by the spec)
- [x] After a bulk verb the rows re-read disk state rather than assuming the write succeeded
      (`onRunFinished` → `refreshAfterBulkVerb`)
- [x] Diagnostics rows use the shared row component and stream output like any other verb
      (`ahk-versions` / `ahk-newfile-check` / `ahk-diagnose` render through `VerbRow`)
- [x] Any generated state persists across restart through the settings document
      (`updateSettings({ ahkScriptStates })`; the document's round-trip suite pins the field)
