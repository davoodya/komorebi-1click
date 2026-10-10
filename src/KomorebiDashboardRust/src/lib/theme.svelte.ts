// Ticket 12 — the theme switcher's state.
//
// The switch applies immediately and remembers the choice, so the store owns
// three things: the current theme, the act of applying it to the document
// (through the pure applyAppearance), and the persistence. Outside the shell
// (plain `vite dev`) there is no localStorage to speak of and the session
// choice still applies — it just does not survive a reload.
import { STORAGE_KEYS, applyAppearance, readAppearance, resolveTheme } from './theme';

const THEME_KEY = STORAGE_KEYS.theme;

class ThemeStore {
  theme = $state('dark');

  /** Where the choice is remembered when the host allows it. */
  private storage(): Storage | null {
    try {
      return globalThis.localStorage ?? null;
    } catch {
      // A locked-down or non-browser host: the shell still works.
      return null;
    }
  }

  /** Read the remembered choice and apply it. Called once at shell start. */
  load(): void {
    this.theme = readAppearance(this.storage() ?? memoryStorage()).theme;
    this.apply();
  }

  /** The runtime switch: flip, apply, remember. */
  toggle(): void {
    this.theme = resolveTheme(this.theme);
    this.apply();
    this.storage()?.setItem(THEME_KEY, this.theme);
  }

  /** The label the toggle button shows: the theme a click MOVES TO. */
  get nextLabel(): string {
    return this.theme === 'dark' ? 'Light' : 'Dark';
  }

  private apply(): void {
    if (typeof document === 'undefined') return;
    applyAppearance(document.documentElement, this.theme, readAppearance(this.storage() ?? memoryStorage()).accent);
  }
}

/** A throwing-free stand-in when localStorage is unavailable. */
function memoryStorage(): Storage {
  const map = new Map<string, string>();
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

export const theme = new ThemeStore();
