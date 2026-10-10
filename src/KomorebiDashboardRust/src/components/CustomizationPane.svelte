<script lang="ts">
  /**
   * Ticket 11 — the Customization tab: the complete appearance surface.
   *
   * PREVIEW NOW, PERSIST ON APPLY — with the WPF's own reasoning: theme,
   * accent and typeface are applied to the live window as soon as they change,
   * because seeing them IS the decision; asking the user to press Apply before
   * they can see an accent colour would be absurd. What Apply adds is
   * PERSISTENCE: the console-height slider previews live and only Apply (or
   * its own release) writes the settings document, so every control here
   * survives a restart through the same document the Settings tab writes.
   *
   * Nothing in this tab touches komorebi, whkd, YASB or AutoHotkey.
   */
  import { ACCENTS } from '../lib/tokens';
  import TypographyControls from './TypographyControls.svelte';
  import { console_ } from '../lib/console.svelte.ts';
  import { CONSOLE_MIN_PERCENT, CONSOLE_MAX_PERCENT } from '../lib/tokens';
  import { resetSettings, settingsDocument, updateSettings } from '../lib/settings.svelte.ts';
  import { theme } from '../lib/theme.svelte.ts';

  /** The slider's position: the live preview, which Apply persists. */
  let sliderPercent = $state(console_.percent);

  // The document's value is the source of truth; a reset or a startup apply
  // moves the slider with it.
  $effect(() => {
    sliderPercent = settingsDocument.consolePercent;
  });

  const sliderDirty = $derived(sliderPercent !== settingsDocument.consolePercent);

  function previewSlider(value: number): void {
    // Preview only: the shared pane moves, nothing is written.
    console_.setPercent(value);
  }

  /** Persist the pane-local preview: one document write, every field. */
  async function applySettings(): Promise<void> {
    await updateSettings({ consolePercent: sliderPercent });
  }

  async function resetDefaults(): Promise<void> {
    // The document's own reset: defaults restored AND applied immediately
    // (the settings store runs the appearance applier on the fresh document).
    await resetSettings();
    sliderPercent = settingsDocument.consolePercent;
  }

  // The document's colourScheme is the single truth: a named swatch or a
  // '#rrggbb' behind the Custom sentinel.
  function isActiveAccent(name: string): boolean {
    return settingsDocument.colorScheme === name;
  }

  /** A swatch writes the document — the appearance's single writer. */
  async function pickAccent(name: string): Promise<void> {
    await updateSettings({ colorScheme: name });
  }
</script>

<section class="customization-pane" data-testid="customization-pane">
  <div class="custom-section">
    <h3 class="custom-title">Theme</h3>
    <div class="custom-row">
      <button class="btn" type="button" data-testid="custom-theme-toggle" onclick={() => theme.toggle()}>
        Switch to {theme.nextLabel.toLowerCase()} theme
      </button>
      <span class="custom-note">The header carries the same switch.</span>
    </div>
  </div>

  <div class="custom-section">
    <h3 class="custom-title">Accent</h3>
    <div class="custom-swatches" role="group" aria-label="Accent colour">
      {#each ACCENTS as accent (accent)}
        <button
          class="swatch"
          class:swatch-active={isActiveAccent(accent)}
          type="button"
          data-testid={`swatch-${accent.toLowerCase()}`}
          aria-label={accent}
          aria-pressed={isActiveAccent(accent)}
          title={accent}
          onclick={() => void pickAccent(accent)}
        ></button>
      {/each}
    </div>
    <div class="custom-row">
      <label class="custom-label" for="custom-hex">Custom</label>
      <input
        id="custom-hex"
        type="color"
        data-testid="custom-accent-color"
        value={theme.customHex}
        oninput={(event) => void theme.setCustomAccent(event.currentTarget.value)}
      />
      <span class="custom-note">Writes through the document; a three-digit hex is rejected.</span>
    </div>
  </div>

  <div class="custom-section">
    <h3 class="custom-title">Console height</h3>
    <div class="custom-row">
      <input
        type="range"
        min={CONSOLE_MIN_PERCENT}
        max={CONSOLE_MAX_PERCENT}
        step={1}
        value={sliderPercent}
        data-testid="console-slider"
        aria-label="Console height"
        oninput={(event) => previewSlider(Number(event.currentTarget.value))}
        onchange={() => void applySettings()}
      />
      <output class="custom-note" data-testid="console-slider-value">{sliderPercent}%</output>
    </div>
    <p class="custom-note">The shared pane every tab uses, between 10% and 60%.</p>
  </div>

  <TypographyControls />

  <div class="custom-section custom-actions">
    <button
      class="btn"
      type="button"
      data-testid="custom-apply"
      disabled={!sliderDirty}
      onclick={() => void applySettings()}
    >
      Apply Settings
    </button>
    <button class="btn" type="button" data-testid="custom-reset" onclick={() => void resetDefaults()}>
      Reset to defaults
    </button>
    {#if sliderDirty}
      <span class="custom-note">Apply keeps the console height for the next launch.</span>
    {/if}
  </div>
</section>

<style>
  .customization-pane {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .custom-section {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .custom-title {
    margin: 0;
    font-size: calc(var(--ui-font-size) * var(--ui-scale) * 1);
  }

  .custom-row {
    display: flex;
    align-items: center;
    gap: 10px;
    flex-wrap: wrap;
  }

  .custom-label {
    color: var(--muted-foreground);
  }

  .custom-note {
    color: var(--muted-foreground);
    font-size: calc(var(--ui-font-size) * var(--ui-scale) * 0.85);
  }

  .custom-swatches {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
  }

  .swatch {
    inline-size: 26px;
    block-size: 26px;
    border-radius: 50%;
    border: 2px solid var(--border);
    cursor: pointer;
    padding: 0;
  }

  .swatch-active {
    border-color: var(--foreground);
  }

  .custom-actions {
    flex-direction: row;
    align-items: center;
  }
</style>
