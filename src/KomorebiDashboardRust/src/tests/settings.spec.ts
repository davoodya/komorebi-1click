/**
 * Ticket 06 — the settings store and its pure helpers.
 *
 * The backend is injected: these tests drive the store in plain node with a
 * fake, because the Tauri IPC layer is a double-click smoke test, not a unit
 * test. What IS pinned here is the store's CONTRACT with the user:
 *   • a load applies the appearance half before anything else,
 *   • a corrupt file's quarantine is surfaced, never silent,
 *   • a failed save leaves the in-memory document unchanged,
 *   • an out-of-range value never reaches the backend (the backend owns the
 *     real reset rule, mirrored here so a drag cannot even ask),
 *   • the defaults here match theme/tokens' own defaults — a disagreement
 *     between the two layers is a test failure, never a runtime surprise.
 */

import { describe, expect, it, beforeEach } from 'vitest';
import {
  CUSTOM_COLOR_SCHEME,
  SETTINGS_BANDS,
  SETTINGS_DEFAULTS,
  clampToBand,
  effectiveAccentName,
  isNamedAccent,
  type SettingsDocument,
} from '../lib/settings';
import {
  busy,
  settingsDocument,
  hasCustomAccent,
  lastQuarantine,
  loadSettings,
  resetSettings,
  revealSettings,
  setAppearanceApplier,
  setBackend,
  status,
  updateSettings,
  type SettingsBackend,
} from '../lib/settings.svelte.ts';
import { DEFAULTS, nextAccent, parseStoredAccentHex } from '../lib/theme';

/** A recording fake backend: the tests drive it, it records the calls. */
function fakeBackend(overrides: Partial<SettingsBackend> = {}) {
  let stored: SettingsDocument = { ...SETTINGS_DEFAULTS };
  const saved: SettingsDocument[] = [];
  const revealed: string[] = [];
  let quarantined: string | null = null;
  const backend: SettingsBackend = {
    async getSettings() {
      return { settings: { ...stored }, quarantined };
    },
    async saveSettings(settings) {
      saved.push(settings);
      stored = { ...settings };
      return 'C:\\\\settings\\\\settings.json';
    },
    async resetSettings() {
      stored = { ...SETTINGS_DEFAULTS };
      return 'C:\\\\settings\\\\settings.json';
    },
    async revealSettingsFolder() {
      revealed.push('C:\\\\settings');
      return 'C:\\\\settings';
    },
    ...overrides,
  };
  return { backend, saved, revealed, setQuarantine: (q: string | null) => (quarantined = q) };
}

/** The appearance this store applied, recorded. */
function recordingApplier() {
  const applied: SettingsDocument[] = [];
  setAppearanceApplier((doc) => applied.push(doc));
  return applied;
}

beforeEach(() => {
  setBackend(null);
  setAppearanceApplier(() => {});
});

describe('the pure helpers', () => {
  it('clamps a drag into its band without inventing precision', () => {
    expect(clampToBand('fontSize', 3)).toBe(SETTINGS_BANDS.fontSize.min);
    expect(clampToBand('fontSize', 99)).toBe(SETTINGS_BANDS.fontSize.max);
    expect(clampToBand('fontSize', 13.6)).toBe(14);
    expect(clampToBand('consolePercent', 55)).toBe(55);
  });

  it('resolves the effective accent: name, or the hex behind Custom', () => {
    const doc = { ...SETTINGS_DEFAULTS };
    expect(effectiveAccentName(doc)).toBe('Blue');
    doc.colorScheme = 'Teal';
    expect(effectiveAccentName(doc)).toBe('Teal');
    doc.colorScheme = CUSTOM_COLOR_SCHEME;
    doc.accentColor = '#112233';
    expect(effectiveAccentName(doc)).toBe('#112233');
    expect(isNamedAccent(effectiveAccentName(doc))).toBe(false);
  });

  it('mirrors the Rust constants key by key (both sides listed)', () => {
    // THE cross-layer contract: settings.rs owns the file, this table is the
    // TypeScript mirror. The Rust side's suite pins the same pairs; this one
    // pins the mirror. A divergence in EITHER file fails a suite, not a
    // shipped default the user never chose.
    const rust: SettingsDocument = {
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
    expect(SETTINGS_DEFAULTS).toEqual(rust);
    // The slider bands mirror settings.rs's normalize() ranges. A band WIDER
    // than the backend's is the bug class that motivated this table: the UI
    // offers a value the backend silently resets.
    expect(SETTINGS_BANDS).toEqual({
      fontSize: { min: 8, max: 40 },
      uiScale: { min: 50, max: 300 },
      consolePercent: { min: 10, max: 60 },
      consoleFontSize: { min: 8, max: 32 },
    });
    // The WPF file's Dark default and this module's 'dark' are the same
    // appearance.
    expect(SETTINGS_DEFAULTS.theme.toLowerCase()).toBe(DEFAULTS.theme);
  });
});

describe('the store', () => {
  it('applies the appearance half before anything else on load', async () => {
    const { backend } = fakeBackend();
    setBackend(backend);
    const applied = recordingApplier();

    await loadSettings();

    expect(applied).toHaveLength(1);
    expect(applied[0].theme).toBe('Dark');
    expect(settingsDocument.theme).toBe('Dark');
  });

  it('surfaces a quarantine instead of silently showing defaults', async () => {
    const fake = fakeBackend();
    fake.setQuarantine('settings.corrupt-20261011.json');
    setBackend(fake.backend);
    recordingApplier();

    await loadSettings();

    expect(lastQuarantine()).toBe('settings.corrupt-20261011.json');
    expect(status()).toEqual({ kind: 'quarantined', file: 'settings.corrupt-20261011.json' });
  });

  it('never sends an out-of-range value — the drag is clamped here first', async () => {
    const fake = fakeBackend();
    setBackend(fake.backend);
    recordingApplier();
    await loadSettings();

    await updateSettings({ fontSize: 999, uiScale: 2 });

    expect(fake.saved).toHaveLength(1);
    expect(fake.saved[0].fontSize).toBe(SETTINGS_BANDS.fontSize.max);
    expect(fake.saved[0].uiScale).toBe(SETTINGS_BANDS.uiScale.min);
    expect(status()).toEqual({ kind: 'saved' });
  });

  it('leaves the document untouched when a save fails', async () => {
    const fake = fakeBackend({
      saveSettings: async () => {
        throw new Error('disk full');
      },
    });
    setBackend(fake.backend);
    recordingApplier();
    await loadSettings();

    await updateSettings({ theme: 'Light' });

    expect(settingsDocument.theme).toBe('Dark');
    expect(status()).toEqual({ kind: 'error', message: 'disk full' });
    expect(busy()).toBe(false);
  });

  it('resets every preference and applies the fresh defaults', async () => {
    const fake = fakeBackend();
    setBackend(fake.backend);
    const applied = recordingApplier();
    await loadSettings();
    await updateSettings({ theme: 'Light', fontSize: 20 });
    applied.length = 0;

    await resetSettings();

    expect(settingsDocument).toEqual({ ...SETTINGS_DEFAULTS });
    expect(applied).toHaveLength(1);
    expect(status().kind).toBe('reset');
    expect(lastQuarantine()).toBe(null);
  });

  it('reveals the folder through the backend', async () => {
    const fake = fakeBackend();
    setBackend(fake.backend);
    await revealSettings();
    expect(fake.revealed).toEqual(['C:\\\\settings']);
    expect(status().kind).toBe('revealed');
  });

  it('adopts a custom hex as the accent', async () => {
    const fake = fakeBackend();
    setBackend(fake.backend);
    recordingApplier();
    await loadSettings();

    // The theme store writes through this document; here the store is driven
    // directly to pin the sentinel pair.
    await updateSettings({ colorScheme: CUSTOM_COLOR_SCHEME, accentColor: '#3fa9f5' });

    expect(settingsDocument.colorScheme).toBe(CUSTOM_COLOR_SCHEME);
    expect(hasCustomAccent()).toBe(true);
    expect(fake.saved[0].accentColor).toBe('#3FA9F5');
  });
});

describe('ticket 07 — the accent half', () => {
  it('cycles the eight named accents and wraps at the end', () => {
    expect(nextAccent('Blue')).toBe('Indigo');
    expect(nextAccent('Indigo')).toBe('Violet');
    expect(nextAccent('Slate')).toBe('Blue');
    // A hex is not in the cycle: the toggle lands on a declared swatch.
    expect(nextAccent('#3fa9f5')).toBe('Blue');
    expect(nextAccent(null)).toBe('Blue');
  });

  it('accepts a six-digit hex and normalizes it; rejects anything else', () => {
    expect(parseStoredAccentHex('  #3fa9f5  ')).toBe('#3FA9F5');
    expect(parseStoredAccentHex('#ABCDEF')).toBe('#ABCDEF');
    // Three-digit is rejected, not expanded — the CSS sits next to eight
    // declared swatches, and ambiguity there is a bug.
    expect(parseStoredAccentHex('#abc')).toBe(null);
    expect(parseStoredAccentHex('blue')).toBe(null);
    expect(parseStoredAccentHex('')).toBe(null);
    expect(parseStoredAccentHex(null)).toBe(null);
  });
});
