// Ticket 03 — the frontend's half of the registry contract.
//
// The backend owns the table and the grouping; what this side must get right is
// that a tab renders exactly the rows that belong to it and that are meant to be
// seen. That is worth its own test because the tracer's placeholder returned the
// WHOLE table, which was exact with two verbs and would silently draw an
// administrative verb inside the Debugging tab once the table grew.
import { describe, expect, it } from 'vitest';
import { rowsForTab } from '../lib/registry.svelte.ts';
import type { VerbDefinition } from '../lib/ipc';

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

describe('rows come from the registry, filtered by tab', () => {
  it('renders only the rows that belong to the rendered tab', () => {
    const verbs = [
      verb({ verb: 'status', tab: 'Debugging' }),
      verb({ verb: 'demo-stream', tab: 'Debugging' }),
      verb({ verb: 'uninstall', tab: 'Uninstall', requiresAdmin: true }),
      verb({ verb: 'restart-all', tab: 'Restart' })
    ];
    const rows = rowsForTab(verbs, 'Debugging');
    expect(rows.map((r) => r.verb)).toEqual(['status', 'demo-stream']);
  });

  it('never puts an administrative verb in a read-only tab', () => {
    // This is the regression the tracer's placeholder would have introduced:
    // `uninstall` is in the same table, and returning the table unfiltered would
    // have drawn an admin action under Debugging.
    const verbs = [
      verb({ verb: 'status', tab: 'Debugging' }),
      verb({ verb: 'cleanup', tab: 'Uninstall', requiresAdmin: true })
    ];
    expect(rowsForTab(verbs, 'Debugging').some((r) => r.requiresAdmin)).toBe(false);
  });

  it('suppresses a verb that has no row of its own', () => {
    // `startup` is a real, dispatchable verb with no row: `startup-install` and
    // `startup-remove` supersede it. Rendering it would offer the user a button
    // that runs `komorebi-service.ps1` with a default action.
    const verbs = [
      verb({ verb: 'startup', tab: 'Settings', renderInGui: false }),
      verb({ verb: 'startup-install', tab: 'Settings', requiresAdmin: true }),
      verb({ verb: 'startup-remove', tab: 'Settings', requiresAdmin: true })
    ];
    expect(rowsForTab(verbs, 'Settings').map((r) => r.verb)).toEqual([
      'startup-install',
      'startup-remove'
    ]);
  });

  it('preserves the order the registry declares rather than sorting', () => {
    // Order is the registry's tab order, which is the order the WPF build showed.
    // Sorting alphabetically would put Kill All after Kill YASB and change the
    // muscle memory the rewrite is meant to preserve.
    const verbs = [
      verb({ verb: 'kill-all', tab: 'KillStart' }),
      verb({ verb: 'kill-komorebi', tab: 'KillStart' }),
      verb({ verb: 'kill-whkd', tab: 'KillStart' }),
      verb({ verb: 'kill-yasb', tab: 'KillStart' })
    ];
    expect(rowsForTab(verbs, 'KillStart').map((r) => r.verb)).toEqual([
      'kill-all',
      'kill-komorebi',
      'kill-whkd',
      'kill-yasb'
    ]);
  });

  it('renders nothing for a tab that carries no verbs', () => {
    // Customization and About are hand-built surfaces, so an empty row list is
    // correct for them rather than a sign of a broken grouping.
    const verbs = [verb({ verb: 'status', tab: 'Debugging' })];
    expect(rowsForTab(verbs, 'About')).toEqual([]);
  });
});