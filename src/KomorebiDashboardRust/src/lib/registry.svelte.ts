// The frontend's view of the single registry table. Rust owns the table; this
// store only fetches it and hands rows to the shell, so the GUI cannot disagree
// with the CLI about what a verb is (ADR-0013).
import { listVerbs, type VerbDefinition } from './ipc';

class RegistryStore {
  verbs = $state<VerbDefinition[]>([]);
  /** True once a load attempt has finished, successfully or not. */
  loaded = $state(false);
  error = $state('');

  async load(): Promise<void> {
    try {
      this.verbs = await listVerbs();
      this.error = '';
    } catch (cause) {
      this.error = cause instanceof Error ? cause.message : String(cause);
    } finally {
      this.loaded = true;
    }
  }
}

export const registry = new RegistryStore();

/**
 * The tab the shell currently renders and its heading.
 *
 * The tracer bullet renders exactly one tab: both verbs it registers live in the
 * Debugging group. Ticket 04 replaces this constant with the registry's own tab
 * grouping and the eight real tabs; until then the shell must not draw eight tab
 * buttons with nothing behind them.
 */
export const TRACER_TAB = {
  id: 'debugging',
  label: 'Debugging',
  title: 'Debugging',
  description: 'Read-only health checks and the streaming test verb.'
} as const;

/**
 * The rows belonging to a tab, in registry order.
 *
 * Until ticket 03 lands the `renderInGui` flag, every declared verb gets a row.
 * Ticket 01 only registers two, and both do get a row, so this is exact today
 * and becomes a filter rather than a lie when the flag arrives.
 */
export function rowsForTab(verbs: VerbDefinition[]): VerbDefinition[] {
  return verbs;
}
