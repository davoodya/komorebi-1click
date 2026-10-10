// Ticket 04 — the eight-tab strip.
//
// The backend owns the tab list (registry.rs TABS, served by list_tabs) and the
// grouping; what this side must get right is that the strip draws exactly those
// tabs in the backend's order, that a switch resolves to a tab that exists, and
// that switching is never destructive to the accumulated console output.
import { beforeEach, describe, expect, it } from 'vitest';
import { console_ } from '../lib/console.svelte.ts';
import { resolveActiveTab, rowsForTab } from '../lib/registry.svelte.ts';
import type { OutputBatch, TabDefinition, VerbDefinition } from '../lib/ipc';

const TAB_IDS = [
  'KillStart',
  'Restart',
  'Settings',
  'Customization',
  'AutoHotkey',
  'Debugging',
  'Uninstall',
  'About'
] as const;

function tabs(ids: readonly string[] = TAB_IDS): TabDefinition[] {
  return ids.map((id) => ({
    id,
    label: `${id} label`,
    description: `${id} description`
  }));
}

function verb(overrides: Partial<VerbDefinition> = {}): VerbDefinition {
  return {
    verb: 'status',
    script: 'komorebi-service.ps1',
    label: 'Status',
    help: 'Read-only health check',
    fixedArguments: ['-Action', 'status'],
    actionLabel: 'Check',
    isReadOnly: true,
    acceptsArguments: false,
    hint: '',
    tab: 'Debugging',
    requiresAdmin: false,
    numericOnly: false,
    renderInGui: true,
    ...overrides
  };
}

describe('the tab strip renders what the backend declares', () => {
  it('resolves the tab the user selected', () => {
    const active = resolveActiveTab(tabs(), 'Settings');
    expect(active?.id).toBe('Settings');
  });

  it('opens on the first declared tab before any selection', () => {
    expect(resolveActiveTab(tabs(), '')?.id).toBe('KillStart');
  });

  it('falls back to the first tab when the selection is unknown', () => {
    // A stale id (a tab the backend no longer declares) must never blank the
    // shell: render the first real tab rather than nothing.
    expect(resolveActiveTab(tabs(), 'no-such-tab')?.id).toBe('KillStart');
  });

  it('has no active tab while the registry is still loading', () => {
    expect(resolveActiveTab([], 'Settings')).toBeUndefined();
  });
});

describe('each tab shows exactly the rows the registry groups under it', () => {
  // One verb per tab, spread across all eight: the union of the per-tab row
  // sets must be every rendered verb exactly once, so no tab can double-draw a
  // row and no row can fall between two tabs.
  const verbs = [
    verb({ verb: 'kill-all', tab: 'KillStart' }),
    verb({ verb: 'restart-all', tab: 'Restart' }),
    verb({ verb: 'startup-install', tab: 'Settings', requiresAdmin: true }),
    verb({ verb: 'ahk-enable-all', tab: 'AutoHotkey' }),
    verb({ verb: 'demo-stream', tab: 'Debugging', acceptsArguments: true, hint: 'Number of lines' }),
    verb({ verb: 'cleanup', tab: 'Uninstall', requiresAdmin: true })
  ];

  it('gives each tab exactly its own rows', () => {
    expect(rowsForTab(verbs, 'KillStart').map((r) => r.verb)).toEqual(['kill-all']);
    expect(rowsForTab(verbs, 'Settings').map((r) => r.verb)).toEqual(['startup-install']);
    expect(rowsForTab(verbs, 'Debugging').map((r) => r.verb)).toEqual(['demo-stream']);
  });

  it('covers every rendered verb exactly once across all eight tabs', () => {
    const seen = TAB_IDS.flatMap((id) => rowsForTab(verbs, id).map((r) => r.verb));
    expect(seen).toEqual(verbs.filter((v) => v.renderInGui).map((v) => v.verb));
    expect(new Set(seen).size).toBe(seen.length);
  });

  it('renders nothing for the hand-built surfaces', () => {
    // Customization and About carry no registry verbs in this table; an empty
    // row list is the correct render for them, not a broken grouping.
    expect(rowsForTab(verbs, 'Customization')).toEqual([]);
    expect(rowsForTab(verbs, 'About')).toEqual([]);
  });
});

describe('switching tabs never touches the accumulated console', () => {
  const batch = (runId: string, count: number): OutputBatch => ({
    runId,
    lines: Array.from({ length: count }, (_, i) => ({ stream: 'stdout', text: `line ${i}` }))
  });

  beforeEach(() => {
    console_.clear();
  });

  it('keeps the transcript when the active tab changes', () => {
    console_.begin('demo-stream', 'run-1');
    console_.append(batch('run-1', 5));

    // The switch the strip performs: resolve a different active tab. The console
    // store is app-level state, so this must not clear, trim or replace it.
    const switched = resolveActiveTab(tabs(), 'KillStart');
    expect(switched?.id).toBe('KillStart');
    expect(console_.lineCount).toBe(5);
    expect(console_.lines.map((l) => l.text)).toEqual([
      'line 0',
      'line 1',
      'line 2',
      'line 3',
      'line 4'
    ]);
    console_.finish({
      runId: 'run-1',
      verb: 'demo-stream',
      exitCode: 0,
      cancelled: false,
      timedOut: false,
      durationMs: 5,
      stdout: '',
      stderr: '',
      summary: ''
    });
  });

  it('keeps accumulating across a switch while a run is live', () => {
    console_.begin('demo-stream', 'run-1');
    console_.append(batch('run-1', 3));
    resolveActiveTab(tabs(), 'Uninstall');
    console_.append(batch('run-1', 4));
    expect(console_.lineCount).toBe(7);
    expect(console_.busy).toBe(true);
    console_.finish({
      runId: 'run-1',
      verb: 'demo-stream',
      exitCode: 0,
      cancelled: false,
      timedOut: false,
      durationMs: 5,
      stdout: '',
      stderr: '',
      summary: ''
    });
  });

  it('keeps the finished verdict after the switch, and only Clear empties', () => {
    console_.begin('demo-stream', 'run-1');
    console_.append(batch('run-1', 2));
    console_.finish({
      runId: 'run-1',
      verb: 'demo-stream',
      exitCode: 0,
      cancelled: false,
      timedOut: false,
      durationMs: 5,
      stdout: '',
      stderr: '',
      summary: ''
    });
    resolveActiveTab(tabs(), 'About');
    expect(console_.lineCount).toBe(2);
    expect(console_.state).toBe('succeeded');
    console_.clear();
    expect(console_.lineCount).toBe(0);
  });
});
