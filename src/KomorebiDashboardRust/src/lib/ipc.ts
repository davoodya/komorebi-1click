// The IPC boundary. Every call into Rust goes through here, so the command
// names and payload shapes exist in exactly one place on this side of the
// boundary and can be checked against the Rust signatures by reading one file.
import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';

/**
 * One registry declaration, exactly as Rust serializes it.
 *
 * The four optional fields are declared ahead of the tickets that populate
 * them (03 adds the tab grouping, admin/read-only gating and the numeric flag).
 * They are optional rather than required so this interface keeps describing what
 * the backend actually sends today instead of what it will send later.
 */
export interface VerbDefinition {
  verb: string;
  script: string;
  label: string;
  help: string;
  fixedArguments: string[];
  actionLabel: string;
  isReadOnly: boolean;
  acceptsArguments: boolean;
  hint: string;
  /** Ticket 03: which tab owns the row. */
  tab?: string;
  /** Ticket 03: true when the script needs an elevated host (gate in 05). */
  requiresAdmin?: boolean;
  /** Ticket 03: digits-only value box. */
  numericOnly?: boolean;
  /** Ticket 03: false suppresses the row in favour of a more specific one. */
  renderInGui?: boolean;
}

export interface OutputLine {
  stream: string;
  text: string;
}

/** One ~50 ms window of output. One emit per window, never one per line. */
export interface OutputBatch {
  runId: string;
  lines: OutputLine[];
}

export interface ScriptResult {
  runId: string;
  verb: string;
  exitCode: number;
  /** The user stopped this run. A recorded fact, never inferred from the code. */
  cancelled: boolean;
  /** The run overran its budget. Distinct from a failure, on purpose. */
  timedOut: boolean;
  durationMs: number;
  stdout: string;
  stderr: string;
  summary: string;
}

export interface AppInfo {
  product: string;
  version: string;
  gitSha: string;
  scriptsPath: string;
}

/** The event channel the backend streams batches on. */
export const OUTPUT_EVENT = 'script-output';

/**
 * True when running inside the Tauri shell. The frontend is also opened by
 * `vite dev` in a plain browser during layout work, where every invoke would
 * reject; the UI branches on this instead of showing an error nobody caused.
 */
export function isTauri(): boolean {
  return typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
}

export function listVerbs(): Promise<VerbDefinition[]> {
  return invoke<VerbDefinition[]>('list_verbs');
}

export function appInfo(): Promise<AppInfo> {
  return invoke<AppInfo>('app_info');
}

/**
 * Dispatch a verb. `args` are the extra arguments for this run only; the
 * registry's fixed arguments are applied by the Rust side, which is what keeps
 * the CLI and the buttons on one code path.
 */
export function runVerb(verb: string, args: string[], runId: string): Promise<ScriptResult> {
  return invoke<ScriptResult>('run_verb', { verb, arguments: args, runId });
}

/**
 * Ask the backend to stop a live run.
 *
 * Resolves to whether a run was actually stopped. `false` is normal and not an
 * error: the run may have finished in the moment between the click and this
 * call. The caller must say so rather than claim a cancel that did nothing.
 */
export function cancelRun(runId: string): Promise<boolean> {
  return invoke<boolean>('cancel_run', { runId });
}

export function onOutput(handler: (batch: OutputBatch) => void): Promise<UnlistenFn> {
  return listen<OutputBatch>(OUTPUT_EVENT, (event) => handler(event.payload));
}
