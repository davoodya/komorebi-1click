<script lang="ts">
  import { console_ } from '../lib/console.svelte.ts';
  import { cancelLiveRun } from '../lib/dispatch';
  import { formatDuration, formatLineCount, runStateLabel } from '../lib/format';

  let body = $state<HTMLDivElement | null>(null);
  /** True while the reader is pinned to the end of the transcript. */
  let atEnd = $state(true);
  /** Share of the pane currently scrolled, for the status line. */
  let scrollPercent = $state(100);

  const lineCount = $derived(console_.lineCount);

  /** The dot's state: a live run wins over the previous run's verdict. */
  const dotState = $derived(console_.busy ? 'running' : (console_.state ?? 'idle'));
  const verdict = $derived(
    console_.busy ? 'RUNNING' : console_.state ? runStateLabel(console_.state) : 'Ready'
  );

  /**
   * Auto-scroll only while the reader is already at the end. Scrolling up to
   * read history is never fought (spec US 30) — that is the entire reason this
   * tracks a threshold instead of always scrolling.
   */
  function onScroll() {
    if (!body) return;
    const slack = body.scrollHeight - body.scrollTop - body.clientHeight;
    atEnd = slack <= 24;
    const range = body.scrollHeight - body.clientHeight;
    scrollPercent = range <= 0 ? 100 : Math.round((body.scrollTop / range) * 100);
  }

  // Re-runs on every appended line, so a batch is what drives the scroll.
  $effect(() => {
    void lineCount;
    if (body && atEnd) body.scrollTop = body.scrollHeight;
  });
</script>

<footer class="console-pane" style="height: {console_.percent}%">
  <div class="console-header">
    <span>Console</span>
    {#if console_.verb}
      <span class="mono">{console_.verb}</span>
    {/if}
    <span class="row-actions">
      <!--
        Cancel is offered only while a run is live, because that is the only time
        it can do anything. It stays visible but disabled once a cancel is on its
        way, so the user can see the request was taken while the verdict is still
        coming from the backend.
      -->
      {#if console_.busy}
        <button
          class="btn btn-quiet"
          type="button"
          data-testid="cancel-run"
          disabled={console_.cancelRequested}
          onclick={() => void cancelLiveRun()}
        >
          {console_.cancelRequested ? 'Cancelling...' : 'Cancel'}
        </button>
      {/if}
      <!-- Clear works during a run and does not cancel it (spec US 33). -->
      <button class="btn btn-quiet" type="button" onclick={() => console_.clear()}>Clear</button>
    </span>
  </div>

  <div class="console-body" bind:this={body} onscroll={onScroll} role="log" aria-live="polite">
    {#if lineCount === 0}
      <span class="console-empty">No output yet. Run a verb to see its output stream here.</span>
    {:else}
      {#each console_.lines as line, index (index)}
        <div class:console-line-stderr={line.stream === 'stderr'}>{line.text}</div>
      {/each}
    {/if}
  </div>

  <div class="status-bar">
    <span class="status-dot" data-state={dotState}></span>
    <span data-testid="run-state">{verdict}</span>
    {#if console_.exitCode !== null}
      <span>exit {console_.exitCode}</span>
      <span>{formatDuration(console_.durationMs)}</span>
    {/if}
    <span>{formatLineCount(lineCount)}</span>
    <span>{scrollPercent}%</span>
    {#if console_.summary}
      <span class="mono">{console_.summary}</span>
    {/if}
  </div>
</footer>
