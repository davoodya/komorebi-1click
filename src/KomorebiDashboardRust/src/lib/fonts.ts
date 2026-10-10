/**
 * Ticket 08 — the font lists, the TypeScript half.
 *
 * The WPF build keeps these in `Services/FontCatalog.cs`; this is the Rust
 * twin's mirror of the STATIC half (the lists that must open instantly). The
 * ENUMERATION half — every installed face — is the backend's
 * `fonts::enumerate_installed()`, called exactly once behind the sentinel and
 * cached here for the rest of the session.
 *
 * The two lists cannot drift apart because MONOSPACED is spliced INTO
 * standard: the console list is the monospaced subset, not a second spelling
 * of it.
 */

/** The "show every installed font" entry, always LAST so its position is predictable. */
export const ALL_FONTS_SENTINEL = 'Custom (All Fonts)...';

/**
 * The monospaced subset of STANDARD, and the default source for the console
 * pane. WPF parity: a proportional face makes script output's columns drift.
 */
export const MONOSPACED = [
  'Cascadia Mono',
  'Cascadia Code',
  'Consolas',
  'Lucida Console',
  'Courier New'
] as const;

/**
 * Tier 1 — faces shipped with every supported Windows version, grouped so the
 * order is useful rather than alphabetical: UI faces, then the monospaced
 * faces, then the document and display faces.
 */
export const STANDARD = [
  // Fluent / UI
  'Segoe UI',
  'Segoe UI Variable',
  'Calibri',
  'Tahoma',
  'Verdana',
  'Trebuchet MS',
  'Candara',
  'Corbel',

  // Monospaced — the console pane's fonts, from the single list above
  ...MONOSPACED,

  // Document
  'Georgia',
  'Times New Roman',
  'Palatino Linotype',
  'Book Antiqua',
  'Garamond',
  'Cambria',
  'Constantia',

  // Display
  'Comic Sans MS',
  'Impact',
  'Franklin Gothic Medium',
  'Arial'
] as const;

/** The tier-1 list followed by the sentinel. Cheap: no font enumeration. */
export function standardWithSentinel(): string[] {
  return [...STANDARD, ALL_FONTS_SENTINEL];
}

/** The monospaced list followed by the sentinel — the console pane's source. */
export function monospacedWithSentinel(): string[] {
  return [...MONOSPACED, ALL_FONTS_SENTINEL];
}


/** Is this value the sentinel rather than a real font? */
export function isSentinel(value: string): boolean {
  return value === ALL_FONTS_SENTINEL;
}

/** True when a name is one of the shipped monospaced faces. */
export function isMonospacedName(value: string): boolean {
  return (MONOSPACED as readonly string[]).includes(value);
}

/** Is this value a name the tier-1 list already ships? */
export function isStandardName(value: string): boolean {
  return (STANDARD as readonly string[]).includes(value);
}

/**
 * Every installed face, enumerated once and cached.
 *
 * The cache lives on the PROMISE, not the resolved value: two rapid opens of
 * the list share one backend round-trip, and a failure is not cached — the
 * next open may succeed, matching the WPF catalog's "cache on success only".
 */
let enumeration: Promise<string[]> | null = null;

export function enumerateInstalledFonts(): Promise<string[]> {
  if (!enumeration) {
    enumeration = import('./ipc')
      .then((ipc) => ipc.listInstalledFonts())
      .catch(() => [] as string[]);
  }
  return enumeration;
}
