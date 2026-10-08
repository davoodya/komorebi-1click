# 06: Settings persistence and the Settings tab

**What to build:** Settings round-trip through a typed document: defaults declared on the type,
normalization on load and save, atomic temp-then-rename writes, and corruption quarantined rather
than silently overwritten. The Settings tab shows its registry rows plus two verbs with custom
actions — Open Folder reveals the containing folder in Explorer, and Factory Reset asks for
confirmation and then restores every default immediately, with no restart.

**Blocked by:** 04 — Eight tabs rendered from the registry

**Status:** ready-for-agent

- [ ] Every settings key round-trips across an application restart; a key absent from the file falls back to its default
- [ ] An out-of-range stored value is clamped on load rather than rejected
- [ ] Saving writes to a temporary file and renames, so an interrupted write cannot produce a torn file
- [ ] A deliberately corrupted settings file is quarantined and reported to the user, never silently replaced with defaults
- [ ] Open Folder opens Explorer at the settings location that is actually in use
- [ ] Factory Reset requires confirmation, then every setting reverts to default and the UI reflects it immediately without restart
