// The IPC boundary. Every call into Rust goes through here, so the command
// names and payload shapes exist in exactly one place on this side of the
// boundary and can be checked against the Rust signatures by reading one file.
import { invoke } from '@tauri-apps/api/core';
import type { SettingsDocument } from './settings';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';

/**
 * One registry declaration, exactly as Rust serializes it.
 *
 * Ticket 03 landed the four grouping and gating fields, so they are required
 * rather than optional: a registry row that arrives without its tab or its flags
 * is a backend that is not the one this frontend was built against, and it is
 * better for that to be a type error than a row rendered in the wrong place.
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
  /** Which tab owns the row. Every verb appears under exactly one. */
  tab: string;
  /** True when the script needs an elevated host (the gate arrives with ticket 05). */
  requiresAdmin: boolean;
  /** Digits-only value box. */
  numericOnly: boolean;
  /** False suppresses the row in favour of a more specific one; the verb still dispatches. */
  renderInGui: boolean;
}

/** One tab of the shell, as the backend declares it. */
export interface TabDefinition {
  id: string;
  label: string;
  description: string;
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
  /**
   * This process's elevation state, measured by the backend's own token probe
   * rather than guessed here. The shell gates administrative rows with it; a
   * second reading in the frontend could only ever disagree with the gate the
   * backend enforces.
   */
  elevated: boolean;
  /**
   * Ticket 06: where the settings document lives, from the backend that owns
   * the profile lookup — shown in the Settings pane and revealed by Open
   * Folder. Never re-derived here.
   */
  settingsPath: string;
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

/**
 * The tabs, in the order they are drawn.
 *
 * The backend owns the list so the strip, `--help`'s groupings and the elevation
 * message cannot disagree about what a tab is called or which verbs are under it.
 */
export function listTabs(): Promise<TabDefinition[]> {
  return invoke<TabDefinition[]>('list_tabs');
}

export function appInfo(): Promise<AppInfo> {
  return invoke<AppInfo>('app_info');
}

/**
 * Ask the backend to relaunch this executable elevated (ticket 12).
 *
 * Resolves only when the relaunch could NOT start — a declined UAC prompt is
 * the normal cause and arrives as an error string to show in the dialog. On
 * success the backend exits this process itself, so there is no "after" to
 * handle: the new elevated instance is simply the next thing that runs.
 */
export function relaunchElevated(): Promise<void> {
  return invoke<void>('relaunch_elevated');
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

// ---------------------------------------------------------------------------
// Ticket 06 — the settings document.
//
// The Rust side is the only writer of the file; these are the three lifecycle
// calls plus the reveal. `quarantined` comes back from load so the UI can
// REPORT a corruption the backend defused instead of silently showing
// defaults the user never chose.
// ---------------------------------------------------------------------------

/** A load result: the document, and the quarantine a corrupt read produced. */
export interface SettingsLoadOutcome {
  settings: SettingsDocument;
  quarantined: string | null;
}

export function getSettings(): Promise<SettingsLoadOutcome> {
  return invoke<SettingsLoadOutcome>('get_settings');
}

/** Write the document. Resolves to the file path that was written. */
export function saveSettings(settings: SettingsDocument): Promise<string> {
  return invoke<string>('save_settings', { settings });
}

/** Restore and persist every default. Resolves to the file path written. */
export function resetSettings(): Promise<string> {
  return invoke<string>('reset_settings');
}

/**
 * Open Explorer at the settings DIRECTORY (the folder, not the file — a .json
 * would otherwise land in whatever program the user associated with JSON).
 */
export function revealSettingsFolder(): Promise<string> {
  return invoke<string>('reveal_settings_folder');
}
