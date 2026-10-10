<script lang="ts">
  import { dispatchVerb } from '../lib/dispatch';
  import { filterNumericValue } from '../lib/format';
  import { console_ } from '../lib/console.svelte.ts';
  import type { RowState } from '../lib/rows.svelte.ts';

  let { row }: { row: RowState } = $props();

  const verb = $derived(row.verb);
  const busy = $derived(console_.busy);

  /**
   * Numeric rows accept digits only.
   *
   * The filter runs on the VALUE, not on a keydown handler, so a paste, a
   * drag-drop or an IME composition cannot smuggle a non-digit in — the same
   * rule the WPF build enforced in its row model rather than in its view. The
   * rule itself lives in format.ts, tested on its own (ASCII digits only, an
   * empty value stays empty), and this handler only applies it to the box.
   */
  function onInput(event: Event) {
    const box = event.currentTarget as HTMLInputElement;
    const raw = box.value;
    const next = filterNumericValue(raw, verb.numericOnly);
    if (next !== raw) box.value = next;
    row.value = next;
  }
</script>

<div class="row-card" data-running={busy}>
  <div class="row-grid">
    <div>
      <div class="row-label">{verb.label}</div>
      <div class="row-help">{verb.help}</div>
    </div>

    <div class="row-actions">
      {#if verb.isReadOnly}
        <span class="badge-readonly" title="This verb changes nothing on the system">Read-only</span>
      {/if}

      {#if row.acceptsValue}
        <input
          class="value-box"
          data-numeric={verb.numericOnly ? 'true' : 'false'}
          type="text"
          inputmode={verb.numericOnly ? 'numeric' : 'text'}
          placeholder={verb.hint || 'value'}
          aria-label="{verb.label} value"
          value={row.value}
          oninput={onInput}
          disabled={busy}
        />
      {/if}

      <button
        class="btn btn-primary"
        type="button"
        disabled={busy}
        onclick={() => dispatchVerb(verb, row.args())}
      >
        {verb.actionLabel || verb.label}
      </button>
    </div>
  </div>
</div>
