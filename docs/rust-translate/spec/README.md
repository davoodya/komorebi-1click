# rust-translate — Specification stage

**Stage:** Specification (Phase 1 of `../roadmap.md`) · **Status:** spec complete, awaiting ticket
creation · **Date:** 2026-10-08

## What is in this directory

| File | Purpose |
|---|---|
| `spec.md` | The specification. Template: Problem Statement · Solution · User Stories (84) · Implementation Decisions · Testing Decisions · Out of Scope · Further Notes |
| `ADR-0017-rust-tauri-dashboard.md` | The architectural decision record for this rewrite, continuing the repo's ADR series (0001–0016) |
| `tickets-draft.md` | Proposed 12-ticket vertical-slice breakdown with blocking graph — the input for `to-tickets`, awaiting approval |

## Companion documents (one level up)

`handoff.md` (translation strategy) · `knowledges.md` (verbs, invariants, host facts) ·
`bugs-fixing.md` (defects that must not return) · `codebase-inventory.md` (per-file map C# → Rust,
17 behaviours that must survive) · `environment.md` (toolchain probe, guard bypass, build strategy) ·
`roadmap.md` (phases R01–R12, risk register, definition of done)

## Tracker state

- Canonical tracker spec: `~/projects/komorebi-1click/.scratch/rust-translate/spec.md`
  (`Status: ready-for-agent`). **It is byte-identical to `spec/spec.md` — keep them in sync.**
- Tickets **created 2026-10-08**: 13 of them, at `.scratch/rust-translate/issues/NN-<slug>.md`
  numbered `01`–`13` in dependency order, each `Status: ready-for-agent`. Mirrored byte-for-byte at
  `../tickets/`.

## What tickets creation resolved

All four points that were open at the spec stage are now closed:

1. **Primary seam** = verb dispatch through the CLI twin → **confirmed** (hybrid test strategy).
2. **Adopted defaults** (hybrid testing, ported full-font enumeration, publish-side-only documents)
   → **confirmed**.
3. **Executable name kept as `KomorebiDashboard.exe`** → **confirmed**; no shipped script changes.
4. **Granularity** → quality over quantity, standard ticket sizing → **13 tickets**; the one split
   made was registry/CLI (03) versus tabs (04), because the original combined ticket was the largest
   and riskiest in the set.

**Sequence:** ticket 01 is the only one with no blockers; every other ticket lists its gate.

## Conventions applied

- All documents in this stage are **English**, per the project language rule.
- The ADR is filed here rather than in `docs/adr/` because this stage's artifacts are kept together;
  promote it to `docs/adr/0017-rust-tauri-dashboard.md` when the rust-translate effort is merged into
  the main doc tree.
