// The one way a verb is started from the UI. Buttons and (later) keyboard
// shortcuts both come through here, so the busy rule and the run-id bookkeeping
// exist once.
import { console_, newRunId } from './console.svelte.ts';
import { cancelRun, isTauri, runVerb, type ScriptResult, type VerbDefinition } from './ipc';

/**
 * Dispatch a verb through the shared backend path.
 *
 * Refuses while another run is in flight: the rows are disabled at that point,
 * but a handler must not rely on the view to enforce the contract.
 */
export async function dispatchVerb(
  verb: VerbDefinition,
  args: string[]
): Promise<ScriptResult | null> {
  if (console_.busy) return null;

  if (!isTauri()) {
    console_.begin(verb.verb, 'preview');
    console_.error(
      'Not running inside the dashboard shell: open the built executable to dispatch verbs.'
    );
    return null;
  }

  const runId = newRunId();
  console_.begin(verb.verb, runId);
  let result: ScriptResult | null = null;
  try {
    result = await runVerb(verb.verb, args, runId);
    console_.finish(result);
  } catch (cause) {
    console_.error(cause instanceof Error ? cause.message : String(cause));
  }
  notifyRunFinished(verb.verb, result);
  return result;
}

/**
 * Did the run succeed? The three verdict facts are the backend's own, and
 * success needs all three: a cancelled or timed-out run is not a success even
 * with a zero exit code, because the script never reached its post-condition.
 */
export function runSucceeded(result: ScriptResult | null): boolean {
  if (result === null) return false;
  return result.exitCode === 0 && !result.cancelled && !result.timedOut;
}

/**
 * Run-completion listeners — the seam for a surface that must react to a run's
 * END rather than to a click.
 *
 * The AutoHotkey pane needs exactly that: after one of the registry's bulk
 * verbs runs, its rows re-read the on-disk state so the UI shows what actually
 * happened instead of assuming the write succeeded. Without this, every caller
 * would need its own copy of "dispatch, wait, then refresh", wired around the
 * shared row component that starts the run.
 */
type RunFinishedListener = (verb: string, result: ScriptResult | null) => void;

const runFinishedListeners = new Set<RunFinishedListener>();

/** Subscribe to run completions; returns the unsubscribe function. */
export function onRunFinished(listener: RunFinishedListener): () => void {
  runFinishedListeners.add(listener);
  return () => {
    runFinishedListeners.delete(listener);
  };
}

function notifyRunFinished(verb: string, result: ScriptResult | null): void {
  for (const listener of runFinishedListeners) {
    try {
      listener(verb, result);
    } catch {
      // A listener's failure must not take the run's own verdict down with it.
    }
  }
}

/**
 * Cancel the live run.
 *
 * The run id is read from the store, which is what makes this work from a button
 * that only knows a run is in flight — the row that started it may already have
 * been re-rendered. Nothing is reported as cancelled here: the backend decides
 * that, and its verdict arrives through the same `finish` path as any other run.
 */
export async function cancelLiveRun(): Promise<void> {
  const runId = console_.runId;
  if (runId === null) return;
  if (!isTauri()) return;

  console_.markCancelRequested();
  try {
    const stopped = await cancelRun(runId);
    // A false answer means the run had already finished. Saying nothing is right:
    // its own real verdict is already on its way and must not be overwritten by
    // a fabricated cancellation.
    if (!stopped) console_.cancelMissed();
  } catch {
    console_.cancelMissed();
  }
}
