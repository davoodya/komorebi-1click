/**
 * Ticket 06 — the settings document on the TypeScript side.
 *
 * The Rust module (`src-tauri/src/settings.rs`) is the single writer of
 * `%APPDATA%\KomorebiDashboard\settings.json` and the source of truth for
 * normalization: anything outside its band is reset to its default, the WPF
 * store's rule, so the two builds never disagree about what a hand-edited file
 * means.
 *
 * This module therefore holds ONLY:
 *   • the document's shape (camelCase, matching serde's rename), and
 *   • the Presentation helpers the sliders need so a NORMAL drag cannot
 *     produce an out-of-range value (the backend stays the validator).
 *
 * The defaults here mirror the Rust constants and are asserted in
 * `settings.spec.ts` — a disagreement between the two builds' defaults is a
 * test failure, never a runtime surprise.
 */

/** Every value the settings document carries (WPF field names, camelCase). */
export interface SettingsDocument {
  theme: string;
  colorScheme: string;
  fontFamily: string;
  fontSize: number;
  accentColor: string;
  uiScale: number;
  consolePercent: number;
  consoleFontFamily: string;
  consoleFontSize: number;
  toggles: Record<string, boolean>;
  ahkScriptStates: Record<string, boolean>;
}

/** Mirrors the Rust constants. A disagreement fails `settings.spec.ts`. */
export const SETTINGS_DEFAULTS: SettingsDocument = {
  theme: 'Dark',
  colorScheme: 'Blue',
  fontFamily: 'Segoe UI',
  fontSize: 14,
  accentColor: '',
  uiScale: 100,
  consolePercent: 25,
  consoleFontFamily: 'Cascadia Mono, Consolas, Courier New',
  consoleFontSize: 12,
  toggles: {},
  ahkScriptStates: {},
};

/**
 * The valid bands, mirroring the Rust normalization EXACTLY (settings.rs:
 * font 8–40, uiScale 50–300, console share 10–60, console font 8–32).
 *
 * These exist for one reason only: a slider DRAG must not produce an
 * out-of-range value. The backend stays the validator — if a band here is
 * ever wider than the Rust one, a value the UI happily offers gets silently
 * reset on save. `settings.spec.ts` pins every number against the Rust
 * constants (both sides listed there), so a drift on either side fails here
 * first.
 */
export const SETTINGS_BANDS = {
  fontSize: { min: 8, max: 40 },
  uiScale: { min: 50, max: 300 },
  consolePercent: { min: 10, max: 60 },
  consoleFontSize: { min: 8, max: 32 },
} as const;

/** A sentinel colorScheme meaning "accentColor holds a #rrggbb value". */
export const CUSTOM_COLOR_SCHEME = 'Custom';

/**
 * Clamp a value into a band, mirroring the backend's *presentation* half: a
 * normal drag cannot leave the band, and a value outside the band is never
 * sent at all — the backend resets such a value to the default anyway.
 */
export function clampToBand(
  key: 'fontSize' | 'uiScale' | 'consolePercent' | 'consoleFontSize',
  value: number,
): number {
  const band = SETTINGS_BANDS[key];
  return Math.min(band.max, Math.max(band.min, Math.round(value)));
}

/**
 * The effective accent: the named scheme, or the custom hex behind it.
 * `accentColor` is either one of the eight names or a '#rrggbb', so the hex
 * badge needs exactly one expression — the same one `theme.ts` persists.
 */
export function effectiveAccentName(doc: SettingsDocument): string {
  return doc.colorScheme === CUSTOM_COLOR_SCHEME ? doc.accentColor : doc.colorScheme;
}

/** Is this value already one of the eight named accents? */
export function isNamedAccent(value: string): boolean {
  return value.length > 0 && !value.startsWith('#');
}
