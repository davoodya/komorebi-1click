# Handoff — Last Session (2026-10-10, session 4)

> **Purpose.** This is the entry log for the latest work session. The full
> continuation document is now **`handoff.md`** in this directory — the two
> previous handoff documents were merged into it, and this file records only what
> session 4 did on top of that.

---

## 1. What this session was

Two questions left over from ticket 02 were answered by Davood, and this session
applied the answers:

1. **Cheatsheets** — Persian or English? → **Both.** A Persian version and an
   English version of every cheatsheet.
2. **Timing thresholds** — a trade-off between strict and relaxed. → **Dual-mode**:
   strict by default, relaxed opt-in, each recorded explicitly.

Both are recorded as ADRs so the next agent inherits them as decisions, not as
ambient knowledge.

---

## 2. Files changed this session

```text
MODIFIED
 tests/rust-ticket02-probe.ps1                     dual-mode thresholds (ADR-0019)
 docs/rust-translate/handoff.md                    merged handoff (the continuation doc)
 docs/rust-translate/implement/BUILD-CHECKLIST.md  ticket-02 probe section
 docs/rust-translate/handoff-last-session.md       this file, retargeted

NEW
 docs/rust-translate/spec/ADR-0019-dual-mode-thresholds.md
 docs/rust-translate/spec/ADR-0020-bilingual-cheatsheets.md
 cheatsheets/en/komorebi-description.md           new translation
 cheatsheets/en/komorebi-hotkeys.md               new translation, from the dev-tree source
 cheatsheets/fa/komorebi-description.md           moved from cheatsheets/
 cheatsheets/fa/komorebi-hotkeys.md               refreshed from the dev-tree source
```

Nothing was committed. Nothing under `src/`, `scripts/`, or `config/` was touched.

---

## 3. Thresholds — ADR-0019

`tests/rust-ticket02-probe.ps1` had hard-coded timing tolerances (3000–15000 ms
timeout, <250 ms worst gap, <30000 ms batching, cancel inside half the budget).
Those are only honest on an idle machine; under load the tightest assertions fail
and then pass again on an idle machine.

The probe now selects a tolerance set explicitly:

| | strict (default) | relaxed |
|---|---|---|
| `$MinTimeoutMs` | 3000 | 2900 |
| `$MaxTimeoutMs` | 15000 | 45000 |
| `$MaxWorstGapMs` | 250 | 900 |
| `$MaxBatchingMs` | 30000 | 90000 |
| cancel budget ratio | `/2` | `/4` |

* Default is strict; a release may only pass strict.
* Relaxed is `-Relaxed`, `-ThresholdMode relaxed`, or
  `DASHBOARD_THRESHOLD_MODE=relaxed`.
* The mode is printed on line 1 and carried in every assertion message.
* `-Strict` combined with a relaxed parameter **exits 3** rather than picking one.

**Measured:** strict passes 26/26 on this machine; relaxed passes 26/26; the
conflict path exits 3 as designed.

**One environment caveat found and recorded:** `DASHBOARD_THRESHOLD_MODE` set in
WSL does **not** reach the probe through `win-exec.sh` — it does not propagate
environment variables across the interop boundary. Pass the parameter explicitly
when invoking from WSL.

---

## 4. Cheatsheets — ADR-0020

The cheatsheets were Persian-only. They now split by language:

```
cheatsheets/
  fa/  Persian (the originals, source of truth)
  en/  English (the translations)
```

Rules the ADR sets: separate documents (not bilingual files), cross-linked in the
header, hotkeys and commands copied **verbatim** so the two files describe the
same configuration, only the description column translated, and the Persian file
is authoritative when a binding changes.

Done this session:

| File | Size | Note |
|---|---|---|
| `fa/komorebi-description.md` | 13.9 KB | moved from `cheatsheets/` |
| `en/komorebi-description.md` | 11.0 KB | translated |
| `fa/komorebi-hotkeys.md` | 15.0 KB | refreshed from the newer dev-tree version |
| `en/komorebi-hotkeys.md` | 13.5 KB | translated, 158 binding rows identical to the source |

The hotkeys file was translated **mechanically** from the Persian source rather
than retyped, and verified: all 158 hotkey/command pairs are identical between the
two files, and the English file contains zero Arabic-script characters. The
Jalali change-log dates were converted programmatically (`1405/07/09` → 2026-10-01
etc.) with a note that the Jalali dates stay authoritative.

**Important:** the English translation was built from the dev-tree source at
`~/projects/komorebi-1click/cheatsheets/komorebi-hotkeys.md` (18.8 KB, 334 lines),
which is **newer** than the previously published copy — it has section 3.5
(`focus-monitor-workspace`), the `Alt + C`/`Alt + V` stack bindings, and the
`wsl.exe`/`notepad++.exe` rows the old published copy lacked. The published `fa/`
copy is now refreshed from it.

**Not done** (large reference documents, deferred to a later session):

| File | Size |
|---|---|
| `komorebi-configuration.md` | 61 KB |
| `komorebi-debugging.md` | 91 KB |
| `Komorebi-Hotkey-Cheatsheet.md` | 59 KB — **deprecated**, carries a redirect header; needs no translation |

---

## 5. The handoff document is merged

`handoff.md` was the strategy document (last updated 2026-10-08, after the ticket
stage — it still said "no code has been written yet"). It now carries the full
state through ticket 03, and `handoff-last-session.md` from session 3 is folded
into it.

**`handoff.md` is the continuation document.** This file is now just the session-4
log.

The merged document contains, in order: one-line status, project background, the
C# inventory, the C#→Rust map, ticket status, the registry (the single table,
35 verbs), the verification baseline you must re-run, the decisions Davood locked,
the ADRs, known gaps and defects (R1–R4, US 55's unprovable delivery), the exact
resume point (ticket `04-eight-tabs`), files changed, the rules that bind the
project, and the mandatory reading order.

---

## 6. The project state is unchanged

No code changed. The Rust tree is exactly where session 3 left it:

* Tickets `01`, `02`, `03` done and verified.
* Next is **`04-eight-tabs`** — a frontend task; the backend (`TABS`,
  `verbs_in_tab`, `list_tabs`) is already in place.
* The one `SKIP` is still `delivered-interrupt` in
  `tests/rust-ticket03-interrupt.mjs`, for the measured ConPTY reason recorded in
  `handoff.md` §8. It converts to PASS from a real interactive console.
* Nothing is committed.

**Read `handoff.md`, not this file, to continue.**
