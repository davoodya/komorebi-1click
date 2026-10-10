<script lang="ts">
  /**
   * Ticket 06 — the Settings tab's custom surface.
   *
   * The tab's registry rows render through the shell like every other tab;
   * this component carries only what the registry cannot express: the two
   * custom actions. Open Folder reveals the settings DIRECTORY (a .json would
   * otherwise open in whatever program the user associated with JSON), and
   * Factory Reset asks for confirmation and restores every default.
   *
   * Neither action runs a script — they are pane actions, and the busy() state
   * is this pane's own so a verb's run cannot be confused with them.
   */
  import {
    busy,
    settingsDocument,
    lastQuarantine,
    revealSettings,
    resetSettings,
    settingsPath,
    status,
  } from '../lib/settings.svelte.ts';
  import { currentAccent, hasCustomAccent } from '../lib/settings.svelte.ts';
  import { theme } from '../lib/theme.svelte.ts';

  let confirming = $state(false);
  let revealOpen = $state(false);

  const accentLabel = $derived(hasCustomAccent() ? currentAccent() : settingsDocument.colorScheme);

  async function factoryReset(): Promise<void> {
    await resetSettings();
    confirming = false;
  }

  const statusText = $derived.by(() => {
    switch (status().kind) {
      case 'saved':
        return 'Preferences saved.';
      case 'reset':
        return 'Every preference restored to its default.';
      case 'quarantined':
        return `The settings file was corrupt and was kept as ${status.file} — defaults are in use until you save.`;
      case 'revealed':
        return 'Opened the settings folder in Explorer.';
      case 'error':
        return `Settings error: ${status.message}`;
      default:
        return lastQuarantine() ? `Previous corruption kept as ${lastQuarantine()}.` : '';
    }
  });
</script>

<div class="settings-pane">
  {#if statusText}
    <p class="settings-status" class:settings-status-error={status().kind === 'error'} role="status">
      {statusText}
    </p>
  {/if}

  <div class="settings-line">
    <span class="settings-label">Settings file</span>
    <code class="settings-path" data-testid="settings-path">{settingsPath() || 'resolving…'}</code>
  </div>

  <div class="settings-line">
    <span class="settings-label">Accent in use</span>
    <code class="settings-path" data-testid="settings-accent">{accentLabel}</code>
  </div>

  <div class="settings-line">
    <span class="settings-label">Custom accent</span>
    <input
      class="settings-color"
      type="color"
      data-testid="accent-color"
      value={theme.customHex}
      disabled={busy()}
      oninput={(event) => void theme.setCustomAccent(event.currentTarget.value)}
    />
    <button class="btn" type="button" data-testid="toggle-color" disabled={busy()} onclick={() => void theme.toggleColor()}>
      Toggle Color
    </button>
  </div>

  <div class="settings-actions">
    <button
      class="btn"
      type="button"
      data-testid="open-folder"
      disabled={busy()}
      onclick={() => {
        revealOpen = !revealOpen;
        void revealSettings();
      }}
    >
      Open Folder
    </button>

    {#if !confirming}
      <button
        class="btn btn-danger"
        type="button"
        data-testid="factory-reset"
        disabled={busy()}
        onclick={() => (confirming = true)}
      >
        Factory Reset
      </button>
    {:else}
      <!--
        The confirmation is inline, on the same button, with the exact promise
        the WPF dialog makes: every preference, immediately, no restart needed.
      -->
      <span class="settings-confirm" role="alertdialog" aria-label="Confirm factory reset">
        <span class="settings-confirm-text">Restore every default? No restart is needed.</span>
        <button
          class="btn btn-danger"
          type="button"
          data-testid="factory-reset-confirm"
          disabled={busy()}
          onclick={() => void factoryReset()}
        >
          Yes, reset everything
        </button>
        <button class="btn" type="button" data-testid="factory-reset-cancel" onclick={() => (confirming = false)}>
          Cancel
        </button>
      </span>
    {/if}
  </div>

  {#if revealOpen}
    <p class="settings-hint">
      Explorer opens at the <strong>folder</strong>; the file is
      <code>{settingsPath().split(/[\\/]/).pop()}</code> inside it.
    </p>
  {/if}
</div>

<style>
  .settings-pane {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 10px 12px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: var(--surface-2);
    margin: 8px 0;
  }

  .settings-status {
    margin: 0;
    font-size: 12px;
    color: var(--muted);
  }

  .settings-status-error {
    color: var(--danger);
  }

  .settings-line {
    display: flex;
    align-items: baseline;
    gap: 8px;
    min-width: 0;
  }

  .settings-label {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--muted);
    flex: 0 0 auto;
  }

  .settings-path {
    font-size: 12px;
    color: var(--text);
    word-break: break-all;
    min-width: 0;
  }

  .settings-color {
    inline-size: 2.2rem;
    block-size: 1.5rem;
    padding: 0;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm, 4px);
    background: var(--surface-3);
  }

  .settings-actions {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .settings-confirm {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 4px 8px;
    border: 1px solid var(--danger);
    border-radius: 6px;
  }

  .settings-confirm-text {
    font-size: 12px;
    color: var(--danger);
  }

  .settings-hint {
    margin: 0;
    font-size: 11px;
    color: var(--muted);
  }
</style>
