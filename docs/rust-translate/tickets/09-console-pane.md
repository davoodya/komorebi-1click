# 09: Console pane behaviour

**What to build:** One console pane is shared by every tab. It resizes by dragging its top edge
between 10% and 60% of the window, and that height applies to every tab and persists. It auto-scrolls
only while the reader is at the bottom, so scrolling up to read history is never fought. Clear works
mid-run without stopping the run. The status line shows scroll percentage and line count. The buffer
is capped around 200,000 characters, trimming whole lines only, so a huge run cannot grow memory
without bound. The console keeps its own font and size, distinct from the app's.

**Blocked by:** 02 — Execution contract; 04 — Eight tabs rendered from the registry

**Status:** ready-for-agent

- [ ] Dragging the pane edge resizes it, clamped to 10–60%, and the height applies to every tab
- [ ] The chosen height persists across restart
- [ ] Auto-scroll stops while the reader is scrolled up reading history and resumes at the bottom
- [ ] Clear works during an active run and does not cancel it
- [ ] The status line shows scroll percentage and line count
- [ ] A very large output stream stops growing at the cap and trims only on line boundaries
- [ ] The console renders with its own font and size, independent of the app font
