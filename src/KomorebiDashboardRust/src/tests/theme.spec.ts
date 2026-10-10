// Ticket 12 — the theme switcher, the frontend's half.
//
// The CSS already carries [data-theme="dark"] and [data-theme="light"] (and
// the eight [data-accent] swatches), and the token contract pins both; what
// was missing is the runtime switch: picking a theme, applying it to the
// document, and remembering it across restarts. The parse/apply logic is pure
// over (storage, document) so a corrupted or missing stored value can be
// tested to fall back to the default rather than to a blank shell.
import { beforeEach, describe, expect, it } from 'vitest';
import { applyAppearance, readAppearance, resolveTheme } from '../lib/theme';

describe('reading a stored appearance', () => {
  it('falls back to the documented defaults when nothing is stored', () => {
    const storage = fakeStorage({});
    expect(readAppearance(storage)).toEqual({ theme: 'dark', accent: 'Blue' });
  });

  it('honours a stored theme and accent', () => {
    const storage = fakeStorage({
      'komorebi-dashboard-theme': 'light',
      'komorebi-dashboard-accent': 'Amber'
    });
    expect(readAppearance(storage)).toEqual({ theme: 'light', accent: 'Amber' });
  });

  it('ignores a corrupted or unknown stored value instead of breaking the shell', () => {
    // A hand-edited or older value must not leave the document without a
    // theme; the default is applied and the junk is simply not remembered.
    expect(
      readAppearance(
        fakeStorage({
          'komorebi-dashboard-theme': 'solarized',
          'komorebi-dashboard-accent': 'octarine'
        })
      )
    ).toEqual({
      theme: 'dark',
      accent: 'Blue'
    });
    expect(
      readAppearance(fakeStorage({ 'komorebi-dashboard-theme': null, 'komorebi-dashboard-accent': undefined }))
    ).toEqual({
      theme: 'dark',
      accent: 'Blue'
    });
  });
});

describe('applying an appearance to the document', () => {
  let root: HTMLElement;

  beforeEach(() => {
    document.documentElement.removeAttribute('data-theme');
    document.documentElement.removeAttribute('data-accent');
    root = document.documentElement;
  });

  it('sets the theme and the accent on the root element', () => {
    applyAppearance(root, 'light', 'Violet');
    expect(root.dataset.theme).toBe('light');
    expect(root.dataset.accent).toBe('Violet');
  });

  it('replaces a previous theme instead of stacking another attribute', () => {
    applyAppearance(root, 'dark', 'Blue');
    applyAppearance(root, 'light', 'Rose');
    expect(root.dataset.theme).toBe('light');
    expect(root.dataset.accent).toBe('Rose');
  });

  it('gives the browser the matching color-scheme hint', () => {
    applyAppearance(root, 'light', 'Blue');
    expect(root.style.colorScheme).toBe('light');
    applyAppearance(root, 'dark', 'Blue');
    expect(root.style.colorScheme).toBe('dark');
  });
});

describe('the runtime switch', () => {
  it('flips the theme and keeps everything else', () => {
    expect(resolveTheme('dark')).toBe('light');
    expect(resolveTheme('light')).toBe('dark');
  });
});

function fakeStorage(values: Record<string, unknown>): Storage {
  const map = new Map<string, string>();
  for (const [key, value] of Object.entries(values)) {
    if (typeof value === 'string') map.set(key, value);
  }
  return {
    get length() {
      return map.size;
    },
    clear: () => map.clear(),
    getItem: (key: string) => map.get(key) ?? null,
    key: (index: number) => [...map.keys()][index] ?? null,
    removeItem: (key: string) => map.delete(key),
    setItem: (key: string, value: string) => void map.set(key, String(value))
  } as Storage;
}
