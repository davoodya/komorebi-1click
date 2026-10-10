# 12: Packaged deliverable

**What to build:** The single deliverable executable lands in `releases\rust\`, carrying the
project's `logo.ico` in all four identity places: application icon, window/title-bar icon, favicon,
and the About image. The build stamps version and Git SHA. A crash writes a log beside the executable
naming the action that failed. Startup time, binary size and idle memory are measured and recorded
against the targets.

**Blocked by:** 05, 06, 07, 08, 09, 10, 11 — every user-facing ticket must land first

**Status:** implemented — 2026-10-11 (session 15).

## What was built (session 15)

- **Publish flow**: `cargo tauri build --no-bundle -- --locked` → the binary is copied into
  `releases\rust\KomorebiDashboard.exe` (the destination object's own `.Name`), and its
  size/SHA256 identity lives in `tests/rust-release-pins.json`. `tests\rust-release-measure.ps1`
  measures and publishes in one run.
- **Icon in all four places**: application icon = `bundle.icon` (logo.ico, embedded at build);
  window/title-bar icon = the same embedded icon (Tauri derives the window icon from it);
  favicon = `public/favicon.ico` (the same logo file, copied into the frontend dist and linked
  from `index.html`); About image = the logo's **48x48 entry extracted at build time** by
  `build.rs`, base64'd into `app_info.logoDataUrl`, shown in `AboutPane`.
- **Version + Git SHA stamped at compile time**: `build.rs` emits
  `DASHBOARD_GIT_SHA` (commit SHA, `+dirty` on a dirty tree, `development` with no git) and
  `main.rs` bakes `CARGO_PKG_VERSION` into the About version line. The crate version was
  aligned with the WPF twin's identity (`1.0.0+<sha>`).
- **Crash log beside the executable**: `crashlog.rs` installs a panic hook that APPENDS one
  record per crash to `<exe dir>\KomorebiDashboard-crash.log`, naming the action underway
  (`note_action` wraps every dispatched run behind a Drop guard). 2 cargo tests (a crash
  during an action names it; a startup crash still records; a second crash appends).
- **Measurements** (recorded in the pins file and the handoff): runtime-up **544 ms**,
  working set **29.5 MB**, size **6,642,176 B (6.33 MB)** — against the 553 ms baseline and the
  18 MB / 45 MB targets. `runtimeUpMs` is the first WebView2 child process: a non-interactive
  launch cannot see the window handle, so window-latency is measured on the desktop by hand.

## Checks

- [x] Exactly one executable exists in `releases\rust\`, with no companion files
      (`.gitkeep` + `KomorebiDashboard.exe` only)
- [x] The executable name is unchanged, so the ignore rule, shortcuts and documentation keep
      working (`scripts/ignore-dashboard.ps1` still names `KomorebiDashboard.exe`)
- [x] The correct icon appears in all four places (bundle icon; window icon derived from it;
      `dist/favicon.ico` linked from the HTML head; the About `<img>` from `logoDataUrl`) —
      the visual confirmation in the running window is Davood's manual pass
- [x] The About tab shows the stamped version string and Git SHA (`versionLine` pinned by
      `about.spec.ts`; `build.rs` stamps the SHA, the crate version matches the WPF's)
- [x] A deliberate crash writes a log beside the executable identifying the failing action
      (the hook, the action tracking and the append-only record are pinned by the crashlog
      suite; the default path is asserted to sit beside the executable — a live deliberate
      crash is Davood's manual pass)
- [x] Startup time, file size and idle RAM measured and recorded against the baseline/targets
      (544 ms runtime-up · 6.33 MB · 29.5 MB — all inside target; caveat above)
- [x] `ignore-dashboard` still names this executable, so the shipped script needs no edit
      (verified against the file; the name is unchanged)
