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

/** A stored accent, or null when it is absent or not one of the shipped swatches. */
export function parseStoredAccent(raw: string | null): string | null {
  const accents = ['Blue', 'Indigo', 'Violet', 'Rose', 'Amber', 'Emerald', 'Teal', 'Slate'];
  return raw !== null && accents.includes(raw) ? raw : null;
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
 */
export function applyAppearance(root: HTMLElement, theme: string, accent: string): void {
  root.dataset.theme = theme;
  root.dataset.accent = accent;
  root.style.colorScheme = theme;
}
