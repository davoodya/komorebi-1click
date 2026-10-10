// Ticket 12 — the theme switcher's logic.
//
// The CSS declares both themes (and the eight accents) as token sets on the
// root element, and the token contract pins them; this module is the runtime
// half: read what the user last chose, refuse to be broken by a corrupted
// value, and apply the choice to the document. Everything here is pure over
// (storage, root) so a fresh machine and a hand-edited localStorage key are
// both just test cases.

/** The appearance defaults. Dark is the shell's default theme (tokens.spec pins the CSS side). */
export const DEFAULTS = { theme: 'dark', accent: 'Blue' } as const;

/** The two keys the choice is remembered under. Exported so the store never re-spells them. */
export const STORAGE_KEYS = { theme: 'komorebi-dashboard-theme', accent: 'komorebi-dashboard-accent' } as const;

/** A stored theme, or null when it is absent or not one of the shipped themes. */
export function parseStoredTheme(raw: string | null): string | null {
  return raw === 'dark' || raw === 'light' ? raw : null;
}

// The eight shipped accents come from tokens.ts — the SAME table the CSS
// declares and tokens.spec.ts pins. A second list here is a list that can
// drift, and a drifted swatch is an unstyled shell.
import { ACCENTS } from './tokens';

/** A stored accent, or null when it is absent or not one of the shipped swatches. */
export function parseStoredAccent(raw: string | null): string | null {
  return raw !== null && (ACCENTS as readonly string[]).includes(raw) ? raw : null;
}

/**
 * Ticket 07 — the "Toggle Color" switch: the next accent in the cycle, or the
 * first when the current value is anything else (a hex behind the Custom
 * sentinel, or a value the CSS never declared). The toggle therefore always
 * LANDS on a declared swatch rather than stopping on an unstyled value.
 */
export function nextAccent(current: string | null): string {
  if (current === null || !parseStoredAccent(current)) return ACCENTS[0];
  const at = (ACCENTS as readonly string[]).indexOf(current);
  return ACCENTS[(at + 1) % ACCENTS.length];
}

/** The seed for a custom accent — one value, referenced by the store and pinned to the CSS. */
export const CUSTOM_ACCENT_SEED = '#4F8FFF';

/** Is this value a custom hex accent rather than one of the eight names? */
export function isHexAccent(value: string): boolean {
  return HEX_RE.test(value);
}

const HEX_RE = /^#[0-9a-f]{6}$/i;

/**
 * A stored custom accent: '#rrggbb', normalized to uppercase, or null when it
 * is absent or malformed. A three-digit hex is REJECTED, not expanded — the
 * value lands in CSS, where '#abc' is ambiguous next to the eight declared
 * swatches, and the WPF store keeps its hex six-digit too.
 */
export function parseStoredAccentHex(raw: string | null): string | null {
  if (raw === null) return null;
  const value = raw.trim();
  if (!HEX_RE.test(value)) return null;
  return value.toUpperCase();
}

/**
 * The appearance to start with: the stored choice when it is valid, the
 * defaults otherwise. A corrupted value is dropped, not honoured — a theme
 * the CSS does not declare would leave the shell unstyled.
 */
export function readAppearance(storage: Storage): { theme: string; accent: string } {
  const theme = parseStoredTheme(storage.getItem(STORAGE_KEYS.theme));
  const accent = parseStoredAccent(storage.getItem(STORAGE_KEYS.accent));
  return {
    theme: theme ?? DEFAULTS.theme,
    accent: accent ?? DEFAULTS.accent
  };
}

/** The other theme — the runtime switch, in one expression. */
export function resolveTheme(theme: string): string {
  return theme === 'dark' ? 'light' : 'dark';
}

/**
 * Write the appearance onto the root element.
 *
 * `data-theme` and `data-accent` are the exact selectors the CSS declares, so
 * this is the only place the document's appearance is set. The inline
 * `color-scheme` is the browser's hint for form controls and scrollbars, which
 * do not read custom properties.
 *
 * Ticket 07 — a CUSTOM accent arrives as a '#rrggbb' value: the selector
 * becomes `Custom` (which the CSS declares to read the runtime property) and
 * the hex is written to `--accent-custom`, so the derived companions
 * (soft/faint/border) follow automatically through the CSS.
 */
export function applyAppearance(root: HTMLElement, theme: string, accent: string): void {
  root.dataset.theme = theme;
  if (isHexAccent(accent)) {
    root.dataset.accent = 'Custom';
    root.style.setProperty('--accent-custom', accent.toUpperCase());
  } else {
    root.dataset.accent = accent;
    root.style.removeProperty('--accent-custom');
  }
  root.style.colorScheme = theme;
}


// ---------------------------------------------------------------------------
// Ticket 08 — typography.
//
// The CSS already consumes these five properties (app.css: --ui-font,
// --ui-font-size, --console-font, --console-font-size, --ui-scale); this is
// the one place the runtime writes them, whether the value comes from the
// settings document or from a live preview.
// ---------------------------------------------------------------------------

/** The typography values the runtime can write, in document units (percent). */
export interface TypographyValues {
  fontFamily: string;
  fontSize: number;
  consoleFontFamily: string;
  consoleFontSize: number;
  uiScale: number;
}

/** The percent scale (100/125/150) as the unitless multiplier the CSS multiplies by. */
export function scaleMultiplier(percent: number): number {
  return Math.max(0.5, Number(percent) / 100);
}

/** A CSS font stack for a UI face: the name, then the shell's default, then the generic. */
export function uiFontStack(family: string): string {
  return `${family}, Segoe UI, sans-serif`;
}

/** A CSS font stack for a console face: the name, then a monospaced default. */
export function consoleFontStack(family: string): string {
  return `${family}, Cascadia Mono, Consolas, monospace`;
}

/**
 * Write the typography values onto the root element. Pure over (root, values):
 * a live preview and a document load call exactly this function, so the
 * preview cannot drift from what Apply persists.
 */
export function applyTypography(root: HTMLElement, values: TypographyValues): void {
  root.style.setProperty('--ui-font', uiFontStack(values.fontFamily));
  root.style.setProperty('--ui-font-size', `${values.fontSize}px`);
  root.style.setProperty('--console-font', consoleFontStack(values.consoleFontFamily));
  root.style.setProperty('--console-font-size', `${values.consoleFontSize}px`);
  root.style.setProperty('--ui-scale', String(scaleMultiplier(values.uiScale)));
}
