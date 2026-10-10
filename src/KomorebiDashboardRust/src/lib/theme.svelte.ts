// Ticket 06/07 — the appearance switcher's state.
//
// Ticket 12 built the switch on top of localStorage; ticket 06 moved the
// settings document to the backend, and appearance is half of that document.
// So this store is now the document's appearance VIEW: it never writes a file
// itself — a toggle updates the document through the settings store, and the
// store applies the whole document (theme + accent together, since a document
// holds both).
//
// The accent half carries ticket 07: eight named swatches cycled by the
// header's Toggle Color button, plus a custom '#rrggbb' behind the Custom
// sentinel that the Settings pane's colour input writes.

import { CUSTOM_ACCENT_SEED, applyAppearance, nextAccent } from './theme';
import { CUSTOM_COLOR_SCHEME, SETTINGS_DEFAULTS, effectiveAccentName, isNamedAccent } from './settings';
import {
  loadSettings,
  setAppearanceApplier,
  settingsDocument,
  updateSettings,
} from './settings.svelte.ts';
import type { SettingsDocument } from './settings';

class ThemeStore {
  theme = $state<'dark' | 'light'>('dark');
  /** One of the eight names, or a '#rrggbb' behind the Custom sentinel. */
  accent = $state<string>(SETTINGS_DEFAULTS.colorScheme);

  /** Where the document has been read at least once. */
  get loaded(): boolean {
    return settingsDocument.theme !== undefined;
  }

  /**
   * Read the settings document. The document is authoritative for appearance
   * from the first frame after this resolves — there is no separate theme
   * store state that could disagree with it.
   */
  async load(): Promise<void> {
    setAppearanceApplier((doc: SettingsDocument) => this.applyFrom(doc));
    await loadSettings();
  }

  /** Flip the theme: update the document, let the applier do the writing. */
  async toggle(): Promise<void> {
    await updateSettings({ theme: this.theme === 'dark' ? 'Light' : 'Dark' });
  }

  /** The label the toggle button shows: the theme a click MOVES TO. */
  get nextLabel(): string {
    return this.theme === 'dark' ? 'Light' : 'Dark';
  }

  /**
   * Cycle the eight named accents. A custom hex is not in the cycle, so the
   * toggle from a custom value lands on the first swatch — the switch always
   * lands on something the CSS declares.
   */
  async toggleColor(): Promise<void> {
    const current = isNamedAccent(this.accent) ? this.accent : null;
    await updateSettings({ colorScheme: nextAccent(current) });
  }

  /** Adopt a custom hex as the accent (the Settings pane's colour input). */
  async setCustomAccent(hex: string): Promise<void> {
    await updateSettings({ colorScheme: CUSTOM_COLOR_SCHEME, accentColor: hex.toUpperCase() });
  }

  /** The hex to show in the colour input when a custom accent is active. */
  get customHex(): string {
    return this.accent.startsWith('#') ? this.accent : CUSTOM_ACCENT_SEED;
  }

  private applyFrom(doc: SettingsDocument): void {
    this.theme = doc.theme === 'Light' ? 'light' : 'dark';
    this.accent = effectiveAccentName(doc);
    this.apply();
  }

  private apply(): void {
    if (typeof document === 'undefined') return;
    applyAppearance(document.documentElement, this.theme, this.accent);
  }
}

export const theme = new ThemeStore();
