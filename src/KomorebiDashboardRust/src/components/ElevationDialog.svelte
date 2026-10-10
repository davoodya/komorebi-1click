<script lang="ts">
  // Ticket 12 — the elevation dialog.
  //
  // The ticket names this dialog exactly: titled "Rerun as Administrator",
  // with OK / Rerun as Administrator / Cancel, naming the specific features
  // that need Administrator. The names come from the registry rows (generated,
  // never typed) and the title and buttons are the constants from elevation.ts
  // — a dialog that renamed itself would be a second contract.
  //
  // There is deliberately no error state here: a declined UAC prompt returns
  // cleanly per ticket 05, which this component honours by closing (the
  // backend's relaunch command documents the same contract).
  import { ELEVATION_DIALOG_BUTTONS, ELEVATION_DIALOG_TITLE } from '../lib/elevation';
  import { elevation } from '../lib/elevation.svelte.ts';

  let { features }: { features: string[] } = $props();

  const waiting = $derived(elevation.pending);
</script>

{#if waiting}
  <div class="dialog-backdrop" role="presentation">
    <div
      class="dialog"
      role="alertdialog"
      aria-modal="true"
      aria-labelledby="elevation-title"
      onclick={(event) => event.stopPropagation()}
    >
      <div class="dialog-title" id="elevation-title">{ELEVATION_DIALOG_TITLE}</div>

      <p class="dialog-body">
        <strong>{waiting.verb.label}</strong> needs Administrator, and this instance of the
        dashboard is not elevated.
      </p>

      <!-- The feature list is generated from the registry rows that carry
           RequiresAdmin — the same names the backend's own refusal carries. -->
      <p class="dialog-body muted">Features that need Administrator:</p>
      <ul class="dialog-features">
        {#each features as feature (feature)}
          <li>{feature}</li>
        {/each}
      </ul>

      <div class="dialog-actions">
        <button class="btn" type="button" onclick={() => elevation.acknowledge()}>
          {ELEVATION_DIALOG_BUTTONS[0]}
        </button>
        <button
          class="btn btn-primary"
          type="button"
          onclick={() => void elevation.relaunchElevated()}
        >
          {ELEVATION_DIALOG_BUTTONS[1]}
        </button>
        <button class="btn" type="button" onclick={() => elevation.dismiss()}>
          {ELEVATION_DIALOG_BUTTONS[2]}
        </button>
      </div>
    </div>
  </div>
{/if}
