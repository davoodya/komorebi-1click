// The token contract. Anything here must exist in src/app.css; the unit test
// `src/tests/tokens.spec.ts` fails if the two ever drift apart.

/** The eight shipped accent swatches (parity with the WPF build, ADR-0015). */
export const ACCENTS = [
  'Blue',
  'Indigo',
  'Violet',
  'Rose',
  'Amber',
  'Emerald',
  'Teal',
  'Slate'
] as const;

export type Accent = (typeof ACCENTS)[number];

export const THEMES = ['dark', 'light'] as const;
export type Theme = (typeof THEMES)[number];

/** Supported UI scales, as CSS root scales (spec US 64). */
export const SCALES = ['100', '125', '150'] as const;
export type Scale = (typeof SCALES)[number];

/** Console pane share bounds, in percent of the tab body (registry: 10–60). */
export const CONSOLE_MIN_PERCENT = 10;
export const CONSOLE_MAX_PERCENT = 60;

/** Every CSS custom property a component is allowed to depend on. */
export const TOKEN_NAMES = [
  '--bg',
  '--surface',
  '--surface-2',
  '--surface-3',
  '--border',
  '--text',
  '--muted',
  '--shadow',
  '--accent',
  '--accent-contrast',
  '--accent-soft',
  '--accent-faint',
  '--accent-border',
  '--ok',
  '--warning',
  '--danger',
  '--radius-lg',
  '--radius-md',
  '--radius-sm',
  '--row-gap',
  '--ui-font',
  '--ui-font-size',
  '--console-font',
  '--console-font-size',
  '--ui-scale'
] as const;

export function isAccent(value: string): value is Accent {
  return (ACCENTS as readonly string[]).includes(value);
}

export function isTheme(value: string): value is Theme {
  return (THEMES as readonly string[]).includes(value);
}

/** Restrict a console share to the supported range, preserving fractions. */
export function clampConsolePercent(percent: number): number {
  if (!Number.isFinite(percent)) return CONSOLE_MIN_PERCENT;
  return Math.min(CONSOLE_MAX_PERCENT, Math.max(CONSOLE_MIN_PERCENT, percent));
}
