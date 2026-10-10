// Ticket 12 — the theme switcher, the frontend's half.
//
// The CSS already carries [data-theme="dark"] and [data-theme="light"] (and
// the eight [data-accent] swatches), and the token contract pins both; what
// was missing is the runtime switch: picking a theme, applying it to the
// document, and remembering it across restarts. The parse/apply logic is pure
// over (storage, document) so a corrupted or missing stored value can be
// tested to fall back to the default rather than to a blank shell.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  CUSTOM_ACCENT_SEED,
  applyAppearance,
  applyTypography,
  consoleFontStack,
  readAppearance,
  resolveTheme,
  scaleMultiplier,
  uiFontStack
} from '../lib/theme';

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

// Ticket 07 — the custom accent: one seed hex declared in BOTH files the
// runtime touches, and the selector the runtime sets when the accent is a hex.
// Ticket 08 — the typography writer.
describe('typography', () => {
  const VALUES = {
    fontFamily: 'Tahoma',
    fontSize: 15,
    consoleFontFamily: 'Cascadia Mono',
    consoleFontSize: 13,
    uiScale: 125
  };
  let root: HTMLElement;

  beforeEach(() => {
    root = document.documentElement;
    for (const property of ['--ui-font', '--ui-font-size', '--console-font', '--console-font-size', '--ui-scale']) {
      root.style.removeProperty(property);
    }
  });

  it('writes every typography property the CSS consumes', () => {
    applyTypography(root, VALUES);
    expect(root.style.getPropertyValue('--ui-font')).toBe(uiFontStack('Tahoma'));
    expect(root.style.getPropertyValue('--ui-font-size')).toBe('15px');
    expect(root.style.getPropertyValue('--console-font')).toBe(consoleFontStack('Cascadia Mono'));
    expect(root.style.getPropertyValue('--console-font-size')).toBe('13px');
    // The CSS multiplies by this, so it must be unitless: 125% -> 1.25.
    expect(root.style.getPropertyValue('--ui-scale')).toBe('1.25');
  });

  it('converts every supported scale and never reaches zero', () => {
    expect(scaleMultiplier(100)).toBe(1);
    expect(scaleMultiplier(125)).toBe(1.25);
    expect(scaleMultiplier(150)).toBe(1.5);
    expect(scaleMultiplier(0)).toBeGreaterThan(0);
    expect(scaleMultiplier(-10)).toBeGreaterThan(0);
  });

  it('keeps a monospaced fallback under a console face', () => {
    // A missing console font must degrade to SOMETHING monospaced, or the
    // output's columns drift.
    expect(consoleFontStack('Cascadia Mono')).toMatch(/monospace$/);
    expect(uiFontStack('Tahoma')).toMatch(/sans-serif$/);
  });
});

describe('the custom accent', () => {
  const css = readFileSync(resolve(process.cwd(), 'src/app.css'), 'utf8');
  let root: HTMLElement;

  beforeEach(() => {
    document.documentElement.removeAttribute('data-accent');
    document.documentElement.style.removeProperty('--accent-custom');
    root = document.documentElement;
  });

  it('keeps the custom-accent seed identical in CSS and runtime', () => {
    // One value, two files, this test is the seam: the runtime writes the
    // seed into --accent-custom, and the CSS declares that very seed.
    expect(css).toContain('--accent-custom: ' + CUSTOM_ACCENT_SEED);
    expect(css).toContain('[data-accent="Custom"]');
  });

  it('applies a custom hex accent as the Custom selector plus the runtime property', () => {
    applyAppearance(root, 'dark', '#3fa9f5');
    expect(root.dataset.accent).toBe('Custom');
    expect(root.style.getPropertyValue('--accent-custom')).toBe('#3FA9F5');
    // A named accent CLEARS the runtime property, so switching back cannot
    // leave a stale hex overriding the swatch.
    applyAppearance(root, 'dark', 'Teal');
    expect(root.dataset.accent).toBe('Teal');
    expect(root.style.getPropertyValue('--accent-custom')).toBe('');
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
