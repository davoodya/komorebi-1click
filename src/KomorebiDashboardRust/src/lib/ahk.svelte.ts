// Ticket 10 — the AutoHotkey tab's state.
//
// The row model mirrors the WPF build's AhkScriptRow, and for the same reason:
// the selection is SEPARATE from the applied state. Every applied change runs
// ahk-script.ps1, which rewrites the same generated AppRunner.vbs; wiring the
// radios straight to the script would launch three processes for three clicks
// racing over one file. The radios move the SELECTION; Apply commits it.
//
// Both seams are injectable (the settings store's pattern): `ahk.spec.ts`
// drives this machine in plain node, and the Tauri IPC layer is exercised by
// the built executable, not by the unit suite.

import { console_ } from './console.svelte.ts';
import type { AhkScriptState, ScriptResult, VerbDefinition } from './ipc';
import { updateSettings } from './settings.svelte.ts';

/** The backend this store needs — the ipc module supplies it in the app. */
export interface AhkBackend {
  listScripts(): Promise<AhkScriptState[]>;
}

/** How one script's state change is committed — the shared dispatch, normally. */
export interface AhkRunner {
  run(state: 'enabled' | 'disabled', key: string): Promise<ScriptResult | null>;
}

let backend: AhkBackend | null = null;
let runner: AhkRunner | null = null;

/** Load the real ipc/dispatch backend lazily so tests never pull in Tauri. */
async function realBackend(): Promise<AhkBackend> {
  if (backend) return backend;
  const ipc = await import('./ipc');
  backend = { listScripts: () => ipc.listAhkScripts() };
  return backend;
}

/** The app's runner: the registry's per-script verb through shared dispatch. */
let verbTable: ((state: 'enabled' | 'disabled') => VerbDefinition) | null = null;

async function loadRunner(): Promise<AhkRunner> {
  if (runner) return runner;
  const { dispatchVerb } = await import('./dispatch');
  const dispatch: AhkRunner = {
    // -Name first, then the state: named parameters bind by name, and the row
    // box carries the script key alone.
    run: (state, key) => dispatchVerb(verbTable!(state), [key])
  };
  runner = dispatch;
  return runner;
}

/**
 * Wire the registry's per-script verbs into the store. Called once by the pane
 * once the registry is loaded; the two verbs are `render_in_gui: false` rows
 * driven BY the pane, which is why the pane owns the lookup.
 */
export function setAhkVerbs(
  verbFor: (state: 'enabled' | 'disabled') => VerbDefinition
): void {
  verbTable = verbFor;
  // Drop the cached dispatch runner so the next apply builds one that closes
  // over the new verb table.
  runner = null;
}

/** Test seam: replace the backend and the runner in one call. */
export function configureAhk(seams: { backend?: AhkBackend; runner?: AhkRunner }): void {
  if (seams.backend) backend = seams.backend;
  if (seams.runner) runner = seams.runner;
}

/** Did the run succeed? The backend's three verdict facts decide, not a guess. */
function succeeded(result: ScriptResult | null): boolean {
  if (result === null) return false;
  return result.exitCode === 0 && !result.cancelled && !result.timedOut;
}

/** One shipped script as a row: manifest metadata, disk state, staged state. */
export class AhkRow {
  /** The state on disk, refreshed after every Apply and every bulk verb. */
  appliedEnabled = $state(false);

  /** What the user has selected for the next Apply. */
  isEnabled = $state(false);

  constructor(
    readonly key: string,
    readonly label: string,
    readonly description: string,
    readonly hotkey: string,
    readonly interpreter: string,
    enabled: boolean
  ) {
    this.appliedEnabled = enabled;
    this.isEnabled = enabled;
  }

  get isDirty(): boolean {
    return this.isEnabled !== this.appliedEnabled;
  }

  /** The row's state line: what WILL happen, or what IS. */
  get statusText(): string {
    if (this.isDirty) {
      return `Will be ${this.isEnabled ? 'enabled' : 'disabled'} when you press Apply.`;
    }
    return `Currently ${this.appliedEnabled ? 'enabled' : 'disabled'} · AutoHotkey ${this.interpreter}`;
  }

  /** Accept the pending selection as the applied state. */
  markApplied(): void {
    this.appliedEnabled = this.isEnabled;
  }

  /** Discard the pending selection. */
  revert(): void {
    this.isEnabled = this.appliedEnabled;
  }
}

class AhkStore {
  rows = $state<AhkRow[]>([]);
  /** The pane's own status line. */
  status = $state('');
  loadError = $state<string | null>(null);

  /** True while any verb runs: the shared busy state, not a local copy. */
  get busy(): boolean {
    return console_.busy;
  }

  get loaded(): boolean {
    return this.rows.length > 0;
  }

  get dirtyCount(): number {
    return this.rows.filter((row) => row.isDirty).length;
  }

  /**
   * The hint under the Apply button, and the pending-change count.
   */
  get applyHint(): string {
    const changed = this.dirtyCount;
    if (changed === 0) return 'Every script already matches its stored state. No changes to write.';
    return `${changed} script${changed === 1 ? '' : 's'} changed. Apply runs the per-script script for each one, then stores the result.`;
  }

  /**
   * Read the manifest and the on-disk state. Called at open time and again
   * after every bulk verb — always at read time, never cached, so the rows
   * show what is actually configured rather than assuming success.
   */
  async load(): Promise<void> {
    try {
      const states = await (await realBackend()).listScripts();
      this.rows = states.map(
        (state) =>
          new AhkRow(
            state.key,
            state.label,
            state.description,
            state.hotkey,
            state.interpreter,
            state.enabled
          )
      );
      this.status = '';
      this.loadError = null;
    } catch (cause) {
      this.loadError = cause instanceof Error ? cause.message : String(cause);
    }
  }

  /**
   * Commit every changed script, then persist the resulting state.
   *
   * Serial, not parallel: each ahk-script.ps1 rewrites the same generated
   * AppRunner.vbs, so concurrent runs would interleave and leave the file
   * describing a state neither intended. The loop stops at the first failure,
   * because a state written after a failed call would claim a change that did
   * not happen.
   */
  async apply(): Promise<void> {
    const pending = this.rows.filter((row) => row.isDirty);
    if (pending.length === 0) {
      this.status = 'Nothing to apply — every script already matches its stored state.';
      return;
    }

    const run = await loadRunner();
    for (const row of pending) {
      const state = row.isEnabled ? 'enabled' : 'disabled';
      const result = await run.run(state, row.key);

      if (!succeeded(result)) {
        row.revert();
        this.status = `${row.label} could not be set to ${state}. No further changes were applied.`;
        return;
      }

      row.markApplied();
    }

    await this.persist();
    this.status = `Applied ${pending.length} script change${pending.length === 1 ? '' : 's'}.`;
  }

  /**
   * Store the applied states in the dashboard's own settings document, so the
   * tab opens showing what the scripts have even before the state file is
   * read. The disk state file stays the scripts' own; this is the UI's mirror.
   */
  async persist(): Promise<void> {
    const states: Record<string, boolean> = {};
    for (const row of this.rows) states[row.key] = row.appliedEnabled;
    await updateSettings({ ahkScriptStates: states });
  }

  /**
   * Re-read the on-disk state after one of the registry's bulk verbs ran, so
   * the radio pairs do not keep showing a state the scripts have already left.
   *
   * Bulk verbs are the registry's own rows (ahk-enable-all / ahk-disable-all),
   * dispatched through the shared row component — which is why the refresh
   * hangs off a run-completion seam rather than off a pane-local button.
   */
  async refreshAfterBulkVerb(): Promise<void> {
    await this.load();
    await this.persist();
  }
}

export const ahk = new AhkStore();
