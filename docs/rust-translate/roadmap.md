# komorebi-1click — Rust + Tauri Translation Roadmap

**Status:** planning complete, awaiting `spec.md` → `tickets/` → implementation by a coding agent.
**Division of labour:** this session (Daya) does **Plan + documents only**. Implementation is done by
a different model, ticket by ticket.

---

## 0. Objective

Translate the shipping **Admin Dashboard** — a C# .NET 8 / WPF / WPF-UI single-file EXE (~170 MB,
60–120 MB RAM) — into **Rust + Tauri v2** with a modern web frontend, without changing what the
program does.

Target gains, taken from `handoff.md` §1 and re-measurable at the end:

| Metric | Today (WPF) | Target (Tauri) |
|---|---:|---|
| Binary size | ~170 MB | ~10–18 MB |
| RAM | 60–120 MB | 30–45 MB |
| Startup | ~553 ms window-ready | measured, expected lower |
| UI styling | XAML + WPF-UI 4.3 | Tailwind / modern web, animations |

**Priorities, binding, in order (ADR-0015):** (1) maximum speed · (2) lag approaching zero ·
(3) smoothness · (4) modern beautiful UI — a lower priority is never traded against a higher one.

---

## 1. Invariants that constrain every ticket

1. **Script-first (ADR-0009):** the Rust core owns **no** system logic. 28 verbs → 62 existing
   `.ps1` scripts. No script is rewritten, no behaviour is reimplemented in Rust.
2. **One registry table** feeds the GUI rows, the CLI dispatch and the `--help` text
   (ADR-0013). Adding a verb = one row.
3. **Same executable, two surfaces (ADR-0013):** args present → headless CLI; no args → GUI.
   Exit codes preserved (script's own; **740** for missing elevation; **2** for parse error;
   **127** for a missing script).
4. **Per-operation elevation (ADR-0012):** start unelevated; three-button dialog with the title
   `Rerun as Administrator` naming the specific features; relaunch elevated and exit the old
   instance; CLI refuses loudly, never silently no-ops.
5. **The no-lag contract (ticket 11):** never block the runtime; 50 ms batched output flush —
   **one** event emit per window, never one per line; cancellation and timeout each kill the whole
   process tree and are reported as different facts.
6. **All shipped text is English.**
7. **Everything from the CLI** — no GUI IDE, no Visual Studio (VS exists only as the provider of
   `link.exe` for cargo).
8. **Verified, not assumed** — every claim in the tickets needs runtime evidence, not config text.

---

## 2. Proposed architecture (draft — to be fixed in `spec.md`)

```
┌─────────────────────────────────────────────────────────────┐
│ Frontend (Vite + TS) — 8 tabs, shared row/console layout    │
│  state: one reactive store (console %, theme, accent, busy) │
└──────────────────────────┬──────────────────────────────────┘
                           │ Tauri invoke() / emit()
┌──────────────────────────▼──────────────────────────────────┐
│ Rust core (tokio)                                           │
│  registry.rs · scripts.rs · settings.rs · elevation.rs      │
│  theme.rs · fonts.rs · ahk.rs · locate.rs · main.rs (CLI)   │
└──────────────────────────┬──────────────────────────────────┘
                           │ async process streaming
┌──────────────────────────▼──────────────────────────────────┐
│ scripts/*.ps1 (62) — UNCHANGED                              │
└─────────────────────────────────────────────────────────────┘
```

Module-by-module mapping is in `codebase-inventory.md` §2.

---

## 3. Phase plan

### Phase 1 — Specification (`spec.md`) · *this session, next step*
- IPC surface: every command, event and payload, spelled out (names, types, error shapes).
- Data models: `VerbDefinition`, `ScriptResult`, `DashboardSettings`, theme/accent state.
- Process engine contract: streaming, batching, cancel, timeout, tree-kill, exit codes.
- Elevation contract: probe, dialog, relaunch, CLI refusal.
- Tauri config: window (1180×760, min 900×520), single-instance, assets, icons, CSP, capabilities.
- Build pipeline: commands, target, artefact paths (`releases/rust/`).
- Test strategy: what replaces the PowerShell static-assertion suites.

### Phase 2 — Ticket breakdown (`tickets/`) · *this session*
Atomic, sequential, each with acceptance criteria + verification method. Proposed split:

| # | Ticket | Depends on |
|---|---|---|
| R01 | Tauri scaffold: project layout, Vite, `tauri.conf.json`, window + icons, build produces an exe in `releases/rust/` | — |
| R02 | Rust core: registry (28 verbs) + `locate.rs` + `ScriptResult`, unit tests against the real script files | R01 |
| R03 | Process engine: async streaming, 50 ms batch emit, cancel, timeout, tree-kill, exit codes | R02 |
| R04 | CLI twin: clap/parser from the same registry, `--help`, exit-code contract, Ctrl+C | R02 |
| R05 | Settings store: JSON, defaults, clamping, atomic save, quarantine, IPC | R01 |
| R06 | Elevation: token probe, dialog, relaunch, CLI gate **before** launch | R02 |
| R07 | Frontend shell: header, 8 tabs, shared row layout, console pane, theme/accent CSS variables | R01, R05 |
| R08 | Verb rows: registry-driven rendering, per-row value, numeric filter, read-only badge, Run/Cancel/Clear | R02, R07 |
| R09 | Tab-specific: Settings slices + Factory Reset, Customization preview/apply, AHK serial apply, About | R05, R08 |
| R10 | Theme/accent/fonts: 8 palettes + custom hex, dark/light, typography, UI scale, console font | R07 |
| R11 | Publish: release profile, icons, NSIS/MSIS + portable exe, size/startup measured | R01 |
| R12 | Verification harness: regression suite translated from `tests/ticket10–13` | all |

### Phase 3 — Implementation by the coding agent
Ticket-by-ticket, each ending with runtime evidence.

### Phase 4 — Verification & handover
- Side-by-side: old EXE vs new exe on the same verbs.
- Sandbox run (ticket 14 harness) — Windows 11 first.
- Measure size / RAM / startup against §0.
- `ignore-dashboard` rule repointed at the new binary name (see Open Question Q3).

---

## 4. Risk register (highest first)

| Risk | Why it matters | Mitigation |
|---|---|---|
| Loss of the PowerShell static-assertion net | `ticket10/11/12` suites scan C# source; they cannot scan Rust | Translate the load-bearing assertions in R12; record anything dropped |
| Elevation behaviour drift | ADR-0012 has hard UI requirements (title, 3 buttons, ordering) | Assert gate ordering in a test, as ticket 12 did |
| Process-tree orphaning | Grandchildren hold pipe handles → UI hangs on "cancel" | Job Object / `taskkill /F /T`; test with `demo-stream -Lines 100000` |
| Output flooding the webview | 10k lines → event-queue flood, the exact jank this rewrite must not introduce | Backend batching, one emit per 50 ms; test with `demo-stream` |
| Backdrop/vibrancy regression (D21) | Mica/Acrylic broke on this hardware | No unconditional vibrancy; conditional with fallback |
| Webview2-specific rendering differences | Not seen in WPF | Explicit visual check of all 8 tabs in Phase 4 |
| Build only works on Windows | WSL cargo cannot link Tauri/MSVC | `win-exec.sh` driving loop documented in `environment.md` §5 |
| `ignore-dashboard` / installer reference the EXE **by name** | A renamed exe stops being ignored by komorebi | Open Question Q3 — decide the binary name before R01 |

---

## 5. Open questions for Davood (answered before `spec.md` is written)

| # | Question | Recommendation |
|---|---|---|
| **Q1** | Frontend framework: **React + TS**, **Svelte 5**, **Vue**, or **vanilla TS**? | **Svelte 5** — smallest bundle and lowest runtime cost, which matches priority 1; React is the fallback if a broader ecosystem matters more |
| **Q2** | UI kit: Tailwind + hand-built Fluent-style components, or a component library (shadcn/ui,-radix)? | **Tailwind + hand-built components** — full control over the Fluent look, no library weight, matches the "own the visual system" approach of `App.xaml` |
| **Q3** | Binary name: keep `KomorebiDashboard.exe`, or move to `komorebi-dashboard.exe`? It is referenced by `ignore-dashboard.ps1`, shortcuts and docs. | **`komorebi-dashboard.exe`** (as `bugs-fixing.md` anticipates) — but it requires updating `ignore-dashboard.ps1` in the same ticket |
| **Q4** | Coexistence: does the Tauri build **replace** the WPF EXE in `releases/`, or ship **alongside** it during transition? | **Alongside** (`releases/rust/`) until Phase 4 passes, then replace |
| **Q5** | Test strategy: (a) translate the PowerShell static assertions to scan Rust, (b) `cargo test` + runtime probes only, or (c) hybrid? | **(c) hybrid** — `cargo test` for pure logic + runtime probes for streaming/elevation + keep the end-to-end CLI tests |
| **Q6** | Font catalog tier 2 (enumerate **all** installed fonts) needs a Windows font-enumeration crate. Port it, or drop the "Custom (All Fonts)…" sentinel and ship the standard list only? | **Port it** — it is a visible feature of the Customization tab; drop only if the crate cost is disproportionate |
| **Q7** | UI scale (100/125/150 %): the WPF version used a `LayoutTransform`. In a webview, use CSS `zoom`, a root `font-size`/`rem` scale, or rely on Webview2 DPI only? | **CSS root scale (`rem`/`zoom`)** — verify on the 125 % portrait monitor |
| **Q8** | Do the planning docs need a mirrored copy in the **dev** repo (`~/projects/…/docs/`), given publish docs ship to GitHub? | **No** — publish side only, matching the two-directory rule |

---

## 6. Definition of done

- [ ] All 8 tabs render and every one of the 28 verbs dispatches through the same registry.
- [ ] CLI twin: `--help` generated from the registry; exit codes 0 / script / 740 / 2 / 127 proven.
- [ ] `demo-stream` proves streaming with a responsive UI; cancel and timeout each kill the tree.
- [ ] Elevation dialog matches ADR-0012 exactly; gate ordering asserted by a test.
- [ ] Settings round-trip, quarantine and Factory Reset behave as the WPF build does.
- [ ] Theme/accent/typography/console settings all persist and apply **before** first paint.
- [ ] Size, RAM and startup measured against §0 and reported.
- [ ] No `.ps1` script was modified.
