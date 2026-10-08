# 12: Packaged deliverable

**What to build:** The single deliverable executable lands in `releases\rust\`, carrying the
project's `logo.ico` in all four identity places: application icon, window/title-bar icon, favicon,
and the About image. The build stamps version and Git SHA. A crash writes a log beside the executable
naming the action that failed. Startup time, binary size and idle memory are measured and recorded
against the targets.

**Blocked by:** 05, 06, 07, 08, 09, 10, 11 — every user-facing ticket must land first

**Status:** ready-for-agent

- [ ] Exactly one executable exists in `releases\rust\`, with no companion files
- [ ] The executable name is unchanged, so the ignore rule, shortcuts and documentation keep working
- [ ] The correct icon appears in all four places: application, title bar, favicon/taskbar, About image
- [ ] The About tab shows the stamped version string and Git SHA
- [ ] A deliberate crash writes a log beside the executable identifying the failing action
- [ ] Startup time, file size and idle RAM are measured and recorded against the 553 ms baseline and the 18 MB / 45 MB targets
- [ ] `ignore-dashboard` still names this executable, so the shipped script needs no edit
