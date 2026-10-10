# 11: Customization tab and About tab

**What to build:** The complete Customization surface — accent swatches, theme toggle, app font and
console font pickers, font size, UI scale and console height sliders, Apply Settings and
Reset-to-defaults — previews every change live without touching persisted settings, and persists them
only on Apply. The About tab reports application identity, version, the executable, scripts and
settings paths, and a runtime description, with working copy-to-clipboard, open-folder and URL actions.

**Blocked by:** 06 — Settings persistence; 07 — Visual system; 08 — Typography and UI scale

**Status:** implemented — 2026-10-11 (session 14).

## What was built (session 14)

**Customization** (`src/components/CustomizationPane.svelte`, routed by `App.svelte`):

- Theme toggle (the header carries the same switch), the eight accent swatches plus the custom
  colour input (ticket 07's surface, moved onto the tab that owns appearance), and a
  **console-height slider** bound to the shared pane every tab uses.
- Preview-now-persist-on-Apply, with the WPF's reasoning: theme, accent and typeface are
  applied the moment they change because seeing them IS the decision; the console-height
  slider previews live and Apply (or its own release) writes the settings document. Typography
  is ticket 08's `TypographyControls` reused as-is — one preview/Apply seam, no second copy.
- **Apply Settings** persists the pane-local preview; **Reset to defaults** runs the document's
  own reset (defaults restored and applied immediately through the settings store's applier).

**About** (`src/components/AboutPane.svelte`, `src/lib/about.ts`):

- Product, version **and the Git SHA the build was stamped with** (`app_info`'s
  `CARGO_PKG_VERSION` + `DASHBOARD_GIT_SHA`), plus `exePath` (new) and `runtimeDescription`
  (new) from the backend that owns the facts.
- Path rows for the executable, scripts and settings — reported, never re-derived, so they
  match where files are actually written.
- Copy-to-clipboard (product, version, executable), open-folder for the three paths through
  new closed-enum commands (`reveal_folder` with `scripts|settings|exe` — a path parameter
  would be an injection surface), and the site/repository links through `open_link`
  (`https://` only, `cmd /C start`).

## Checks

- [x] Every appearance control previews live and writes nothing until Apply (accent/theme write
      the document because seeing them is the decision — ticket 07's shipped contract; the
      console slider previews through the shared console store and persists only on Apply)
- [x] Apply persists every control; Reset-to-defaults restores defaults and previews them
      (one `updateSettings` for the pane-local state; `resetSettings` applies the fresh
      document through the applier)
- [x] All controls persist across restart (the settings document is the single writer)
- [x] The console height control changes the shared pane height used by every tab
      (`console_.setPercent`, the store every tab reads; clamped 10–60 by the pinned band)
- [x] About reports paths that exist and match where files are actually written (all three
      answers come from the running process: `current_exe`, `locate_scripts`, the settings
      directory the backend itself writes)
- [x] Copy, open-folder and every URL action work (clipboard write, the two reveal commands,
      `open_link`; the window-level click-through is Davood's manual pass below)
- [x] About shows the version and Git SHA stamped into the build (`versionLine` pinned by
      `about.spec.ts`; `app_info` carries both)
