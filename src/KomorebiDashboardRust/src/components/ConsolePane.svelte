<script lang="ts">
  import { console_, percentFromDrag, DRAG_PERCENT_STEP } from '../lib/console.svelte.ts';
  import { cancelLiveRun } from '../lib/dispatch';
  import { formatDuration, formatLineCount, runStateLabel } from '../lib/format';
  import { settingsDocument, updateSettings } from '../lib/settings.svelte.ts';

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

  // ---- Ticket 09: the drag handle -----------------------------------------
  //
  // The pane's top edge is a real separator: pointer capture keeps the drag on
  // the handle even when the pointer outruns it, the arrow keys do the same
  // without a pointer at all, and the chosen height persists through the
  // settings document (one writer — the same document Apply writes) so it
  // survives a restart and is identical on every tab.
  let dragging = $state(false);

  function startDrag(event: PointerEvent): void {
    const target = event.currentTarget;
    if (!(target instanceof HTMLElement)) return;
    const pane = target.parentElement;
    if (!pane) return;
    target.setPointerCapture(event.pointerId);
    dragging = true;
    onDragTo(event.clientY, pane);
  }

  function onDragTo(clientY: number, pane: HTMLElement): void {
    const rect = pane.getBoundingClientRect();
    console_.setPercent(percentFromDrag(rect.top, rect.height, clientY));
  }

  function endDrag(): void {
    if (!dragging) return;
    dragging = false;
    void persistPercent();
  }

  function onHandleKey(event: KeyboardEvent): void {
    const step =
      event.key === 'ArrowUp' ? DRAG_PERCENT_STEP : event.key === 'ArrowDown' ? -DRAG_PERCENT_STEP : 0;
    if (step === 0) return;
    event.preventDefault();
    console_.setPercent(console_.percent + step);
    void persistPercent();
  }

  /** Persist the height only when it actually changed what the document holds. */
  async function persistPercent(): Promise<void> {
    const value = console_.percent;
    if (value === settingsDocument.consolePercent) return;
    await updateSettings({ consolePercent: value });
  }
</script>

<footer class="console-pane" style="height: {console_.percent}%">
  <!--
    Ticket 09 — the drag handle sits ON the pane's top edge: a 6px strip with
    the row-resize cursor. It is a separator for assistive tech carrying the
    live value, and the arrow keys move it the same way.
  -->
  <div
    class="console-handle"
    class:dragging
    role="separator"
    aria-orientation="horizontal"
    aria-label="Console height"
    aria-valuenow={console_.percent}
    aria-valuemin={10}
    aria-valuemax={60}
    tabindex="0"
    data-testid="console-drag"
    onpointerdown={startDrag}
    onpointermove={(event) => {
      if (dragging && event.currentTarget.parentElement) {
        onDragTo(event.clientY, event.currentTarget.parentElement);
      }
    }}
    onpointerup={endDrag}
    onkeydown={onHandleKey}
  ></div>
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
