import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  ACCENTS,
  SCALES,
  THEMES,
  TOKEN_NAMES,
  clampConsolePercent,
  isAccent,
  isTheme
} from '../lib/tokens';

const root = process.cwd();
const css = readFileSync(resolve(root, 'src/app.css'), 'utf8');

/** Every component that renders chrome, including the shell itself. */
function componentSources(): Array<[string, string]> {
  const dir = resolve(root, 'src/components');
  const files = readdirSync(dir)
    .filter((name) => name.endsWith('.svelte'))
    .map((name) => [`components/${name}`, readFileSync(resolve(dir, name), 'utf8')] as [string, string]);
  files.push(['App.svelte', readFileSync(resolve(root, 'src/App.svelte'), 'utf8')]);
  return files;
}

describe('design tokens', () => {
  it('declares every token the components are allowed to depend on', () => {
    for (const token of TOKEN_NAMES) {
      expect(css, `missing token ${token}`).toContain(`${token}:`);
    }
  });

  it('defines the eight shipped accent swatches', () => {
    expect(ACCENTS).toHaveLength(8);
    for (const accent of ACCENTS) {
      expect(css, `missing accent selector for ${accent}`).toContain(`[data-accent="${accent}"]`);
    }
  });

  it('defines both themes and all three UI scales', () => {
    for (const theme of THEMES) {
      expect(css, `missing theme ${theme}`).toContain(`[data-theme="${theme}"]`);
    }
    for (const scale of SCALES) {
      expect(css, `missing scale ${scale}`).toContain(`[data-scale="${scale}"]`);
    }
  });

  it('never asks for a Mica/Acrylic/vibrancy effect (D21 must not return)', () => {
    expect(css.toLowerCase()).not.toMatch(/\bmica\b|acrylic|vibrancy|backdrop-filter/);
  });

  it('validates theme and accent names', () => {
    expect(isTheme('dark')).toBe(true);
    expect(isTheme('light')).toBe(true);
    expect(isTheme('solarized')).toBe(false);
    expect(isAccent('Slate')).toBe(true);
    expect(isAccent('Chartreuse')).toBe(false);
  });

  it('clamps the console share to the supported range', () => {
    expect(clampConsolePercent(25)).toBe(25);
    expect(clampConsolePercent(37.5)).toBe(37.5);
    expect(clampConsolePercent(4)).toBe(10);
    expect(clampConsolePercent(90)).toBe(60);
    expect(clampConsolePercent(Number.NaN)).toBe(10);
  });

  it('contains no literal colour in any component: tokens only', () => {
    // Colour literals are allowed in src/app.css and nowhere else. A component
    // that hard-codes one cannot follow the theme or the accent.
    const literal = /#[0-9a-fA-F]{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(/;
    for (const [name, source] of componentSources()) {
      expect(literal.test(source), `literal colour in ${name}`).toBe(false);
    }
  });
});
