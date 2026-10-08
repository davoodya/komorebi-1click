import { beforeEach, describe, expect, it } from 'vitest';
import { CONSOLE_CHAR_CAP, DEFAULT_CONSOLE_PERCENT, console_, newRunId } from '../lib/console.svelte.ts';
import type { OutputBatch, ScriptResult } from '../lib/ipc';

function batch(runId: string, count: number, text = 'x'.repeat(10)): OutputBatch {
  return { runId, lines: Array.from({ length: count }, () => ({ stream: 'stdout', text })) };
}

function result(runId: string, exitCode: number, durationMs = 10): ScriptResult {
  return {
    runId,
    verb: 'demo-stream',
    exitCode,
    durationMs,
    stdout: '',
    stderr: '',
    summary: 'demo-stream'
  };
}

describe('console store', () => {
  beforeEach(() => {
    console_.clear();
    console_.finish(result('reset', 0));
    console_.clear();
    console_.setPercent(DEFAULT_CONSOLE_PERCENT);
  });

  it('starts idle with no output and the designed default share', () => {
    expect(console_.busy).toBe(false);
    expect(console_.lineCount).toBe(0);
    expect(console_.percent).toBe(25);
  });

  it('marks a run busy between begin and finish', () => {
    console_.begin('demo-stream', 'run-1');
    expect(console_.busy).toBe(true);
    console_.finish(result('run-1', 0));
    expect(console_.busy).toBe(false);
    expect(console_.state).toBe('succeeded');
  });

  it('appends whole batches and counts every line', () => {
    console_.begin('demo-stream', 'run-1');
    console_.append(batch('run-1', 12));
    console_.append(batch('run-1', 8));
    expect(console_.lineCount).toBe(20);
    console_.finish(result('run-1', 0));
    expect(console_.busy).toBe(false);
  });

  it('ignores a late batch from a run that is no longer current', () => {
    console_.begin('demo-stream', 'run-1');
    console_.append(batch('run-1', 3));
    console_.finish(result('run-1', 0));

    console_.begin('status', 'run-2');
    console_.append(batch('run-1', 5)); // straggler from the cancelled run
    expect(console_.lineCount).toBe(3);
    console_.append(batch('run-2', 2));
    expect(console_.lineCount).toBe(5);
    console_.finish(result('run-2', 0));
  });

  it('caps the transcript at 200k characters, trimming whole lines only', () => {
    console_.begin('demo-stream', 'run-1');
    const perBatch = 200;
    const text = 'y'.repeat(199);
    for (let i = 0; i < 200; i++) console_.append(batch('run-1', perBatch, text));

    expect(console_.chars).toBeLessThanOrEqual(CONSOLE_CHAR_CAP);
    expect(console_.chars).toBeGreaterThan(CONSOLE_CHAR_CAP - 2_000);
    // Whole lines only: every retained line is still intact.
    expect(console_.lines.every((line) => line.text.length === 199)).toBe(true);
  });

  it('clears the transcript without touching the run in flight', () => {
    console_.begin('demo-stream', 'run-1');
    console_.append(batch('run-1', 4));
    console_.clear();
    expect(console_.lineCount).toBe(0);
    expect(console_.busy).toBe(true);
    console_.finish(result('run-1', 0));
  });

  it('records a non-zero exit as a failure with its code and duration', () => {
    console_.begin('demo-stream', 'run-1');
    console_.finish(result('run-1', 7, 1234));
    expect(console_.state).toBe('failed');
    expect(console_.exitCode).toBe(7);
    expect(console_.durationMs).toBe(1234);
  });

  it('records timeout as its own fact, not a failure', () => {
    console_.begin('demo-stream', 'run-1');
    console_.finish(result('run-1', 124, 300_000));
    expect(console_.state).toBe('timed-out');
  });

  it('clamps the console share into the supported range', () => {
    console_.setPercent(75);
    expect(console_.percent).toBe(60);
    console_.setPercent(2);
    expect(console_.percent).toBe(10);
  });

  it('generates a distinct run id per dispatch', () => {
    const ids = new Set([newRunId(), newRunId(), newRunId()]);
    expect(ids.size).toBe(3);
  });
});
