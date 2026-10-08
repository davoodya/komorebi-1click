# 10: AutoHotkey tab

**What to build:** The AutoHotkey tab shows the three shipped scripts from their manifest, annotated
with their real state on disk. Choosing an option stages it; nothing is written until Apply. Apply
writes serially and stops at the first failure, reporting which one failed. The bulk verbs in this tab
re-read state from disk afterwards so the UI reflects what actually happened instead of assuming
success. Diagnostics rows are rendered from the registry like every other row and stream their output.

**Blocked by:** 04 — Eight tabs rendered from the registry; 06 — Settings persistence and the Settings tab

**Status:** ready-for-agent

- [ ] Each script row shows state read from disk at read time, not a cached guess
- [ ] Selecting an option stages it only — no file is written before Apply
- [ ] Apply writes the scripts serially and stops at the first failure, naming the failed script
- [ ] After a bulk verb the rows re-read disk state rather than assuming the write succeeded
- [ ] Diagnostics rows use the shared row component and stream output like any other verb
- [ ] Any generated state persists across restart through the settings document
