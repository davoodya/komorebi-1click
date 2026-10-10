# 04: Eight tabs rendered from the registry

**What to build:** All eight tabs — Start & Stop, Restart, Customization, AutoHotkey, Settings,
Debugging, Uninstall, About — render their rows from the registry through one shared row component
carrying label, help, READ-ONLY badge, inline hint, numeric input filter, per-row current value and
the verb's own action label. Switching tabs preserves console output and never loses scroll.

**Blocked by:** 03 — Registry completeness and the CLI twin

**Status:** done — 2026-10-10, session 7

- [x] All eight tabs render; each tab's row set matches the registry grouping exactly
- [x] Every tab uses the same shared row component — no per-tab divergence in row layout
- [x] The READ-ONLY badge appears on exactly the verbs marked read-only
- [x] Numeric input filters apply to their row and never launch anything themselves
- [x] Per-row current value is shown for verbs that report one
- [x] Switching tabs neither clears nor loses the console output accumulated so far

## Evidence (2026-10-10)

Shipped in the session-7 rust ticket-04 commit (2026-10-10, on `main`, pushed).

- **Runtime, in the built EXE (12/12 UIA assertions):**
  `docs/rust-translate/evidence/ticket04-eight-tabs-uia.md` — the strip draws
  exactly the eight declared tabs in the backend's order (`Kill and Start >
  Restart and Reloading > Settings > Customization > AutoHotkey Scripts >
  Debugging > Uninstall and Cleanup > About`), opens on the first tab marked
  selected, selecting Debugging re-renders the panel from that tab's own rows
  and moves the selection, the About surface renders the empty row state, and a
  finished run's console is byte-identical across the switch (32 lines before,
  32 after).
- **Unit:** `src/tests/tabs.spec.ts` (10 tests — selection resolution, the
  first-tab fallback for a stale id, the empty registry, and the grouping
  covering every rendered verb exactly once across all eight tabs);
  `src/tests/format.spec.ts` (`filterNumericValue`, ASCII digits only, empty
  stays empty, and the filtered value is what reaches the script through
  `parseArguments`).
- **Suites:** cargo 24 passed · `npm test` 63 passed (7 files) ·
  `svelte-check` 0 errors 0 warnings · build.ps1 four phases exit 0 (EXE
  sha256 8ea3c3d1fe18ee4f...) · shipped-text 202 files PASS.

## Notes

- The row component is unchanged in shape: every tab's rows come from the same
  `rowsForTab` filter into the same `VerbRow`, so there is no per-tab rendering
  path to diverge. The READ-ONLY badge is still rendered from `verb.isReadOnly`
  only, and the numeric box still filters the VALUE (extracted to
  `filterNumericValue` in `lib/format.ts`), never a keystroke hook.
- "Per-row current value" is the roadmap R08 per-row value: the row's own value
  box, owned per row (`RowState.value`), shown for verbs that take one.
- Tab selection lives in `lib/registry.svelte.ts` (`tabSelection` +
  `resolveActiveTab`), not in the component, so the strip and the panel resolve
  the same id and a stale selection can never blank the shell.
