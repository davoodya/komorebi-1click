/**
 * Ticket 06 — the Settings pane's store.
 *
 * The backend owns the file; this store owns the INTERACTION: load once at
 * startup, keep the document, apply the appearance half of it (theme, accent,
 * scale, console share), and give the two custom actions a single place to
 * report from.
 *
 * The backend is injectable so `settings.spec.ts` can drive the store in plain
 * node with a fake — the Tauri IPC layer is exercised by the double-click
 * smoke test, not by the unit suite.
 */

import {
  CUSTOM_COLOR_SCHEME,
  SETTINGS_DEFAULTS,
  clampToBand,
  effectiveAccentName,
  isNamedAccent,
  type SettingsDocument,
} from './settings';
import { parseStoredAccentHex } from './theme';

/** The shape of the backend this store needs — the ipc module supplies it. */
export interface SettingsBackend {
  getSettings(): Promise<{ settings: SettingsDocument; quarantined: string | null }>;
  saveSettings(settings: SettingsDocument): Promise<string>;
  resetSettings(): Promise<string>;
  revealSettingsFolder(): Promise<string>;
}

/** What the pane last did, in its own words. */
export type SettingsStatus =
  | { kind: 'idle' }
  | { kind: 'saved' }
  | { kind: 'reset'; path: string }
  | { kind: 'quarantined'; file: string }
  | { kind: 'revealed'; folder: string }
  | { kind: 'error'; message: string };

/** Appearance application seam (theme.ts owns the actual attribute writes). */
export type ApplyAppearance = (doc: SettingsDocument) => void;

let backend: SettingsBackend | null = null;
let applyAppearance: ApplyAppearance = () => {};

/** Load the ipc backend lazily so tests never pull in Tauri. */
async function loadBackend(): Promise<SettingsBackend> {
  if (backend) return backend;
  const ipc = await import('./ipc');
  backend = {
    getSettings: () => ipc.getSettings(),
    saveSettings: (s) => ipc.saveSettings(s),
    resetSettings: () => ipc.resetSettings(),
    revealSettingsFolder: () => ipc.revealSettingsFolder(),
  };
  return backend;
}

/** The path of the settings file, shown from the backend's own answer. */
let _settingsPath = $state('');

/**
 * The document as it currently stands (normalized by the backend).
 * Named `settingsDocument`, not `document`: this module is imported by the
 * theme store, and shadowing the DOM global there is a footgun.
 */
export const settingsDocument = $state<SettingsDocument>({ ...SETTINGS_DEFAULTS });

/** A quarantine the last load defused — shown, never silent. */
let _lastQuarantine = $state<string | null>(null);

/** The pane's own status line. */
let _status = $state<SettingsStatus>({ kind: 'idle' });

/** True while a backend round-trip is in flight. */
let _busy = $state(false);

/** True once the first load has completed (drives the pane's spinner). */
let _loaded = $state(false);

/**
 * Install the appearance seam. Called once at startup with theme.ts's
 * applyTheme so the store never imports the theme module directly — no cycle,
 * and a test can pass a recording stub.
 */
export function setAppearanceApplier(fn: ApplyAppearance): void {
  applyAppearance = fn;
}

/** Override the backend (tests only). */
export function setBackend(fake: SettingsBackend | null): void {
  backend = fake;
}

/*
 * The store's surface, as read-only getters over the private state: Svelte
 * forbids exporting a module-level `$state` binding that gets REASSIGNED, and
 * every action above reassigns — the getters keep the reassignments internal
 * and the reactivity intact.
 */
export function settingsPath(): string {
  return _settingsPath;
}

export function lastQuarantine(): string | null {
  return _lastQuarantine;
}

export function status(): SettingsStatus {
  return _status;
}

export function busy(): boolean {
  return _busy;
}

export function loaded(): boolean {
  return _loaded;
}

/**
 * Load the document. The appearance half applies BEFORE first paint of the
 * pane, so a restarted app shows the user's theme, not a flash of default.
 *
 * A quarantine is surfaced as its own status kind: the user must learn that
 * their file was corrupt instead of wondering where their preferences went.
 */
export async function loadSettings(): Promise<void> {
  _busy = true;
  _status = { kind: 'idle' };
  try {
    const api = await loadBackend();
    const outcome = await api.getSettings();
    applyAppearance(outcome.settings);
    assignDocument(outcome.settings);
    _lastQuarantine = outcome.quarantined;
    if (outcome.quarantined) {
      _status = { kind: 'quarantined', file: outcome.quarantined };
    }
  } catch (e) {
    _status = { kind: 'error', message: describe(e) };
  } finally {
    _busy = false;
    _loaded = true;
  }
}

/**
 * Apply a partial update: normalize through the bands, write the whole
 * document, and apply the appearance half. A failed save leaves the in-memory
 * document UNCHANGED and says so — the backend stayed authoritative.
 */
export async function updateSettings(patch: Partial<SettingsDocument>): Promise<void> {
  const next = normalizedPatch(settingsDocument, patch);
  _busy = true;
  _status = { kind: 'idle' };
  try {
    const api = await loadBackend();
    await api.saveSettings(next);
    applyAppearance(next);
    assignDocument(next);
    _status = { kind: 'saved' };
  } catch (e) {
    _status = { kind: 'error', message: describe(e) };
  } finally {
    _busy = false;
  }
}

/**
 * Factory Reset: restore every default AND persist it, so the next launch
 * starts resolved. The confirmation itself lives in the pane — this function
 * performs, it does not ask.
 */
export async function resetSettings(): Promise<void> {
  _busy = true;
  _status = { kind: 'idle' };
  try {
    const api = await loadBackend();
    const path = await api.resetSettings();
    const fresh = { ...SETTINGS_DEFAULTS };
    applyAppearance(fresh);
    assignDocument(fresh);
    _lastQuarantine = null;
    _status = { kind: 'reset', path };
  } catch (e) {
    _status = { kind: 'error', message: describe(e) };
  } finally {
    _busy = false;
  }
}

/** Open Folder: reveal the settings DIRECTORY through the backend. */
export async function revealSettings(): Promise<void> {
  _status = { kind: 'idle' };
  try {
    const api = await loadBackend();
    const folder = await api.revealSettingsFolder();
    _status = { kind: 'revealed', folder };
  } catch (e) {
    _status = { kind: 'error', message: describe(e) };
  }
}

/** Show the settings file path from the backend's own app_info answer. */
export function setSettingsPath(path: string): void {
  _settingsPath = path;
}

/** The accent the UI should render right now: name or '#rrggbb'. */
export function currentAccent(doc = settingsDocument): string {
  return effectiveAccentName(doc);
}

/** True when the active accent is a custom hex rather than a named scheme. */
export function hasCustomAccent(doc = settingsDocument): boolean {
  return !isNamedAccent(currentAccent(doc));
}

/** The CUSTOM sentinel, re-exported for the pane's swatch list. */
export { CUSTOM_COLOR_SCHEME };

// ---------------------------------------------------------------------------
// internals
// ---------------------------------------------------------------------------

function normalizedPatch(doc: SettingsDocument, patch: Partial<SettingsDocument>): SettingsDocument {
  const next: SettingsDocument = { ...doc, ...patch };
  for (const key of ['fontSize', 'uiScale', 'consolePercent', 'consoleFontSize'] as const) {
    next[key] = clampToBand(key, Number(next[key]));
  }
  if (!isNamedAccent(next.colorScheme) && next.colorScheme !== CUSTOM_COLOR_SCHEME) {
    // An unknown scheme name is not a renderable accent — fall back, the same
    // way the backend does, rather than painting nothing.
    next.colorScheme = SETTINGS_DEFAULTS.colorScheme;
  }
  if (next.colorScheme === CUSTOM_COLOR_SCHEME) {
    // One normalization for both writers (toggle and colour input): the hex is
    // upper-case or it is dropped to the named default. An unknown NAME stays
    // what it is; only the hex's shape is enforced here.
    const hex = parseStoredAccentHex(next.accentColor);
    if (hex) next.accentColor = hex;
  }
  return next;
}

function assignDocument(doc: SettingsDocument): void {
  Object.assign(settingsDocument, doc);
}

function describe(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}
