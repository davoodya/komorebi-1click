// Ticket 12 — the elevation gate, the frontend's half.
//
// The gate has to be pure: a UI that decides "this verb needs Administrator"
// by poking at window chrome cannot be tested, and an elevation mistake is
// the kind that either blocks a legitimate action or runs an administrative
// script unelevated. So the decision lives here as one function, and the
// feature names the dialog shows are derived from the registry rows the
// backend serves — never from a string someone typed into the dialog.
import { describe, expect, it } from 'vitest';
import {
  ELEVATION_DIALOG_TITLE,
  ELEVATION_DIALOG_BUTTONS,
  adminFeatures,
  elevationGate
} from '../lib/elevation';
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

describe('the elevation gate', () => {
  it('offers a relaunch for an administrative verb while unelevated', () => {
    expect(elevationGate(true, false)).toBe('offer-relaunch');
  });

  it('runs an administrative verb once the shell is elevated', () => {
    expect(elevationGate(true, true)).toBe('run');
  });

  it('never gates a non-administrative verb, elevated or not', () => {
    expect(elevationGate(false, false)).toBe('run');
    expect(elevationGate(false, true)).toBe('run');
  });
});

describe('the feature names the dialog shows', () => {
  it('names exactly the rows that carry RequiresAdmin, in registry order', () => {
    const features = adminFeatures([
      verb({ verb: 'kill-all', label: 'Kill All', requiresAdmin: true }),
      verb({ verb: 'status', label: 'Status', requiresAdmin: false }),
      verb({ verb: 'uninstall', label: 'Uninstall', requiresAdmin: true })
    ]);
    expect(features).toEqual(['Kill All', 'Uninstall']);
  });

  it('is empty when no verb needs Administrator', () => {
    expect(adminFeatures([verb({ requiresAdmin: false })])).toEqual([]);
  });

  it('deduplicates a repeated label without reordering', () => {
    const features = adminFeatures([
      verb({ verb: 'kill-all', label: 'Kill All', requiresAdmin: true }),
      verb({ verb: 'kill-komorebi', label: 'Kill All', requiresAdmin: true }),
      verb({ verb: 'status', label: 'Status', requiresAdmin: false })
    ]);
    expect(features).toEqual(['Kill All']);
  });
});

describe('the dialog contract', () => {
  it('is titled what the ticket names', () => {
    expect(ELEVATION_DIALOG_TITLE).toBe('Rerun as Administrator');
  });

  it('offers exactly the three named actions, the relaunch in the middle', () => {
    expect(ELEVATION_DIALOG_BUTTONS).toEqual(['OK', 'Rerun as Administrator', 'Cancel']);
  });
});
