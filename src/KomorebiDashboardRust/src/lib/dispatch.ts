// The one way a verb is started from the UI. Buttons and (later) keyboard
// shortcuts both come through here, so the busy rule and the run-id bookkeeping
// exist once.
import { console_, newRunId } from './console.svelte.ts';
import { cancelRun, isTauri, runVerb, type VerbDefinition } from './ipc';

/**
 * Dispatch a verb through the shared backend path.
 *
 * Refuses while another run is in flight: the rows are disabled at that point,
 * but a handler must not rely on the view to enforce the contract.
 */
export async function dispatchVerb(verb: VerbDefinition, args: string[]): Promise<void> {
  if (console_.busy) return;

  if (!isTauri()) {
    console_.begin(verb.verb, 'preview');
    console_.error(
      'Not running inside the dashboard shell: open the built executable to dispatch verbs.'
    );
    return;
  }

  const runId = newRunId();
  console_.begin(verb.verb, runId);
  try {
    const result = await runVerb(verb.verb, args, runId);
    console_.finish(result);
  } catch (cause) {
    console_.error(cause instanceof Error ? cause.message : String(cause));
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
