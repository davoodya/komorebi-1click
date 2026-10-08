// Human-facing formatting for the console status line, plus the argument split.
// Kept dependency-free and pure so unit tests can cover it without a DOM.

/** A duration as a short, stable string: 812 ms / 3.41 s / 1 m 04 s. */
export function formatDuration(ms: number): string {
  if (!Number.isFinite(ms) || ms < 0) return '0 ms';
  if (ms < 1000) return `${Math.round(ms)} ms`;
  const seconds = ms / 1000;
  if (seconds < 60) return `${seconds.toFixed(2)} s`;
  const minutes = Math.floor(seconds / 60);
  const rest = Math.floor(seconds % 60);
  return `${minutes} m ${String(rest).padStart(2, '0')} s`;
}

/**
 * The state a finished run left behind. Cancellation and timeout are distinct
 * facts and are never collapsed into "failed" (spec US 38/41).
 */
export type RunState = 'succeeded' | 'failed' | 'timed-out' | 'cancelled';

export interface RunFacts {
  exitCode: number;
  cancelled?: boolean;
  timedOut?: boolean;
}

export function describeRun(facts: RunFacts): RunState {
  if (facts.cancelled) return 'cancelled';
  if (facts.timedOut) return 'timed-out';
  return facts.exitCode === 0 ? 'succeeded' : 'failed';
}

/** The label shown in the run-status chip. */
export function runStateLabel(state: RunState): string {
  switch (state) {
    case 'succeeded':
      return 'OK';
    case 'failed':
      return 'FAILED';
    case 'timed-out':
      return 'TIMED OUT';
    case 'cancelled':
      return 'CANCELLED';
  }
}

/** "12 lines" / "1 line" */
export function formatLineCount(lines: number): string {
  return lines === 1 ? '1 line' : `${lines} lines`;
}

/**
 * Split a row's typed value into arguments.
 *
 * Ported from the C# `SplitArguments` so a value the user typed behaves the same
 * in both builds: whitespace separates arguments, and double quotes group a
 * value that contains spaces. Quotes are stripped; an unterminated quote simply
 * groups to the end of the input rather than failing, which is what the WPF
 * build did.
 */
export function parseArguments(input: string): string[] {
  const trimmed = input.trim();
  if (trimmed.length === 0) return [];

  const parts: string[] = [];
  let current = '';
  let inQuotes = false;

  for (const ch of trimmed) {
    if (ch === '"') {
      inQuotes = !inQuotes;
      continue;
    }
    if (!inQuotes && /\s/.test(ch)) {
      if (current.length > 0) {
        parts.push(current);
        current = '';
      }
      continue;
    }
    current += ch;
  }
  if (current.length > 0) parts.push(current);
  return parts;
}
