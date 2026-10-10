// Ticket 12 — the shell's elevation state and the dialog it drives.
//
// Two pieces of state, deliberately in one store because they are one
// decision: whether this process is elevated (read once from the backend's
// token probe, which owns the measurement), and which verb — if any — is
// waiting on the relaunch dialog. The gate logic itself stays pure in
// elevation.ts; this file only carries its inputs and the UI consequence.
import { appInfo, relaunchElevated, type VerbDefinition } from './ipc';
import { dispatchVerb } from './dispatch';
import { elevationGate } from './elevation';

/** The verb waiting on the dialog, and the arguments it was clicked with. */
interface PendingVerb {
  verb: VerbDefinition;
  args: string[];
}

class ElevationStore {
  /**
   * This process's elevation state, as the backend measured it.
   *
   * `null` until the first `appInfo` lands — meaning "unknown", which is not
   * the same as "unelevated": before the answer arrives the gate errs toward
   * allowing nothing to be mislabelled, and in practice the store is loaded
   * before any row is clickable.
   */
  elevated = $state<boolean | null>(null);

  /** The verb waiting on the dialog, or null when no dialog is open. */
  pending = $state<PendingVerb | null>(null);

  /** Read the backend's measurement. Called once at shell start. */
  async load(): Promise<void> {
    // One retry: a transient IPC failure at startup would otherwise freeze
    // the conservative answer (unelevated) for the whole session, gating
    // verbs the process might actually be able to run.
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        this.elevated = (await appInfo()).elevated;
        return;
      } catch {
        if (attempt === 1) {
          // Outside the shell (plain `vite dev` in a browser) there is no
          // measurement to have, and a failed read must not open the gate:
          // treating the shell as unelevated makes the decision conservative
          // rather than permissive.
          this.elevated = false;
        }
      }
    }
  }

  /**
   * The one entry point a row click goes through: run the verb, or open the
   * dialog naming what needs Administrator.
   */
  request(verb: VerbDefinition, args: string[]): void {
    if (elevationGate(verb.requiresAdmin, this.elevated === true) === 'offer-relaunch') {
      this.pending = { verb, args };
      return;
    }
    void dispatchVerb(verb, args);
  }

  /**
   * OK: acknowledge and close. The operation cannot proceed unelevated, so
   * the ticket's three buttons are acknowledge / relaunch / cancel — OK does
   * not dispatch a verb the backend's own gate would refuse anyway. The CLI
   * is where a refused verb gets its structured exit-740 answer naming the
   * features; the window's job is to offer the way out, not to attempt it.
   */
  acknowledge(): void {
    this.pending = null;
  }

  /**
   * Rerun as Administrator: ask the backend to elevate. On success this
   * process exits inside the command and this method never returns. A
   * declined UAC prompt comes back as a rejection, and the ticket's contract
   * for that case is a clean return with no error state: the dialog simply
   * closes and the window stays as it was.
   */
  async relaunchElevated(): Promise<void> {
    try {
      await relaunchElevated();
    } catch {
      this.acknowledge();
    }
  }

  /** Cancel: close the dialog, run nothing, say nothing. */
  dismiss(): void {
    this.pending = null;
  }
}

export const elevation = new ElevationStore();
