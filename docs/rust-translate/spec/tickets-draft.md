# rust-translate — Approved ticket breakdown (source: `to-tickets`, 2026-10-08)

**Status:** APPROVED · **Result:** 13 tickets published to `../tickets/` and
`~/projects/komorebi-1click/.scratch/rust-translate/issues/` · **Date:** 2026-10-08

## What changed from the original 12-ticket proposal

- **Ticket 03 split into 03 (registry + CLI twin) and 04 (eight tabs).** It was the largest and
  riskiest ticket: 35 verbs plus eight views plus the CLI in one context window. Splitting keeps each
  slice sized for a fresh context window while both remain vertical — the CLI ticket's presentation
  surface is the CLI, which is a real surface under ADR-0013, and the tabs ticket's is the GUI.
- Everything else kept the proposed order and edges. Test strategy confirmed as hybrid, with the CLI
  twin as the primary seam.

## The 13 tickets

| # | Title | Blocked by |
|---|---|---|
| 01 | Scaffold and the first tracer bullet — two verbs end to end | **None (start immediately)** |
| 02 | Execution contract — batching, cancel, timeout, tree kill | 01 |
| 03 | Registry completeness and the CLI twin | 01 |
| 04 | Eight tabs rendered from the registry | 03 |
| 05 | Elevation (ADR-0012) | 04 |
| 06 | Settings persistence and the Settings tab | 04 |
| 07 | Visual system — theme and accent | 01 |
| 08 | Typography and UI scale | 07 |
| 09 | Console pane behaviour | 02, 04 |
| 10 | AutoHotkey tab | 04, 06 |
| 11 | Customization tab and About tab | 06, 07, 08 |
| 12 | Packaged deliverable | 05, 06, 07, 08, 09, 10, 11 |
| 13 | Verification and the translated regression net | 12 |

## Blocking graph

```
01 ─┬─ 02 ─────────────┬─ 09 ─┐
    ├─ 03 ─ 04 ─┬─ 05 │      │
    │           ├─ 06 ─┼─ 10 │
    │           │      │      ├─ 12 ─ 13
    └─ 07 ─ 08 ─┴─ 11 ─┘      │
                    └──────────┘
```

- **Start here:** 01 — the only ticket with no blockers, and the prefactor for everything else.
- **Frontier after 01:** 02, 03 and 07 become available together.
- **Longest path:** 01 → 03 → 04 → 06 → 11 → 12 → 13.
- **Parallel lanes:** 07/08 (appearance) and 02 (execution) can run beside 03/04/05/06 (behaviour).

## Working the frontier

Work the set in dependency order rather than numeric order once 01 lands: a ticket may start only
when every entry in its **Blocked by** line is done. Do not close or edit a parent issue. After each
ticket, append a dated line to §5 of `handoff.md` so an interrupted session can resume.
