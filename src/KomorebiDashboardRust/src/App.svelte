<script lang="ts">
  import { onMount } from 'svelte';
  import logo from './assets/logo.png';
  import TabLayout from './components/TabLayout.svelte';
  import VerbRow from './components/VerbRow.svelte';
  import ConsolePane from './components/ConsolePane.svelte';
  import { console_ } from './lib/console.svelte.ts';
  import { onOutput } from './lib/ipc';
  import { appInfo, type AppInfo } from './lib/ipc';
  import { registry, resolveActiveTab, rowsForTab, tabSelection } from './lib/registry.svelte.ts';
  import { rowsFrom, type RowState } from './lib/rows.svelte.ts';

  let info = $state<AppInfo | null>(null);
  let rows = $state<RowState[]>([]);
  /** Plain cache, deliberately not reactive: rewriting it must not re-trigger. */
  let cache: RowState[] = [];

  // The tab the shell renders: the user's selection resolved against the
  // backend's own tab list, falling back to the first declared tab so the shell
  // always shows a real tab (and none at all before the registry loads).
  const activeTab = $derived(resolveActiveTab(registry.tabs, tabSelection.selected));
  const visibleRows = $derived(activeTab ? rowsForTab(registry.verbs, activeTab.id) : []);

  // The registry arrives asynchronously, so rows are derived from it. Existing
  // RowState objects are reused, which is what keeps a typed value when the
  // registry is re-read.
  $effect(() => {
    cache = rowsFrom(visibleRows, cache);
    rows = cache;
  });

  onMount(() => {
    void registry.load();
    appInfo()
      .then((value) => (info = value))
      .catch(() => (info = null));

    // The output subscription is what turns the backend's ~50 ms batches into
    // visible text. It is registered once, for the process's lifetime, because
    // the console is shared: a listener per tab would append every batch
    // several times over.
    let unsubscribe: (() => void) | undefined;
    onOutput((batch) => console_.append(batch))
      .then((off) => (unsubscribe = off))
      .catch(() => {
        // Outside the shell (plain `vite dev` in a browser) there is no event
        // channel; the UI stays usable and dispatch reports why it cannot run.
      });

    return () => unsubscribe?.();
  });

  const product = $derived(info?.product ?? 'Komorebi Admin Dashboard');
  const version = $derived(info?.version ?? '0.1.0');
</script>

<div class="app-shell">
  <header class="header-band">
    <img class="header-logo" src={logo} alt="" width="32" height="32" />
    <div>
      <div class="header-title">{product}</div>
      <div class="header-meta">
        Komorebi &middot; WHKD &middot; YASB &middot; AutoHotkey &middot; v{version}
      </div>
    </div>
  </header>

  <!--
    The strip: every tab the backend declares, in its order, with nothing added
    and none hidden. The panel resolves its id from the same list, so the
    selection can never point at a tab the backend does not declare.
  -->
  <div class="tab-strip" role="tablist" aria-label="Dashboard sections">
    {#each registry.tabs as tab (tab.id)}
      <button
        class="tab-button"
        type="button"
        role="tab"
        aria-selected={tab.id === activeTab?.id}
        onclick={() => tabSelection.select(tab.id)}
      >
        {tab.label}
      </button>
    {/each}
  </div>

  <TabLayout title={activeTab?.label ?? 'Loading'} description={activeTab?.description ?? ''}>
    {#if registry.error}
      <p class="tab-description console-line-stderr">
        Could not read the verb registry: {registry.error}
      </p>
    {:else if !registry.loaded}
      <p class="tab-description">Loading verbs...</p>
    {:else if visibleRows.length === 0}
      <!-- Customization and About are declared tabs with hand-built surfaces
           instead of registry verb rows, so an empty row list is the correct
           render for them rather than a broken grouping. -->
      <p class="tab-description">This tab carries no verb rows.</p>
    {:else}
      <div class="row-list">
        {#each rows as row (row.verb.verb)}
          <VerbRow {row} />
        {/each}
      </div>
    {/if}
    <ConsolePane />
  </TabLayout>
</div>
