# WPF — Add Later (exemptions)

> **Purpose (Davood's instruction, 2026-10-10):** work proceeds on the **Rust**
> track only. Every item the Rust build carries, or must fix, that the WPF
> build should later match is recorded HERE, to be handled in a future WPF
> session — never silently dropped, never silently applied to the Rust track.
>
> Each item names: what the Rust build does today, what the WPF build does
> today (per its green suite `tests/ticket12-theme-elevation.tests.ps1`,
> `tests/ticket10-dashboard-shell.tests.ps1`, `tests/ticket11-threading.tests.ps1`),
> the gap, and the later action. "No action" items are marked as such —
> the doc records parity decisions, not just work.

---

## 1. Verb-registry divergences (from the parity suite, session 10)

`tests/ticket10-registry-parity.tests.ps1` encodes two **sanctioned**
Rust-only divergences and fails on anything else:

| Divergence | Rust side | WPF side | Later action |
|---|---|---|---|
| `ignore-dashboard` verb | present since Rust ticket 03 (`d64ec0c`) | absent | Add to the WPF table **before the Phase-4 cutover** (roadmap Q4/Q3), or retire when the WPF EXE stops shipping |
| export/import/demo-stream hint + action_label copy | Rust-only since ticket 07 (`5f8bf04`) | absent | same decision as above |

**Constraint:** the Rust build ships ALONGSIDE the WPF EXE until Phase 4
(roadmap Q4), so the Rust table is the active one; these exemptions are
reviewed and named in the parity suite, and any NEW unreviewed difference
fails it.

---

## 2. Ticket 11 — threading / no-lag contract

- **WPF:** fully implemented (green suite, 67 assertions; Dispatcher batching,
  cancellation, default timeout).
- **Rust:** implemented in `dashboard_core::execute` (tokio tasks, one
  `OutputBatch` per ~50 ms window, `request_cancel`, overrun timeout,
  tree kill) — audited session 11 (2026-10-10): cargo 30/30 incl. the
  execution contract, npm 78/78, command layer inspected.
- **Gap:** none architectural; the two are independent implementations of one
  contract.
- **Later action:** none. If a defect is ever found in one, check the other.

---

## 3. Ticket 12 — theme + elevation (Rust twin finished session 11)

The WPF build already satisfied the ticket in full (ThemeService via WPF-UI,
the exact dialog wording, the registry-generated message, the CLI gate, the
refusal before launch). The Rust twin now matches it; the differences below
are **strengths of the Rust build** the WPF build may adopt later, in priority
order:

1. **Admin badge on rows.** Rust renders `badge-admin` (warning-coloured,
   deliberately not the read-only accent) on every row with `requiresAdmin`,
   so the need for Administrator is visible before a click. WPF: no badge
   found; the dialog explains it only after the click. *Adopt if desired.*
2. **Persistent elevation chip.** Rust shows a `Not elevated` header chip from
   the backend's own token probe (`app_info.elevated`), so an unelevated
   session is explained before any dialog. WPF: no equivalent. *Adopt if
   desired.*
3. **One structured exit code (5).** The Rust CLI's gate returns
   `EXIT_NEEDS_ELEVATION = 5` through the SAME result type as every other
   outcome (unknown verb 2, missing script 127, cancelled 130) — the same code
   the installer wrapper uses for an elevation refusal. WPF: returns non-zero
   (its suite asserts the sign, not the code). *Consider aligning on 5.*
4. **One gate for both consumers.** Rust's gate lives in
   `dashboard_core::elevation_gate` and both the window and the CLI run
   through it, so the frontend dialog and the CLI refusal can never name
   different features. WPF duplicates the decision per consumer (its suites
   assert each separately). *No action required; note when refactoring.*
5. **Theme persistence + corrupted-value fallback.** Rust remembers the choice
   (`komorebi-dashboard-theme`), falls back to the documented default on junk,
   and sets `color-scheme` for native controls. WPF-UI handles the theme
   switch its own way; the persistence semantics are the only transferable
   part. *Adopt if desired.*

---

## 4. Standing items (unchanged)

- Roadmap **Q3**: binary name (`KomorebiDashboard.exe` vs
  `komorebi-dashboard.exe`) — decided for the Rust track (`komorebi-dashboard.exe`);
  the WPF references (`ignore-dashboard.ps1`, shortcuts, docs) must be updated
  in the same ticket if/when the WPF build is touched.
- The Rust EXE's `-BackupPath` advertisement (session 9) has no WPF counterpart
  need; WPF uses its own backup flow.

---

## Davood's decision on the §3 items (2026-10-10, session 11)

When the WPF track resumes, the §3 strengths above (per-row admin badge,
"Not elevated" chip, exact exit 740, the one-gate contract, theme persistence)
are to be implemented **properly and standardly** — as real features with their
own suites, not as an ad-hoc port. In particular the badge/chip must come from
the same registry-flag source the Rust twin uses (a second hand-rolled list is
how the two builds drifted in the first place), and the exit code must be the
shared contract (740), not the WPF-era value.
