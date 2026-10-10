<script lang="ts">
  /**
   * Ticket 10 — the AutoHotkey tab.
   *
   * Three surfaces, one contract each:
   * - The script rows carry the manifest metadata and the state on disk, with
   *   a staged selection that writes nothing until Apply. Apply commits
   *   serially and stops at the first failure.
   * - The registry's own bulk rows (enable/disable all) and diagnostic rows
   *   render through the SHARED VerbRow component like every other row — a
   *   new check appears by being added to the registry and nowhere else.
   * - After a bulk verb the rows re-read the disk state, so the UI shows what
   *   actually happened instead of assuming the write succeeded.
   */
  import { onMount } from 'svelte';
  import { ahk, setAhkVerbs } from '../lib/ahk.svelte.ts';
  import { registry } from '../lib/registry.svelte.ts';
  import { rowsFrom } from '../lib/rows.svelte.ts';
  import { onRunFinished } from '../lib/dispatch';
  import VerbRow from './VerbRow.svelte';

  const BULK = ['ahk-enable-all', 'ahk-disable-all'];
  const DIAGNOSTICS = ['ahk-versions', 'ahk-newfile-check', 'ahk-diagnose'];

  let bulkRows = $state(rowsFrom([], []));
  let diagnosticRows = $state(rowsFrom([], []));

  /** Set once the registry has arrived; the two per-script verbs never change. */
  let verbsWired = false;

  onMount(() => {
    // The rows are read at open time — the state file is the scripts' own, and
    // a cached guess would be exactly the lie this ticket forbids.
    void ahk.load();
    // Bulk verbs run through the shared row component; their completion is
    // what triggers the re-read. One seam, no pane-local copy of dispatch.
    const off = onRunFinished((verb) => {
      if (verb.startsWith('ahk-')) void ahk.refreshAfterBulkVerb();
    });
    return off;
  });

  // The registry arrives asynchronously; both groups come from it like every
  // other tab's rows, and the RowState objects persist across re-renders so a
  // typed value is never dropped.
  $effect(() => {
    const byVerb = new Map(registry.verbs.map((v) => [v.verb, v]));
    const pick = (names: string[]) =>
      names.map((name) => byVerb.get(name)).filter((v): v is NonNullable<typeof v> => v !== undefined);
    bulkRows = rowsFrom(pick(BULK), bulkRows);
    diagnosticRows = rowsFrom(pick(DIAGNOSTICS), diagnosticRows);

    // The registry's per-script verbs are `render_in_gui: false` rows: the
    // pane drives them, so the pane looks them up — once, when the registry
    // has arrived, because a child's onMount runs before the shell's load.
    if (verbsWired) return;
    const enable = byVerb.get('ahk-enable');
    const disable = byVerb.get('ahk-disable');
    if (!enable || !disable) return;
    verbsWired = true;
    setAhkVerbs((state) => (state === 'enabled' ? enable : disable));
  });
</script>

<section class="ahk-pane" data-testid="ahk-pane">
  <div class="ahk-script-list">
    {#each ahk.rows as row (row.key)}
      <article class="ahk-card" data-testid={`ahk-row-${row.key}`}>
        <header class="ahk-card-head">
          <div>
            <h3 class="ahk-card-title">{row.label}</h3>
            <p class="ahk-card-desc">{row.description}</p>
          </div>
          <span class="ahk-badge" title="The hotkey this script binds">{row.hotkey}</span>
        </header>
        <div class="ahk-card-controls">
          <!--
            One radio group per row: the group name carries the script key, so
            two rows can never steal each other's selection.
          -->
          <div role="radiogroup" aria-label={`${row.label} state`}>
            <label>
              <input
                type="radio"
                name={`ahk-${row.key}`}
                checked={row.isEnabled}
                disabled={ahk.busy}
                onchange={() => (row.isEnabled = true)}
              />
              Enable
            </label>
            <label>
              <input
                type="radio"
                name={`ahk-${row.key}`}
                checked={!row.isEnabled}
                disabled={ahk.busy}
                onchange={() => (row.isEnabled = false)}
              />
              Disable
            </label>
          </div>
          <p class="ahk-card-status" data-dirty={row.isDirty}>{row.statusText}</p>
        </div>
      </article>
    {/each}
  </div>

  <div class="ahk-apply-bar">
    <button
      class="btn"
      type="button"
      data-testid="ahk-apply"
      disabled={ahk.dirtyCount === 0 || ahk.busy}
      onclick={() => void ahk.apply()}
    >
      Apply
    </button>
    <p class="ahk-hint" data-testid="ahk-hint">{ahk.applyHint}</p>
    {#if ahk.status}
      <p class="ahk-status" data-testid="ahk-status">{ahk.status}</p>
    {/if}
    {#if ahk.loadError}
      <p class="ahk-status ahk-status-error" data-testid="ahk-load-error">{ahk.loadError}</p>
    {/if}
  </div>

  {#if bulkRows.length > 0 || diagnosticRows.length > 0}
    <div class="ahk-registry-rows">
      <div class="row-list">
        {#each bulkRows as row (row.verb.verb)}
          <VerbRow {row} />
        {/each}
        {#each diagnosticRows as row (row.verb.verb)}
          <VerbRow {row} />
        {/each}
      </div>
    </div>
  {/if}
</section>

<style>
  .ahk-pane {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .ahk-script-list {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .ahk-card {
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 10px 12px;
    background: var(--card);
  }

  .ahk-card-head {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 10px;
  }

  .ahk-card-title {
    margin: 0;
    font-size: calc(var(--ui-font-size) * var(--ui-scale) * 0.95);
  }

  .ahk-card-desc {
    margin: 2px 0 0;
    color: var(--muted-foreground);
    font-size: calc(var(--ui-font-size) * var(--ui-scale) * 0.85);
  }

  .ahk-badge {
    border: 1px solid var(--border);
    border-radius: 999px;
    padding: 2px 10px;
    color: var(--muted-foreground);
    font-family: var(--console-font);
    font-size: calc(var(--console-font-size) * var(--ui-scale) * 0.8);
    white-space: nowrap;
  }

  .ahk-card-controls {
    display: flex;
    align-items: center;
    gap: 16px;
    margin-block-start: 8px;
    flex-wrap: wrap;
  }

  .ahk-card-controls label {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    cursor: pointer;
  }

  .ahk-card-status {
    margin: 0;
    color: var(--muted-foreground);
    font-size: calc(var(--ui-font-size) * var(--ui-scale) * 0.85);
  }

  .ahk-card-status[data-dirty='true'] {
    color: var(--accent);
  }

  .ahk-apply-bar {
    display: flex;
    align-items: center;
    gap: 12px;
    flex-wrap: wrap;
  }

  .ahk-hint,
  .ahk-status {
    margin: 0;
    color: var(--muted-foreground);
    font-size: calc(var(--ui-font-size) * var(--ui-scale) * 0.85);
  }

  .ahk-status-error {
    color: var(--accent);
  }
</style>
