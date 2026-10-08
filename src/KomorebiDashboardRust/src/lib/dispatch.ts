// The one way a verb is started from the UI. Buttons and (later) keyboard
// shortcuts both come through here, so the busy rule and the run-id bookkeeping
// exist once.
import { console_, newRunId } from './console.svelte.ts';
import { isTauri, runVerb, type VerbDefinition } from './ipc';

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
