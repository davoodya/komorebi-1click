import { describe, expect, it } from 'vitest';
import { RowState, rowsFrom } from '../lib/rows.svelte.ts';
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

describe('row state', () => {
  it('hides the value box for a verb that takes no arguments', () => {
    const row = new RowState(verb());
    expect(row.acceptsValue).toBe(false);
    row.value = 'ignored';
    expect(row.args()).toEqual([]);
  });

  it('shows a value box for a verb that takes arguments', () => {
    const row = new RowState(
      verb({ verb: 'demo-stream', acceptsArguments: true, hint: 'Number of lines (default 50)' })
    );
    expect(row.acceptsValue).toBe(true);
    row.value = '-Lines 120';
    expect(row.args()).toEqual(['-Lines', '120']);
  });

  it('owns its value: two rows with the same verb never share text', () => {
    const definition = verb({ acceptsArguments: true });
    const first = new RowState(definition);
    const second = new RowState(definition);
    first.value = 'from the first row';
    expect(second.value).toBe('');
    expect(second.args()).toEqual([]);
  });

  it('reuses the existing row when the registry is re-read', () => {
    const definition = verb({ acceptsArguments: true });
    const original = new RowState(definition);
    original.value = '-Lines 10';
    const next = rowsFrom([definition], [original]);
    expect(next).toHaveLength(1);
    expect(next[0]).toBe(original);
    expect(next[0].args()).toEqual(['-Lines', '10']);
  });

  it('drops rows whose verb left the registry and keeps registry order', () => {
    const a = new RowState(verb({ verb: 'status' }));
    const b = new RowState(verb({ verb: 'demo-stream' }));
    const next = rowsFrom([verb({ verb: 'demo-stream' }), verb({ verb: 'status' })], [a, b]);
    expect(next.map((row) => row.verb.verb)).toEqual(['demo-stream', 'status']);
  });
});
