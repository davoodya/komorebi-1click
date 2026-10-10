// Ticket 08 — the font lists.
//
// The ticket's checks are about BEHAVIOUR: the standard list opens instantly
// (nothing here enumerates), the sentinel is last and can never become the
// applied value, and the console list is monospaced only. The enumeration
// itself is the backend's (fonts.rs, five cargo tests over registry output);
// this pins the static half.

import { describe, expect, it } from 'vitest';
import {
  ALL_FONTS_SENTINEL,
  STANDARD,
  MONOSPACED,
  isMonospacedName,
  isSentinel,
  isStandardName,
  monospacedWithSentinel,
  standardWithSentinel
} from '../lib/fonts';

describe('the tier-1 font lists', () => {
  it('puts the sentinel last in both lists', () => {
    expect(standardWithSentinel().at(-1)).toBe(ALL_FONTS_SENTINEL);
    expect(monospacedWithSentinel().at(-1)).toBe(ALL_FONTS_SENTINEL);
  });

  it('carries the monospaced faces inside the standard list exactly once', () => {
    // The console list is a SUBSET of the standard list, not a second spelling
    // of it — a change to one cannot leave the other behind.
    const standard = standardWithSentinel();
    for (const name of MONOSPACED) {
      expect(standard.filter((entry) => entry === name)).toHaveLength(1);
    }
  });

  it('offers only monospaced faces for the console', () => {
    for (const name of monospacedWithSentinel()) {
      if (name === ALL_FONTS_SENTINEL) continue;
      expect(isMonospacedName(name), `${name} is not monospaced`).toBe(true);
    }
    expect(MONOSPACED.length).toBeGreaterThan(0);
  });

  it('recognizes the sentinel, the standard faces, and the monospaced subset', () => {
    expect(isSentinel(ALL_FONTS_SENTINEL)).toBe(true);
    expect(isSentinel('Segoe UI')).toBe(false);
    expect(isStandardName('Segoe UI')).toBe(true);
    expect(isStandardName('Comic Sans MS')).toBe(true);
    expect(isStandardName('No Such Font 9000')).toBe(false);
    expect(isMonospacedName('Cascadia Mono')).toBe(true);
    expect(isMonospacedName('Segoe UI')).toBe(false);
  });

  it('never lets the sentinel stand in for a font name', () => {
    // The sentinel's value is the sentinel string; a font named after it
    // would be a different string, and no shipped list contains it.
    expect(STANDARD).not.toContain(ALL_FONTS_SENTINEL);
    expect(MONOSPACED).not.toContain(ALL_FONTS_SENTINEL);
  });

  it('keeps the lists in a useful order: UI faces first, then mono, then document and display', () => {
    const standard = standardWithSentinel();
    const firstMono = standard.indexOf(MONOSPACED[0]);
    const firstDocument = standard.indexOf('Georgia');
    // The mono block sits between the UI block and the document block.
    expect(firstMono).toBeGreaterThan(standard.indexOf('Segoe UI'));
    expect(firstMono).toBeLessThan(firstDocument);
  });
});
