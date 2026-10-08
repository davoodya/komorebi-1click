// The single console store. Every tab reads this one instance, which replaces
// the WPF build's weak-reference broadcast: one share value, one output buffer,
// no per-tab copies that can disagree (codebase-inventory 2.3).
import { clampConsolePercent } from './tokens';
import { describeRun, type RunState } from './format';
import type { OutputBatch, OutputLine, ScriptResult } from './ipc';

/** Output ceiling, trimmed on whole lines only (spec US 32 / inventory 14). */
export const CONSOLE_CHAR_CAP = 200_000;

/** The console share the current build is designed around (SettingsStore). */
export const DEFAULT_CONSOLE_PERCENT = 25;

class ConsoleStore {
  /** Append-only transcript, already trimmed to the cap. */
  lines = $state<OutputLine[]>([]);
  /** Character budget consumed by `lines`, maintained incrementally. */
  chars = $state(0);

  /** The in-flight run, or null when idle. */
  runId = $state<string | null>(null);
  verb = $state<string | null>(null);

  /** Facts about the last finished run. */
  state = $state<RunState | null>(null);
  exitCode = $state<number | null>(null);
  durationMs = $state(0);
  summary = $state('');

  /** Console share of the tab body, in percent; global to every tab. */
  percent = $state(DEFAULT_CONSOLE_PERCENT);

  /** A cancel has been requested for the live run and is not yet confirmed. */
  cancelRequested = $state(false);

  /** True while a verb is executing: rows disable, nothing else may start. */
  get busy(): boolean {
    return this.runId !== null;
  }

  lineCount = $derived(this.lines.length);

  /**
   * Start a run. Clears the previous run's verdict but NOT its output: the
   * console accumulates so tab switches mid-run are not destructive
   * (ticket 04), and Clear is the only thing that empties it.
   */
  begin(verb: string, runId: string): void {
    this.runId = runId;
    this.verb = verb;
    this.state = null;
    this.exitCode = null;
    this.durationMs = 0;
    this.summary = `Running ${verb}...`;
    this.cancelRequested = false;
  }

  /**
   * Append one batch. Batches for a run we are no longer tracking are dropped:
   * a late batch from a cancelled run must never write into the next run's
   * transcript.
   */
  append(batch: OutputBatch): void {
    if (this.runId !== null && batch.runId !== this.runId) return;
    if (batch.lines.length === 0) return;

    let added = 0;
    for (const line of batch.lines) added += line.text.length + 1;
    const next = this.lines.concat(batch.lines);
    this.chars += added;

    if (this.chars > CONSOLE_CHAR_CAP) {
      // Drop whole lines from the front until the cap is honoured: trimming
      // mid-line would corrupt a line the user is reading.
      let drop = 0;
      while (drop < next.length && this.chars > CONSOLE_CHAR_CAP) {
        this.chars -= next[drop].text.length + 1;
        drop++;
      }
      this.lines = next.slice(drop);
      return;
    }
    this.lines = next;
  }

  /** Record the verdict of a finished run. */
  finish(result: ScriptResult): void {
    if (this.runId !== null && result.runId !== this.runId) return;
    // Both flags come from the backend as recorded facts. They are never derived
    // from the exit code here: a cancellation and a timeout must stay distinct,
    // and only the backend knows which one actually happened.
    this.state = describeRun({
      exitCode: result.exitCode,
      cancelled: result.cancelled,
      timedOut: result.timedOut
    });
    this.exitCode = result.exitCode;
    this.durationMs = result.durationMs;
    this.summary = result.summary;
    this.runId = null;
    this.cancelRequested = false;
  }

  /**
   * Mark that a cancel has been asked for. The run is not over until the backend
   * says so, so this only drives the button's own state; the verdict still comes
   * from `finish`.
   */
  markCancelRequested(): void {
    this.cancelRequested = true;
  }

  /** A cancel was asked for but no live run answered, so nothing was stopped. */
  cancelMissed(): void {
    this.cancelRequested = false;
  }

  /** Clear the transcript only. Never cancels the run (spec US 33). */
  clear(): void {
    this.lines = [];
    this.chars = 0;
  }

  /** One share for every tab; clamped to the supported range (10-60 %). */
  setPercent(percent: number): void {
    this.percent = clampConsolePercent(percent);
  }

  /** Message shown when the backend never produced a verdict. */
  error(message: string): void {
    this.finish({
      runId: this.runId ?? 'local',
      verb: this.verb ?? 'unknown',
      exitCode: 1,
      cancelled: false,
      timedOut: false,
      durationMs: 0,
      stdout: '',
      stderr: message,
      summary: message
    });
  }
}

export const console_ = new ConsoleStore();

/** A short, unique-enough run id. The backend echoes it on every batch. */
export function newRunId(): string {
  return `run-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}
