// Per-row state. A row owns its own typed value; the registry entry it renders
// is shared and immutable (parity with the WPF build's VerbRow model, which
// exists precisely so typing into one row cannot rewrite another).
import { parseArguments } from './format';
import type { VerbDefinition } from './ipc';

export class RowState {
  /** What the user typed into THIS row's box. */
  value = $state('');

  constructor(readonly verb: VerbDefinition) {}

  /**
   * True when the row shows a value box.
   *
   * `acceptsArguments` is the registry's own shape flag (a `<x>` or `[x]` in the
   * declared arguments). The hint is also honoured because a verb that documents
   * a value for the user must offer somewhere to type it; for the two tracer
   * verbs both fields agree, and ticket 03 makes the flag authoritative.
   */
  get acceptsValue(): boolean {
    return this.verb.acceptsArguments || this.verb.hint.trim().length > 0;
  }

  /** The extra arguments for a run of this row, and only this row. */
  args(): string[] {
    return this.acceptsValue ? parseArguments(this.value) : [];
  }
}

/** One row per verb, in registry order. */
export function rowsFrom(verbs: VerbDefinition[], existing: RowState[]): RowState[] {
  const byVerb = new Map(existing.map((row) => [row.verb.verb, row]));
  return verbs.map((verb) => byVerb.get(verb.verb) ?? new RowState(verb));
}
