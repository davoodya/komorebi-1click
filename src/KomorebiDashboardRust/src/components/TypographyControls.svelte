<script lang="ts">
  /**
   * Ticket 08 — the typography controls.
   *
   * Five controls preview LIVE (the CSS custom properties are written the
   * moment a value changes) and persist only when APPLIED — the ticket's exact
   * contract. Revert drops the preview back to what the document holds.
   *
   * The font lists are two tiers: the standard list opens instantly (no
   * enumeration ever happens to open it), and the sentinel — last, always —
   * expands the full installed set ONCE, off the UI thread, cached for the
   * rest of the session. The sentinel itself can never become the applied
   * value: picking it expands the list and leaves the current font selected.
   */
  import {
    ALL_FONTS_SENTINEL,
    enumerateInstalledFonts,
    monospacedWithSentinel,
    standardWithSentinel
  } from '../lib/fonts';
  import { applyTypography, scaleMultiplier } from '../lib/theme';
  import { busy, loaded, settingsDocument, updateSettings } from '../lib/settings.svelte.ts';

  /**
   * True while the document may overwrite the preview. False while the user
   * edits (a stray backend save must not stomp their in-progress preview) and
   * true again after Apply or Revert.
   */
  let allowDocOverwrite = $state(false);

  /** Preview state — deliberately NOT the document until Apply. */
  let fontFamily = $state(settingsDocument.fontFamily);
  let fontSize = $state(settingsDocument.fontSize);
  let consoleFontFamily = $state(settingsDocument.consoleFontFamily);
  let consoleFontSize = $state(settingsDocument.consoleFontSize);
  let uiScale = $state(String(settingsDocument.uiScale));

  /** The expanded (enumerated) lists, or null while still tier-1. */
  let expandedApp = $state<string[] | null>(null);
  let expandedConsole = $state<string[] | null>(null);
  /** True while the one-time enumeration is running. */
  let expanding = $state(false);

  const appFonts = $derived(expandedApp ?? standardWithSentinel());
  const consoleFonts = $derived(expandedConsole ?? monospacedWithSentinel());

  /** A preview differs from the document only when Apply has something to write. */
  const dirty = $derived(
    fontFamily !== settingsDocument.fontFamily ||
      fontSize !== settingsDocument.fontSize ||
      consoleFontFamily !== settingsDocument.consoleFontFamily ||
      consoleFontSize !== settingsDocument.consoleFontSize ||
      Number(uiScale) !== settingsDocument.uiScale
  );

  /**
   * The document is authoritative when it changes UNDER the preview: a factory
   * reset or a first load replaces the preview wholesale.
   */
  $effect(() => {
    const doc = settingsDocument;
    if (dirty && !allowDocOverwrite) return;
    fontFamily = doc.fontFamily;
    fontSize = doc.fontSize;
    consoleFontFamily = doc.consoleFontFamily;
    consoleFontSize = doc.consoleFontSize;
    uiScale = String(doc.uiScale);
  });

  function preview(): void {
    if (typeof document === 'undefined') return;
    applyTypography(document.documentElement, {
      fontFamily,
      fontSize,
      consoleFontFamily,
      consoleFontSize,
      uiScale: Number(uiScale)
    });
  }

  /** Every change previews immediately — including the scale's own multiplication. */
  $effect(() => {
    void fontFamily;
    void fontSize;
    void consoleFontFamily;
    void consoleFontSize;
    void uiScale;
    if (loaded()) preview();
  });

  async function apply(): Promise<void> {
    allowDocOverwrite = true;
    await updateSettings({
      fontFamily,
      fontSize,
      consoleFontFamily,
      consoleFontSize,
      uiScale: Number(uiScale)
    });
  }

  function revert(): void {
    const doc = settingsDocument;
    fontFamily = doc.fontFamily;
    fontSize = doc.fontSize;
    consoleFontFamily = doc.consoleFontFamily;
    consoleFontSize = doc.consoleFontSize;
    uiScale = String(doc.uiScale);
    allowDocOverwrite = false;
    preview();
  }

  /**
   * The sentinel's action: expand this list once. The current font stays
   * selected — the sentinel is a doorway, never a value.
   */
  async function expand(which: 'app' | 'console'): Promise<void> {
    expanding = true;
    const installed = await enumerateInstalledFonts();
    const tier1 = which === 'app' ? standardWithSentinel() : monospacedWithSentinel();
    const merged = [...new Set([...tier1.slice(0, -1), ...installed])].sort((a, b) =>
      a.localeCompare(b, undefined, { sensitivity: 'base' })
    );
    if (which === 'app') expandedApp = merged;
    else expandedConsole = merged;
    expanding = false;
  }

  /** On change: a sentinel pick expands and is not kept as the value. */
  function onAppFont(event: Event): void {
    const value = (event.currentTarget as HTMLSelectElement).value;
    if (value === ALL_FONTS_SENTINEL) {
      void expand('app');
      return;
    }
    fontFamily = value;
  }

  function onConsoleFont(event: Event): void {
    const value = (event.currentTarget as HTMLSelectElement).value;
    if (value === ALL_FONTS_SENTINEL) {
      void expand('console');
      return;
    }
    consoleFontFamily = value;
  }
</script>

<div class="typography" data-testid="typography-controls">
  <div class="typo-line">
    <span class="settings-label">App font</span>
    <select
      class="typo-select"
      data-testid="app-font"
      value={fontFamily}
      onchange={onAppFont}
      disabled={busy() || expanding}
    >
      {#each appFonts as name (name)}
        <option value={name}>{name}</option>
      {/each}
    </select>
    <input
      class="typo-number"
      type="number"
      min="8"
      max="40"
      data-testid="app-font-size"
      value={fontSize}
      oninput={(event) => (fontSize = Number(event.currentTarget.value))}
      disabled={busy()}
    />
  </div>

  <div class="typo-line">
    <span class="settings-label">Console font</span>
    <select
      class="typo-select"
      data-testid="console-font"
      value={consoleFontFamily}
      onchange={onConsoleFont}
      disabled={busy() || expanding}
    >
      {#each consoleFonts as name (name)}
        <option value={name}>{name}</option>
      {/each}
    </select>
    <input
      class="typo-number"
      type="number"
      min="8"
      max="32"
      data-testid="console-font-size"
      value={consoleFontSize}
      oninput={(event) => (consoleFontSize = Number(event.currentTarget.value))}
      disabled={busy()}
    />
  </div>

  <div class="typo-line">
    <span class="settings-label">UI scale</span>
    {#each ['100', '125', '150'] as scale (scale)}
      <label class="typo-radio">
        <input
          type="radio"
          name="ui-scale"
          value={scale}
          checked={uiScale === scale}
          onchange={() => (uiScale = scale)}
          disabled={busy()}
        />
        {scale}% <span class="typo-preview" style="font-size: {Number(scale) / 10}px">Aa</span>
      </label>
    {/each}
  </div>

  <div class="settings-actions">
    <button class="btn" type="button" data-testid="typo-apply" disabled={!dirty || busy()} onclick={() => void apply()}>
      Apply
    </button>
    <button class="btn" type="button" data-testid="typo-revert" disabled={!dirty} onclick={revert}>
      Revert
    </button>
    <span class="typo-hint">
      {#if busy()}
        Saving…
      {:else if expanding}
        Enumerating installed fonts…
      {:else if dirty}
        Previewing — Apply to persist across restarts
      {:else}
        Applied
      {/if}
    </span>
  </div>

  <p class="typo-note">
    The scale multiplies through <code>--ui-scale</code> ({uiScale}% → &times;{scaleMultiplier(Number(uiScale))}); the
    preview applies instantly and nothing is written until Apply.
  </p>
</div>

<style>
  .typography {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin: 4px 0 8px;
  }

  .typo-line {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }

  .typo-select {
    flex: 1 1 auto;
    min-width: 0;
    font-size: 12px;
    color: var(--text);
    background: var(--surface-3);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm, 4px);
    padding: 3px 6px;
  }

  .typo-number {
    inline-size: 3.5rem;
    font-size: 12px;
    color: var(--text);
    background: var(--surface-3);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm, 4px);
    padding: 3px 6px;
  }

  .typo-radio {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: 12px;
    color: var(--text);
  }

  .typo-preview {
    color: var(--muted);
  }

  .typo-hint {
    font-size: 11px;
    color: var(--muted);
  }

  .typo-note {
    margin: 0;
    font-size: 11px;
    color: var(--muted);
  }
</style>
