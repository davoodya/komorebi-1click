<script lang="ts">
  /**
   * Ticket 11 — the About tab.
   *
   * Read-only by design: it starts no script, so it is the one tab with nothing
   * for the console. Everything it reports is discovered by the backend
   * (app_info's own answers) or declared as constants here — the paths shown
   * are the paths the files are actually written to, because they come from
   * the same process that writes them.
   */
  import { AUTHOR, LINKS, PRODUCT_NAME, SUMMARY, copyText, versionLine } from '../lib/about';
  import { appInfo, openLink, revealFolder, revealSettingsFolder, type AppInfo } from '../lib/ipc';
  import { settingsPath } from '../lib/settings.svelte.ts';
  import { onMount } from 'svelte';

  let info = $state<AppInfo | null>(null);
  let copyState = $state('');

  onMount(() => {
    // The shell already fetched app_info; reusing its answers is free and
    // keeps ONE measurement of the running process.
    void appInfo()
      .then((value) => (info = value))
      .catch(() => (info = null));
  });

  const runtime = $derived(info?.runtimeDescription ?? 'Tauri · unknown runtime');

  /** The four paths, with the reveal action each one can take. */
  const PATHS = $derived([
    { label: 'Executable', value: info?.exePath ?? '(unavailable)', kind: 'exe' as const },
    { label: 'Scripts', value: info?.scriptsPath ?? '(unavailable)', kind: 'scripts' as const },
    { label: 'Settings', value: settingsPath() || info?.settingsPath || '(unavailable)', kind: null }
  ]);

  async function copyVersion(): Promise<void> {
    try {
      await navigator.clipboard.writeText(copyText(info));
      copyState = 'Version and path copied.';
    } catch {
      // The clipboard can be locked by another process; a failed copy is not
      // worth an error dialog.
      copyState = 'The clipboard refused the copy.';
    }
  }

  async function reveal(kind: 'exe' | 'scripts' | 'settings'): Promise<void> {
    try {
      if (kind === 'settings') await revealSettingsFolder();
      else await revealFolder(kind);
    } catch {
      // Non-fatal: the status line says it, the tab stays usable.
      copyState = 'Could not open that folder.';
    }
  }
</script>

<section class="about-pane" data-testid="about-pane">
  <div class="about-identity">
    <h2 class="about-title">{info?.product ?? PRODUCT_NAME}</h2>
    <p class="about-author">{AUTHOR}</p>
    <p class="about-version" data-testid="about-version">{versionLine(info)}</p>
    <p class="about-runtime" data-testid="about-runtime">{runtime}</p>
  </div>

  <p class="about-summary">{SUMMARY}</p>

  <div class="about-actions">
    <button class="btn" type="button" data-testid="about-copy" onclick={() => void copyVersion()}>
      Copy version
    </button>
    {#each LINKS as link (link.kind)}
      <button
        class="btn"
        type="button"
        data-testid={`about-link-${link.kind}`}
        onclick={() => void openLink(link.kind).then(() => {}, () => {})}
      >
        {link.label}
      </button>
    {/each}
  </div>
  {#if copyState}
    <p class="about-status" data-testid="about-status">{copyState}</p>
  {/if}

  <div class="about-paths">
    <h3 class="about-section-title">Paths</h3>
    {#each PATHS as row (row.label)}
      <div class="about-path-row">
        <span class="about-path-label">{row.label}</span>
        <code class="about-path-value" data-testid={`about-path-${row.kind ?? row.label.toLowerCase()}`}>{row.value}</code>
        {#if row.kind}
          <button
            class="btn btn-small"
            type="button"
            data-testid={`about-open-${row.kind}`}
            onclick={() => void reveal(row.kind!)}
          >
            Open folder
          </button>
        {:else}
          <button
            class="btn btn-small"
            type="button"
            data-testid="about-open-settings"
            onclick={() => void reveal('settings')}
          >
            Open folder
          </button>
        {/if}
      </div>
    {/each}
  </div>
</section>

<style>
  .about-pane {
    display: flex;
    flex-direction: column;
    gap: 12px;
    max-inline-size: 720px;
  }

  .about-title {
    margin: 0;
    font-size: calc(var(--ui-font-size) * var(--ui-scale) * 1.3);
  }

  .about-author {
    margin: 2px 0 0;
    color: var(--muted-foreground);
  }

  .about-version {
    margin: 6px 0 0;
    font-family: var(--console-font);
    font-size: calc(var(--console-font-size) * var(--ui-scale) * 0.9);
  }

  .about-runtime {
    margin: 2px 0 0;
    color: var(--muted-foreground);
    font-size: calc(var(--ui-font-size) * var(--ui-scale) * 0.85);
  }

  .about-summary {
    margin: 0;
  }

  .about-actions {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
  }

  .about-status {
    margin: 0;
    color: var(--muted-foreground);
    font-size: calc(var(--ui-font-size) * var(--ui-scale) * 0.85);
  }

  .about-section-title {
    margin: 0;
    font-size: calc(var(--ui-font-size) * var(--ui-scale) * 0.95);
  }

  .about-path-row {
    display: flex;
    align-items: center;
    gap: 10px;
    padding-block: 4px;
    flex-wrap: wrap;
  }

  .about-path-label {
    color: var(--muted-foreground);
    min-inline-size: 90px;
  }

  .about-path-value {
    font-family: var(--console-font);
    font-size: calc(var(--console-font-size) * var(--ui-scale) * 0.85);
    overflow-wrap: anywhere;
  }
</style>
