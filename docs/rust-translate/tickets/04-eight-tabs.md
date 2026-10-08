# 04: Eight tabs rendered from the registry

**What to build:** All eight tabs — Start & Stop, Restart, Customization, AutoHotkey, Settings,
Debugging, Uninstall, About — render their rows from the registry through one shared row component
carrying label, help, READ-ONLY badge, inline hint, numeric input filter, per-row current value and
the verb's own action label. Switching tabs preserves console output and never loses scroll.

**Blocked by:** 03 — Registry completeness and the CLI twin

**Status:** ready-for-agent

- [ ] All eight tabs render; each tab's row set matches the registry grouping exactly
- [ ] Every tab uses the same shared row component — no per-tab divergence in row layout
- [ ] The READ-ONLY badge appears on exactly the verbs marked read-only
- [ ] Numeric input filters apply to their row and never launch anything themselves
- [ ] Per-row current value is shown for verbs that report one
- [ ] Switching tabs neither clears nor loses the console output accumulated so far
