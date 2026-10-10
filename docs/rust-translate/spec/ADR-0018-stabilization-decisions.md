# ADR-0018 — Stabilization decisions: verb count, argument order, CI, settings compatibility

**Status:** Accepted · **Date:** 2026-10-09 · **Supersedes:** nothing partially — it corrects counts in
ADR-0017's companion documents · **Companion to:** ADR-0017, ADR-0009, ADR-0012, ADR-0013
**Scope:** the Rust translation of the Admin Dashboard, beginning with ticket 03.

## Context

The planning stage (spec + tickets) deliberately deferred four questions. They were deferred because
the answer did not change the *shape* of the design — but each one now blocks, or would silently
corrupt, a ticket that is about to be implemented. Ticket 03 in particular cannot be accepted without
the first of them.

The four are: the registry's real size, what "fixed arguments before user arguments" actually
guarantees, whether the translation gets CI, and whether settings may be improved while still reading
a file written by the WPF build. Two further facts were discovered while implementing ticket 02 and
belong in the same record, because they are corrections to what the project believed about itself.

The forcing issue is the **registry count**. `knowledges.md`, `roadmap.md`, `spec.md`, ADR-0017 and
ticket 03 all say **28 verbs**. A parser over `VerbRegistry.cs` — run twice, independently, and
cross-checked against a hand count — finds **35**. Ticket 03's first acceptance criterion is "All 28
verbs are registered", so as written that criterion is unsatisfiable: 35 registered means it fails
literally, and 28 registered means seven working features are deleted. The number has to be settled
by decision, not by whichever document is read first.

## Decision

### 1. The registry has 35 verbs, and the shipped set is the contract

**35 verbs, not 28.** The rows are the record, not the prose:

| Measure | Count |
|---|---:|
| Registered verbs | **35** |
| Rendered GUI rows (`RenderInGui: true`) | 31 |
| CLI-only rows (`RenderInGui: false`) | 4 |
| Verbs requiring Administrator | 10 |
| Read-only verbs | 6 |
| Distinct `.ps1` files reached | 22 |
| Tabs carrying registry verbs | 6 of 8 |

The four CLI-only rows are `startup`, `ahk`, `ahk-enable`, `ahk-disable` — each superseded in the GUI
by a more specific pair of rows (`startup-install`/`startup-remove`, `ahk-enable-all`/`ahk-disable-all`)
while remaining fully dispatchable. The two tabs with no registry verbs are **Customization** and
**About**, which are hand-built surfaces; verbs are grouped under the other six.

**How the 28 arose:** it is the count from an earlier ADR-0013 revision and was copied forward into
each later document, where it was repeated rather than re-derived. It is a stale number, not a
different scope: every document that says 28 also lists rows that add up to more than 28.

**Rule:** every document, ticket and acceptance criterion states **the count the registry actually
carries**, and the completeness criterion is "every registered verb resolves to an existing script and
appears under exactly one tab", not a literal number that a future row addition would falsify. A
number in prose that no test derives is a number that will drift again; the count is therefore
asserted by a test over the table, and prints itself, so the prose can be checked rather than trusted.

### 2. Fixed arguments are applied before user arguments as a **contract order**

The rule from `codebase-inventory.md` §3.6 is preserved: `FixedArguments` are appended **before** the
arguments the user typed. What changes is the **reason recorded for it**.

The old justification — "PowerShell takes the last occurrence of a parameter" — is **false**, and was
measured in the audit: invoking `pwsh -File script.ps1 -Action status -Action install` fails outright
with `ParameterAlreadyBound` and a non-zero exit. PowerShell's parameter binder *rejects* a duplicate
named parameter in a `-File` invocation; it does not let the later one win.

So the order is kept for two reasons that are true:

1. **Parity.** The WPF build ordered them this way, and this work preserves behaviour rather than
   re-deciding it. Changing the order would be a behavioural change smuggled in under a refactor.
2. **Alias shadowing.** A user-supplied alias of a fixed parameter is a *different* code path than a
   duplicate literal name, and the order determines which binding wins. Keeping fixed-first keeps that
   path identical to the build being replaced.

**Consequence:** no shipped script is touched to "make" the old rationale true, and the rationale is
not restated anywhere as fact. A registry row that lets a user reach a fixed parameter by name is a
contract question for the registry, not a reason to edit a script.

### 3. This effort gets CI/CD, as a local gate first and a hosted gate only if it can be honest

Two facts drive the decision: **the build host is Windows** (MSVC `link.exe` + WebView2, ADR-0017), and
**almost every meaningful assertion in this project is a runtime measurement on Windows** — process
trees, batching intervals, UI Automation over a live window.

Therefore CI is adopted in layers, and each layer must be genuinely reproducible before the next is
claimed:

| Layer | What it runs | Where | Status |
|---|---|---|---|
| 1. Local contract | The four phases of `build.ps1` plus the non-destructive runtime suites | Windows, developer-driven | **exists today** — this is the current gate |
| 2. Repeatable clean-tree gate | The same contract from a `git worktree` checkout with **0 dirty files**, plus the shipped-text check | Windows | **exists today**, run per ticket |
| 3. Hosted CI | Layer 2 in a Windows runner with WebView2 | GitHub Actions `windows-latest` | **adopted, to be added** — blocked on runner capability, not on intent |

Constraints that keep layer 3 honest, and are the reason it is not simply switched on now:

- **Timing-sensitive assertions must not gate a hosted build.** Two measured runs of the identical
  commit produced different artifact hashes, and under load the tightest tolerances (3 s budget
  honoured, inter-batch gap, cancel-to-verdict) reported 3/26 and 1/11 failures that re-ran clean on an
  idle machine. A CI gate that fails for machine load trains people to ignore it. Hosted CI runs the
  **deterministic** half — static checks, shipped-text check, `cargo test`, frontend tests, the CLI
  twin — and the **timing probes stay a locally-run, human-read artifact**.
- **The artifact is not byte-reproducible**, by design (`DASHBOARD_GIT_SHA` is stamped in, and the PE
  carries linker metadata). CI must never assert an artifact hash; it asserts *0 dirty files + exit 0 +
  a functional run*, which is the proof technique already retired-and-replaced in ticket 02.
- **WebView2 availability is a runner precondition**, not something to discover mid-build.
- **No secret is required**, so nothing about this gate depends on repository or organization settings.

Until layer 3 exists and passes, no document may claim "CI is green" for this module. The honest
statement is the one that is true: *the four-phase contract plus the runtime suites pass on the Windows
build host, and from a clean checkout.*

### 4. Settings stay compatible first; improvements are additive and explicit

The WPF build's settings file must keep loading, because a user's preferences are the one thing a
rewrite can destroy silently.

The audit found that the spec's description of the settings engine is **aspirational, not descriptive**
of the current code: `DefaultConsolePercent` is **25** in source while the documents say **35**;
`Normalize` replaces an out-of-range value with the default rather than clamping it to the bound; and
`Save` does not call `Normalize` despite its own comment.

**Decision:** the Rust implementation reads and writes the WPF file format, and:

- **Keys are read case-insensitively** and written in the existing **PascalCase** form, so an old file
  upgrades with no migration step and a new file is readable by the old build.
- **Defaults live on the type**, so a key absent from an older file is filled in rather than becoming a
  zero.
- **Out-of-range handling preserves the WPF behaviour** observed in source (fall back to the default),
  *except* where ticket 06's acceptance says "clamped" — that wording describes the *desired* engine.
  The gap is resolved by implementing the WPF-compatible behaviour, asserting it, and recording the
  discrepancy in ticket 06 rather than quietly picking one reading.
- **Console percent default is 25**, matching the code and not the documents.
- **Atomic temp-then-rename save and corrupt-file quarantine stay mandatory** — these are unambiguous
  and are not in tension with compatibility.

### 5. Two corrections to the project's own record

Both were found while implementing ticket 02 and are recorded here so no later document repeats them:

1. **A time-out is a recorded fact, never an inferred exit code.** Ticket 01 inferred a timeout from
   exit 124 and a cancellation from 130. The backend that observes the stop now sets `cancelled` /
   `timedOut` on the result, and the frontend reads those flags. Inferring a verdict from a number is
   how "cancelled" collapses into "failed".
2. **"English-only shipped text" is a statement about language, not character encoding.** ADR-0017
   rule 7 governs CJK, Hangul, Cyrillic, Arabic, Hebrew, Thai and Devanagari codepoints in shipped
   text. English punctuation — em dashes, curly quotes, ellipses — is English, is used by the very WPF
   build being translated, and banning it would be a parity regression. The rule is enforced by
   `tests/check-shipped-text.mjs` inside `build.ps1`, so it is machine-checkable rather than a matter
   of reviewer interpretation.

## Rationale

- **The registry is the product's spine.** ADR-0013 makes it the single source for GUI rows, CLI
  dispatch, `--help` and the elevation message. Two of those four consumers are generated *from* the
  count, so a wrong count is not a documentation wart — it is an acceptance criterion that cannot be
  satisfied and a feature set that would be silently trimmed to fit a sentence.
- **A stale rationale is worse than a missing one.** The duplicate-parameter justification was
  plausible, repeated across documents, and false. It survived because it was never executed. Keeping
  the order while correcting the reason means the next reader tests the contract rather than the myth.
- **CI is worth having only where it is deterministic.** Adopting a hosted gate that fails on machine
  load would be a net loss of trust; adopting the deterministic half now is a strict improvement, and
  the timing probes keep their value as measurements rather than as gates.
- **Settings compatibility is asymmetric.** Reading an old file wrongly loses a user's preferences
  permanently; adding a new key later costs nothing. So compatibility is decided first and
  improvements are additive.
- **Both corrections in §5 are the same class of error** as the count: a claim that was copied forward
  instead of being measured. Each one now has a check rather than a sentence.

## Consequences

- **Ticket 03 is accepted against 35 verbs / 31 GUI rows / 4 CLI-only**, with the count asserted by a
  test that derives it from the table.
- **`knowledges.md`, `roadmap.md`, `spec.md` and ADR-0017's prose counts are stale.** They are corrected
  where they are load-bearing for an acceptance criterion (ticket 03), and where they are background
  they are annotated rather than silently rewritten, so the record of the error survives.
- **`scripts/` remains untouched.** No script changes to accommodate a registry row, and none is
  rewritten to make any rationale true.
- **A hosted CI gate is now an explicit, unfinished item** rather than an assumption. Until it lands,
  the recorded gate is the local clean-checkout contract.
- **Settings carry a documented WPF/Rust behavioural divergence** (default-vs-clamp), recorded on
  ticket 06 rather than resolved by preference.
- **`help()` becomes fully registry-generated.** Ticket 01 hard-coded the `demo-stream` argument list
  and a `Debugging:` header; ticket 03 generates help from the table, including per-tab grouping and
  the `[admin]` marker, so it cannot go stale.
- **Customization and About have no registry verbs.** They are hand-built surfaces (tickets 11), and
  the phrase "each verb grouped under exactly one of the eight tabs" is satisfied by the six tabs that
  carry verbs; the other two are not empty or missing.