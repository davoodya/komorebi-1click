# 05: Elevation (ADR-0012)

**What to build:** Clicking an administrative verb from an unelevated window shows the `Rerun as
Administrator` dialog with exactly three actions — OK, Rerun as Administrator, Cancel — and a feature
list **generated** from the registry's admin flags rather than written by hand. On confirmation the
app relaunches elevated and the old instance exits, so only one window exists. In the CLI the same
gate is checked before any launch and refuses with exit 740. Declining UAC is a choice, not a failure:
the app stays open, unelevated, fully usable.

**Blocked by:** 04 — Eight tabs rendered from the registry

**Status:** ready-for-agent

- [ ] The elevation gate is evaluated before launch — no administrative script ever starts unelevated (ordering assertion)
- [ ] The dialog's feature list is generated from the admin flags of the registered verbs, so it can never drift from reality
- [ ] The dialog shows exactly three actions with the title `Rerun as Administrator`
- [ ] On confirmation the app relaunches elevated and the old instance exits — no duplicate window
- [ ] Declining UAC returns cleanly to the unelevated window with no error state
- [ ] CLI: an administrative verb dispatched unelevated exits 740 and launches nothing
- [ ] The token probe does not use process access escalation (ADR-0016)
