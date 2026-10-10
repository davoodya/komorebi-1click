// The frontend's view of the single registry table. Rust owns the table; this
// store only fetches it and hands rows to the shell, so the GUI cannot disagree
// with the CLI about what a verb is (ADR-0013).
import { listTabs, listVerbs, type TabDefinition, type VerbDefinition } from './ipc';

class RegistryStore {
  verbs = $state<VerbDefinition[]>([]);
  tabs = $state<TabDefinition[]>([]);
  /** True once a load attempt has finished, successfully or not. */
  loaded = $state(false);
  error = $state('');

  async load(): Promise<void> {
    try {
      const [verbs, tabs] = await Promise.all([listVerbs(), listTabs()]);
      this.verbs = verbs;
      this.tabs = tabs;
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
 * The tab the shell currently renders.
 *
 * Ticket 03 delivered the registry's tab grouping; ticket 04 replaces this
 * constant with the real eight-tab strip. Until then the shell renders ONE tab —
 * and it renders that tab's OWN rows, taken from the registry, rather than every
 * declared verb. The distinction matters: the tracer's placeholder returned the
 * whole table, which was exact with two verbs and would now draw an
 * administrative verb like `uninstall` inside the Debugging tab.
 */
export const CURRENT_TAB = 'Debugging' as const;

/**
 * The rows belonging to a tab, in registry order.
 *
 * Two filters, both from the registry rather than from the view:
 * the row must belong to this tab, and it must not be suppressed in favour of a
 * more specific row (`startup`, `ahk`, `ahk-enable`, `ahk-disable` are CLI-only
 * rows with no row of their own).
 */
export function rowsForTab(verbs: VerbDefinition[], tab: string): VerbDefinition[] {
  return verbs.filter((verb) => verb.tab === tab && verb.renderInGui);
}
