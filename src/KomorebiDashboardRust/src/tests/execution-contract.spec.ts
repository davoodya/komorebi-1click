// Ticket 02 — the frontend half of the execution contract.
//
// The verdicts the console prints come from facts the backend records, so these
// tests pin the two things the UI is responsible for: never collapsing cancel
// and timeout into a failure, and never inventing a verdict of its own.
import { beforeEach, describe, expect, it } from 'vitest';
import { console_ } from '../lib/console.svelte.ts';
import { describeRun } from '../lib/format';
import type { ScriptResult } from '../lib/ipc';

function result(partial: Partial<ScriptResult> & { exitCode: number }): ScriptResult {
  return {
    runId: 'run-1',
    verb: 'demo-stream',
    cancelled: false,
    timedOut: false,
    durationMs: 1200,
    stdout: '',
    stderr: '',
    summary: 'Demo Stream — exit 0 in 1.20s',
    ...partial
  };
}

describe('run verdicts come from recorded facts, not from the exit code', () => {
  it('reads cancellation from the cancelled flag even when the code is not 130', () => {
    // A cancelled run is killed, so its raw code is whatever the kill produced.
    // The verdict must still be cancelled, which is why the flag exists.
    expect(describeRun({ exitCode: 1, cancelled: true })).toBe('cancelled');
    expect(describeRun({ exitCode: 0, cancelled: true })).toBe('cancelled');
  });

  it('reads a timeout from the timedOut flag even when the code is not 124', () => {
    expect(describeRun({ exitCode: 1, timedOut: true })).toBe('timed-out');
    expect(describeRun({ exitCode: 124, timedOut: true })).toBe('timed-out');
  });

  it('never lets a timeout be reported as a failure', () => {
    // The spec is explicit: a hung run says TIMED OUT, not FAILED.
    expect(describeRun({ exitCode: 124, timedOut: true })).not.toBe('failed');
    expect(describeRun({ exitCode: 7 })).toBe('failed');
  });

  it('keeps cancel and timeout distinct when both flags somehow arrive', () => {
    // Cancellation wins: the user's own action is never reported back as a
    // timeout. The backend enforces this too, and the UI must not undo it.
    expect(describeRun({ exitCode: 130, cancelled: true, timedOut: true })).toBe('cancelled');
  });
});

describe('the console records the facts the backend sent', () => {
  beforeEach(() => {
    console_.clear();
  });

  it('stamps a cancelled verdict from the result, not from an inference', () => {
    console_.begin('demo-stream', 'run-1');
    console_.finish(result({ exitCode: 130, cancelled: true, summary: 'cancelled' }));
    expect(console_.state).toBe('cancelled');
    expect(console_.runId).toBeNull();
  });

  it('stamps a timed-out verdict for an overrun', () => {
    console_.begin('demo-stream', 'run-1');
    console_.finish(result({ exitCode: 124, timedOut: true, summary: 'timed out' }));
    expect(console_.state).toBe('timed-out');
  });

  it('keeps a genuine failure distinct from both', () => {
    console_.begin('demo-stream', 'run-1');
    console_.finish(result({ exitCode: 9 }));
    expect(console_.state).toBe('failed');
  });

  it('clears the cancel request once the run has a verdict', () => {
    console_.begin('demo-stream', 'run-1');
    console_.markCancelRequested();
    expect(console_.cancelRequested).toBe(true);
    console_.finish(result({ exitCode: 130, cancelled: true }));
    expect(console_.cancelRequested).toBe(false);
    expect(console_.busy).toBe(false);
  });

  it('resets the cancel request when a new run starts', () => {
    console_.begin('demo-stream', 'run-1');
    console_.markCancelRequested();
    console_.begin('demo-stream', 'run-2');
    expect(console_.cancelRequested).toBe(false);
  });

  it('drops output belonging to a run it is no longer tracking', () => {
    // This is what stops a late batch from a cancelled run leaking into the
    // transcript of the next one.
    console_.begin('demo-stream', 'run-2');
    console_.append({ runId: 'run-1', lines: [{ stream: 'stdout', text: 'stale' }] });
    expect(console_.lines).toHaveLength(0);
    console_.append({ runId: 'run-2', lines: [{ stream: 'stdout', text: 'fresh' }] });
    expect(console_.lines).toHaveLength(1);
  });
});