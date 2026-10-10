// Ticket 10 — the AutoHotkey pane's state machine.
//
// The behaviours pinned here are the ticket's own checks: staging without
// writing, a SERIAL apply that stops at the first failure, the failed row
// reverting, and the re-read of the real disk state after a bulk verb.
//
// The backend and the runner are injected (the settings store's pattern), so
// this suite drives the shipped store in plain node with no Tauri in sight.

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { AhkRow, ahk, configureAhk, type AhkBackend, type AhkRunner } from '../lib/ahk.svelte.ts';
import type { ScriptResult } from '../lib/ipc';

const MANIFEST_STATES = [
  {
    key: 'autocorrect',
    label: 'Autocorrect Script',
    description: 'Auto-correct common typing mistakes as you type.',
    hotkey: 'runs on every word',
    interpreter: 'v1',
    enabled: true
  },
  {
    key: 'ChangeLangF3',
    label: 'Change Language F3 Script',
    description: 'Switch the keyboard input language with F3.',
    hotkey: 'F3',
    interpreter: 'v1',
    enabled: false
  },
  {
    key: 'NewFile',
    label: 'Create New File WIN+CTRL+N Script',
    description: 'Create a new file in the active folder.',
    hotkey: 'Win+Ctrl+N',
    interpreter: 'v2',
    enabled: true
  }
];

function resultOf(exitCode: number, cancelled = false, timedOut = false): ScriptResult {
  return {
    runId: 'run-1',
    verb: exitCode === 0 ? 'ahk-enable' : 'ahk-disable',
    exitCode,
    cancelled,
    timedOut,
    durationMs: 1,
    stdout: '',
    stderr: '',
    summary: exitCode === 0 ? 'reached the requested state' : 'the change failed'
  };
}

describe('AhkRow — the selection is separate from the applied state', () => {
  const row = (enabled: boolean) =>
    new AhkRow(
      'NewFile',
      'Create New File WIN+CTRL+N Script',
      'Create a new file.',
      'Win+Ctrl+N',
      'v2',
      enabled
    );

  it('opens clean: the selection equals the applied state', () => {
    const r = row(true);
    expect(r.isDirty).toBe(false);
    expect(r.statusText).toContain('Currently enabled');
    expect(r.statusText).toContain('v2');
  });

  it('stages a change without touching the applied state', () => {
    const r = row(true);
    r.isEnabled = false;
    expect(r.isDirty).toBe(true);
    expect(r.appliedEnabled).toBe(true); // nothing written yet
    expect(r.statusText).toContain('Will be disabled');
  });

  it('accepts the selection on apply and discards it on revert', () => {
    const accepted = row(true);
    accepted.isEnabled = false;
    accepted.markApplied();
    expect(accepted.appliedEnabled).toBe(false);
    expect(accepted.isDirty).toBe(false);

    const reverted = row(false);
    reverted.isEnabled = true;
    reverted.revert();
    expect(reverted.isEnabled).toBe(false);
  });
});

describe('the apply contract', () => {
  const backend: AhkBackend = { listScripts: async () => MANIFEST_STATES };

  beforeEach(async () => {
    vi.resetModules();
    const order: string[] = [];
    // The default runner succeeds; a test that needs a failure replaces it
    // through configureAhk before calling apply.
    const recordingRunner: AhkRunner = {
      run: async (state, key) => {
        order.push(`${key}:${state}`);
        return resultOf(0);
      }
    };
    configureAhk({ backend, runner: recordingRunner });
    await ahk.load();
    (globalThis as never as { __order: string[] }).__order = order;
  });

  it('reads the manifest and the disk state at read time', () => {
    expect(ahk.rows.map((r) => r.key)).toEqual(['autocorrect', 'ChangeLangF3', 'NewFile']);
    // The manifest order preserved; ChangeLangF3 disabled on disk.
    expect(ahk.rows.map((r) => r.appliedEnabled)).toEqual([true, false, true]);
    expect(ahk.dirtyCount).toBe(0);
    expect(ahk.applyHint).toContain('No changes to write');
  });

  it('applies every staged change serially and marks them applied', async () => {
    ahk.rows[0].isEnabled = false; // autocorrect -> disabled
    ahk.rows[2].isEnabled = false; // NewFile -> disabled

    await ahk.apply();

    const order = (globalThis as never as { __order: string[] }).__order;
    // Serial means one at a time, in row order — never interleaved, and the
    // rows that did not change are never sent.
    expect(order).toEqual(['autocorrect:disabled', 'NewFile:disabled']);
    // Both staged rows took their selection; the untouched row keeps its disk
    // state (ChangeLangF3: disabled).
    expect(ahk.rows.map((r) => r.appliedEnabled)).toEqual([false, false, false]);
    expect(ahk.status).toContain('Applied 2');
    expect(ahk.dirtyCount).toBe(0);
    expect(ahk.applyHint).toContain('No changes to write');
  });

  it('stops at the first failure, reverts that row, and names it', async () => {
    let call = 0;
    configureAhk({
      runner: {
        run: async () => {
          call += 1;
          return resultOf(call === 2 ? 1 : 0);
        }
      }
    });

    ahk.rows[0].isEnabled = false; // 1st: succeeds
    ahk.rows[1].isEnabled = true; // 2nd: FAILS
    ahk.rows[2].isEnabled = false; // 3rd: must never be attempted

    await ahk.apply();

    expect(call).toBe(2);
    expect(ahk.rows[0].appliedEnabled).toBe(false); // committed
    expect(ahk.rows[1].isEnabled).toBe(false); // reverted to the disk state
    expect(ahk.rows[2].isEnabled).toBe(false); // staged, untouched
    expect(ahk.rows[2].isDirty).toBe(true); // still pending, not lost
    expect(ahk.status).toContain('Change Language F3 Script could not be set to enabled');
  });

  it('treats a cancelled or timed-out run as a failure, not a success', async () => {
    configureAhk({ runner: { run: async () => resultOf(0, false, true) } });
    ahk.rows[0].isEnabled = false;
    await ahk.apply();
    expect(ahk.rows[0].appliedEnabled).toBe(true); // never marked applied
    expect(ahk.status).toContain('could not be set');
  });

  it('says nothing to apply when every row matches its stored state', async () => {
    await ahk.apply();
    expect(ahk.status).toContain('Nothing to apply');
  });

  it('re-reads the disk state after a bulk verb instead of assuming success', async () => {
    // The bulk verb disabled everything on disk; the next read must show it,
    // and the staged selections must follow the disk rather than survive it.
    let states = MANIFEST_STATES.map((s) => ({ ...s }));
    configureAhk({ backend: { listScripts: async () => states } });

    ahk.rows[1].isEnabled = true; // the user staged a re-enable of ChangeLangF3
    await ahk.apply(); // commits it through the UI's mirror

    // The registry's bulk verb then flips the real state file:
    states = states.map((s) => ({ ...s, enabled: false }));
    await ahk.refreshAfterBulkVerb();

    expect(ahk.rows.map((r) => r.appliedEnabled)).toEqual([false, false, false]);
    expect(ahk.rows.map((r) => r.isEnabled)).toEqual([false, false, false]);
    expect(ahk.dirtyCount).toBe(0);
  });
});
