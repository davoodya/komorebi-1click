// Ticket 12 — the elevation gate, the frontend's half.
//
// The gate is pure on purpose: whether a verb needs Administrator comes from
// the registry row the backend serves, whether this shell is elevated comes
// from `appInfo`, and the only thing left is the small decision between them
// — which lives here, testable without a window. The dialog is the UI of that
// decision; its button set and title are constants because the ticket names
// them, and the feature list it shows is generated from the registry (never a
// string typed into the dialog).

/** What the shell should do when a verb is clicked. */
export type GateDecision = 'run' | 'offer-relaunch';

/**
 * Decide what a click should do.
 *
 * An administrative verb in an unelevated shell offers a relaunch; every
 * other combination runs. The check does not consult anything but the two
 * facts it is given, so a unit test can hold both.
 */
export function elevationGate(requiresAdmin: boolean, elevated: boolean): GateDecision {
  return requiresAdmin && !elevated ? 'offer-relaunch' : 'run';
}

/**
 * The feature names the elevation dialog names: every registry row that needs
 * Administrator, by its button label, in registry order, deduplicated.
 *
 * Generated from the table for the same reason the backend generates its own
 * list — a second, hand-typed copy of the registry's flags is exactly what
 * ADR-0013 exists to prevent, and the ticket calls the generic message out by
 * name as not good enough.
 */
export function adminFeatures(verbs: { label: string; requiresAdmin: boolean }[]): string[] {
  const features: string[] = [];
  for (const verb of verbs) {
    if (verb.requiresAdmin && !features.includes(verb.label)) features.push(verb.label);
  }
  return features;
}

/** The dialog's title, exactly as the ticket names it. */
export const ELEVATION_DIALOG_TITLE = 'Rerun as Administrator';

/** The dialog's actions, in button order: acknowledge, relaunch, cancel. */
export const ELEVATION_DIALOG_BUTTONS = ['OK', 'Rerun as Administrator', 'Cancel'] as const;
