# 11: Customization tab and About tab

**What to build:** The complete Customization surface — accent swatches, theme toggle, app font and
console font pickers, font size, UI scale and console height sliders, Apply Settings and
Reset-to-defaults — previews every change live without touching persisted settings, and persists them
only on Apply. The About tab reports application identity, version, the executable, scripts and
settings paths, and a runtime description, with working copy-to-clipboard, open-folder and URL actions.

**Blocked by:** 06 — Settings persistence; 07 — Visual system; 08 — Typography and UI scale

**Status:** ready-for-agent

- [ ] Every appearance control previews live and writes nothing until Apply
- [ ] Apply persists every control; Reset-to-defaults restores defaults and previews them
- [ ] All controls persist across restart
- [ ] The console height control changes the shared pane height used by every tab
- [ ] About reports paths that exist and match where files are actually written
- [ ] Copy, open-folder and every URL action work
- [ ] About shows the version and Git SHA stamped into the build
