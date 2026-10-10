# 08: Typography and UI scale

**What to build:** The app font list is a fast tiered standard list whose last entry is
`Custom (All Fonts)...`; choosing it enumerates the full installed set once, off the UI thread, and
caches the result. The console font list contains only monospaced families and gets the same
sentinel. App font size, console size and UI scale (100/125/150%) preview live as you change them and
persist only when applied.

**Blocked by:** 07 — Visual system — theme and accent

**Status:** implemented — 2026-10-11 (session 13). Automated checks green; the last line is
Davood's manual pass (`tests-reminded.md`).

## What was built (session 13)

- `src-tauri/src/fonts.rs` — the full enumeration, dependency-free: both
  `HKLM`/`HKCU ...\Fonts` keys through `reg query`, face names parsed (key lines and file
  descriptors dropped, trailing parenthesized type tokens stripped in a loop for faces whose own
  name already carries a group), case-folded dedupe, ordinal/case-folded sort. 5 cargo tests, one of
  them against the live registry. Tauri command `list_installed_fonts` is **async**, so the
  enumeration runs off the UI thread.
- `src/lib/fonts.ts` — the standard tier (the WPF's exact order, mono faces spliced mid-list like
  the WPF) + `ALL_FONTS_SENTINEL` = `"Custom (All Fonts)..."` last in both lists, `isSentinel`,
  `isStandardName`, `isMonospacedName`, and the one-time cached `enumerateInstalledFonts()`.
- `src/lib/theme.ts` — `applyTypography(root, values)` writes the five CSS properties the sheet
  already declares (`--ui-font`, `--ui-font-size`, `--console-font`, `--console-font-size`,
  `--ui-scale`), with `scaleMultiplier()` converting 100/125/150 to the unitless multiplier the CSS
  multiplies by. A monospaced/sans-serif fallback rides under the chosen face. `theme.svelte.ts`'s
  applier calls it on every document load, so the document applies typography the same way it
  applies theme and accent.
- `src/components/TypographyControls.svelte` (rendered by `SettingsPane`) — five controls. A change
  writes the CSS properties immediately (preview, nothing persisted); **Apply** writes all five
  through the settings document in one save; **Revert** re-reads the document. The sentinel option
  triggers the cached enumeration and is never itself applied: it stays out of the persisted value
  (the store pins the defaults; the preview state only ever holds a real face).

## Checks

- [x] The standard font list opens instantly — enumerating fonts never stalls opening the list
  (tier 1 is a static array; the sentinel option is appended to it)
- [x] The sentinel entry never remains selected as the applied value (it is a picker action, not a
  font; after enumeration the current real font stays selected)
- [x] Full enumeration runs off the UI thread, happens once, and is cached for later opens
  (async Tauri command + module-level promise cache; `fonts.rs` tests pin the parse)
- [x] The console font list contains only monospaced families (`MONOSPACED` ⊆ `STANDARD`, pinned
  one entry per name by `fonts.spec.ts`)
- [x] Changing family, size or scale previews immediately without touching persisted settings
  (preview writes CSS properties only; the document changes only on Apply)
- [x] Applying persists every typography control across restart (one `updateSettings` writes all
  five fields; the store's round-trip suite pins them and the document's `normalize()` keeps
  out-of-band values from surviving a save/load)
- [ ] 125% scale verified visually on the portrait monitor with no clipped, overlapping or overflowing
  layout — **manual, Davood's**
