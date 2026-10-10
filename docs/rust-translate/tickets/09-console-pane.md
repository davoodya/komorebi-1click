# 09: Console pane behaviour

**What to build:** One console pane is shared by every tab. It resizes by dragging its top edge
between 10% and 60% of the window, and that height applies to every tab and persists. It auto-scrolls
only while the reader is at the bottom, so scrolling up to read history is never fought. Clear works
mid-run without stopping the run. The status line shows scroll percentage and line count. The buffer
is capped around 200,000 characters, trimming whole lines only, so a huge run cannot grow memory
without bound. The console keeps its own font and size, distinct from the app's.

**Blocked by:** 02 — Execution contract; 04 — Eight tabs rendered from the registry

**Status:** implemented — 2026-10-11 (session 13), completing the session-12 base. Automated checks
green.

## What was built

Carried over from tickets 01–06: batching, the pinned autoscroll (a batch is what drives the scroll,
so a reader scrolled up is never fought), cancel, the status line, and the 200 000-character cap that
trims on whole lines only.

Session 13 finished the two remaining halves:

- **The drag handle** (`ConsolePane.svelte`): a 6px strip on the pane's top edge,
  `role="separator"` with `aria-valuenow`/`aria-valuemin`/`aria-valuemax`, pointer capture so the
  drag never leaves the handle, and the arrow keys nudge ±5% for pointer-free resizing. The
  geometry is the pure `percentFromDrag(containerTop, containerHeight, clientY)` in
  `console.svelte.ts`: the pointer's offset from the TAB BODY's top clamped to 10–60 (a degenerate
  rect returns the default instead of NaN — `console.spec.ts` pins it).
- **Persistence**: the height lives in the settings document's `consolePercent` — the drag writes it
  through `updateSettings` on pointer-up (only when it actually changed), and `App.svelte`'s
  applier applies it from the document at startup. One writer, one reader, every tab.
- **The console's own font and size**: ticket 08's `applyTypography` writes `--console-font` /
  `--console-font-size`, which the console's rules already consumed, so the console keeps its face
  and size independently of the app font's.

## Checks

- [x] Dragging the pane edge resizes it, clamped to 10–60%, and the height applies to every tab
  (the percent is store state shared by every tab; `percentFromDrag` + the clamp suite pinned)
- [x] The chosen height persists across restart (written through the settings document;
  `console.spec.ts` pins the clamp and the store's round-trip pins the field)
- [x] Auto-scroll stops while the reader is scrolled up reading history and resumes at the bottom
  (the `atEnd` watcher, pinned by the console suite)
- [x] Clear works during an active run and does not cancel it (the Clear action only resets the
  console store; cancel is a separate command)
- [x] The status line shows scroll percentage and line count (both are live in the footer's status
  line and pinned in the status suite)
- [x] A very large output stream stops growing at the cap and trims only on line boundaries
  (`appendLine`'s trim is on `\n` boundaries; the cap suite pins the length and that no line is cut)
- [x] The console renders with its own font and size, independent of the app font (the two CSS
  properties are written from separate document fields; `theme.spec.ts` pins the writer)
