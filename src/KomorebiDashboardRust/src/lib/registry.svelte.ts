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
 * The strip's selection, as reactive state the shell owns.
 *
 * Ticket 03 delivered the registry's tab grouping; ticket 04 replaces the
 * one-tab placeholder with this real eight-tab strip: the user's choice
 * lives here, and what renders is always resolved against the backend's own
 * tab list, so the shell can never show a tab the backend does not declare nor
 * blank out on a stale id.
 */
class TabSelectionStore {
  /** The tab id the user picked. Empty until they pick, or before load. */
  selected = $state('');

  select(id: string): void {
    this.selected = id;
  }
}

export const tabSelection = new TabSelectionStore();

/**
 * The tab to render: the selection when the backend still declares it,
 * otherwise the first declared tab, and nothing at all before the registry
 * loads (the strip itself iterates registry.tabs directly, so both the strip
 * and the panel resolve their id against the same list rather than trusting
 * the selection alone).
 */
export function resolveActiveTab(
  tabs: readonly TabDefinition[],
  selected: string
): TabDefinition | undefined {
  if (tabs.length === 0) return undefined;
  return tabs.find((tab) => tab.id === selected) ?? tabs[0];
}

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
