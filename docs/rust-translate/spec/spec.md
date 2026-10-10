# Spec — komorebi-1click Admin Dashboard: Rust + Tauri v2 translation

**Feature slug:** `rust-translate` · **Status:** ready-for-agent · **Date:** 2026-10-08
**Author:** planning session (Daya) · **Implementation:** separate coding agent, ticket by ticket

**Governing ADRs:** ADR-0009 (script-first Dashboard), ADR-0012 (per-operation elevation),
ADR-0013 (CLI verb set), ADR-0015 (priority order), ADR-0016 (elevated window management).
**Prior planning docs:** `docs/rust-translate/{handoff,knowledges,bugs-fixing,codebase-inventory,environment,roadmap}.md`

---

## Problem Statement

The Admin Dashboard that ships today is a C# .NET 8 / WPF single-file executable. From the user's
point of view it works, but it costs too much for what it is:

- It is a **~170 MB download** to deliver a management surface over a set of PowerShell scripts, and
  it holds **60–120 MB of RAM** while idle.
- It takes roughly **half a second** before a window appears.
- Its Fluent look is built on XAML templates, where a styling mistake does not fail the build — it
  fails at first render. That already produced a defect where the app launched to a **completely
  blank/black window**, and the only diagnostic was a crash file with a line number.
- Producing a polished, animated, modern interface in XAML is slow and fragile, so visual quality
  stalls against the project's stated priorities.
- There is no fast inner loop for UI work: every styling change needs a full rebuild of a
  self-contained .NET binary.

The user wants the **same product** — every feature of the current Dashboard, plus faster and better
versions of them — without the size, memory, startup and rendering liabilities.

## Solution

Rebuild the Dashboard as a **Rust + Tauri v2** desktop application whose UI is a webview frontend
written in **Svelte 5 + TypeScript + Tailwind CSS + Lucide Icons**, with **hand-built components**
(no component library).

Behaviour is preserved exactly, because the product was never the UI layer:

- The **script-first invariant** (ADR-0009) holds: the application owns no system-management logic.
  Every action resolves a verb through the single registry table and runs one of the existing 62
  PowerShell scripts. **No script is modified.**
- The **same executable keeps two surfaces** (ADR-0013): arguments on the command line dispatch
  through the same registry and the same process runner the buttons use, so the GUI and the CLI twin
  cannot behave differently.
- **Per-operation elevation** (ADR-0012) is preserved: the app starts unelevated, gates administrative
  verbs before anything is launched, shows the three-button `Rerun as Administrator` dialog naming the
  specific features, relaunches elevated and exits the old instance; the CLI refuses loudly with
  exit code 740.

Deliverable: **a single EXE** placed in `H:\Repo\komorebi-1click\releases\rust\`, which when launched
opens a fast, modern, beautiful admin dashboard for the Komorebi / WHKD / YASB / AutoHotkey stack.

Expected gains, all re-measurable at the end: ~10–18 MB binary, ~30–45 MB RAM, lower startup than the
measured 553 ms, and a UI that is easier to make beautiful without spending performance.

## User Stories

### Startup, size and responsiveness

1. As a **Dashboard user**, I want the window to appear faster than the current 553 ms, so that
   launching the tool feels instant.
2. As a **Dashboard user**, I want the application to use well under the current 60–120 MB of RAM at
   idle, so that it does not compete with the window manager it manages.
3. As a **user downloading the Dashboard**, I want a single EXE of roughly 10–18 MB instead of 170 MB,
   so that obtaining and updating the tool is cheap.
4. As a **Dashboard user**, I want the first frame to already show my saved theme, accent, font and
   console settings, so that I never watch the app repaint from defaults.
5. As a **Dashboard user**, I want no operation to ever freeze the window, so that the interface keeps
   its zero-lag promise while scripts run.
6. As a **user on a machine with no .NET runtime**, I want the EXE to run with no runtime installation,
   so that the tool works on a clean Windows machine.

### Shell, navigation and layout

7. As a **Dashboard user**, I want the same eight tabs in the same order — Kill and Start, Restart and
   Reloading, Settings, Customization, AutoHotkey Scripts, Debugging, Uninstall and Cleanup, About —
   so that my muscle memory transfers from the current version.
8. As a **Dashboard user**, I want a header showing the product name, the component list and the build
   version, so that I always know which build I am running.
9. As a **Dashboard user**, I want a header button that toggles Dark/Light theme in one click and
   persists immediately, so that appearance changes are not lost on restart.
10. As a **Dashboard user**, I want a header button that steps through the accent palette and persists
    immediately, so that I can change the app's colour without opening Customization.
11. As a **Dashboard user**, I want every tab to use one shared row-and-console layout, so that all
    tabs look and behave like one product.
12. As a **Dashboard user**, I want the window to keep its 1180×760 default and 900×520 minimum, so
    that the layout I am used to is preserved.
13. As a **Dashboard user**, I want rounded window corners on Windows 11, so that the app matches the
    platform chrome.
14. As a **Dashboard user**, I want the window NOT to be tiled or pushed across monitors by komorebi,
    so that the dashboard stays where I put it on a multi-monitor desk.

### Verb rows and execution

15. As a **Dashboard user**, I want each tab to render its rows from the single registry table, so that
    a row cannot disagree with the CLI about what a verb does.
16. As a **Dashboard user**, I want a row to show its label, its one-line help and, where relevant, a
    READ-ONLY badge, so that I never mistake a diagnostic for an action.
17. As a **Dashboard user**, I want a row that takes a value to show an input box with a hint, so that
    I know what to type.
18. As a **Dashboard user**, I want a numeric row to accept digits only — including on paste and
    non-keyboard input — so that a transparency percentage cannot become garbage.
19. As a **Dashboard user**, I want each row's Run button to carry the verb's own action label
    (Kill, Start, Restart, Export, Repair…), so that the button says what it will do.
20. As a **Dashboard user**, I want rows to disable while a script is running, so that I cannot start
    two conflicting operations.
21. As a **Dashboard user**, I want the same user-typed value to be owned per row rather than shared,
    so that typing in one row never rewrites another.
22. As a **Dashboard user**, I want arguments passed to a script in the registry-declared order with
    fixed arguments first, so that scripts bind their parameters correctly.
23. As a **Dashboard user**, I want all 35 verbs reachable, including the ones that exist only for the
    CLI, so that nothing regresses against the current build.
24. As a **Dashboard user**, I want the Settings tab to group rows into Startup tasks, Configuration,
    Appearance, Dashboard preferences and Reset, so that I can find a control without scanning.
25. As a **Dashboard user**, I want the Uninstall tab to list the four scopes and both admin actions,
    so that I understand what will be removed before I act.
26. As a **Dashboard user**, I want the About tab to report identity, version, executable path, scripts
    path and settings path, so that I can tell which copy I launched.
27. As a **Dashboard user**, I want About's links and copy/open-folder actions to work, so that I can
    reach the repository and author from inside the app.

### Streaming console

28. As a **Dashboard user**, I want script output to stream live into a console pane while the script
    runs, so that I can see progress instead of a spinner.
29. As a **Dashboard user**, I want output delivered in ~50 ms batches rather than one update per line,
    so that a script printing 10,000 lines costs the UI the same handful of updates as 10.
30. As a **Dashboard user**, I want the console to auto-scroll only while I am at the end, so that
    reading history mid-run is not yanked back to the bottom.
31. As a **Dashboard user**, I want a drag grip to resize the console between 10 % and 60 % of the tab,
    with the new share applied to every tab and persisted, so that the layout does not jump when I
    switch tabs.
32. As a **Dashboard user**, I want the console capped at ~200,000 characters trimmed on a line
    boundary, so that a very long run cannot grow memory without limit.
33. As a **Dashboard user**, I want Clear available during a run and the status line to show percent
    and line count, so that I can manage the pane without stopping the work.
34. As a **Dashboard user**, I want the console font and size to be independent of the app font, so
    that script output stays monospaced and columns line up.
35. As a **Dashboard user**, I want stdout and stderr both preserved, so that a PowerShell warning on
    stderr does not hide the detail I need to diagnose a failure.

### Cancellation, timeout and errors

36. As a **Dashboard user**, I want a Cancel affordance for long operations, so that I can stop a
    script I no longer need.
37. As a **Dashboard user**, I want cancel and timeout each to kill the **entire process tree**, so
    that no grandchild keeps the pipe open and hangs the interface.
38. As a **Dashboard user**, I want a hung script to hit the 300 s default budget and report
    `TIMED OUT` rather than `FAILED`, so that the message names the real reason.
39. As a **Dashboard user**, I want a non-zero exit surfaced as a structured result — exit code,
    duration and raw output — never swallowed.
40. As a **Dashboard user**, I want a missing script reported as exit 127 with the offending path in
    the console, so that I can see where the app looked.
41. As a **Dashboard user**, I want the status line to distinguish succeeded, FAILED, cancelled and
    TIMED OUT with a duration, so that I know what happened at a glance.
42. As a **Dashboard user**, I want an unexpected error written to a log beside the executable and
    reported in a dialog, so that a crash is diagnosable rather than silent.

### Elevation

43. As a **user running unelevated**, I want non-administrative verbs to work normally, so that I am
    not forced to run the whole app as Administrator.
44. As a **user running unelevated**, I want an administrative verb to raise a dialog titled
    `Rerun as Administrator` with exactly the buttons OK / Rerun as Administrator / Cancel, so that the
    decision is mine in one click.
45. As a **user running unelevated**, I want that dialog to list the specific features that need
    Administrator — generated from the registry, not hardcoded — so that the message is always true.
46. As a **user who accepts elevation**, I want the app to relaunch elevated and the unelevated
    instance to exit, so that two instances never race over the same scheduled tasks.
47. As a **user who declines UAC**, I want that treated as a choice and not as an error, so that I am
    not shown a failure for declining.
48. As a **CLI user**, I want a verb needing elevation to print a clear refusal and exit **740** when
    I lack the privilege, so that the CLI never silently no-ops.
49. As a **CLI user**, I want the elevation gate checked **before** the script is launched, so that a
    refused destructive action never runs.

### CLI twin

50. As a **CLI user**, I want `--help` generated from the registry, so that documented verbs can never
    drift from real ones.
51. As a **CLI user**, I want the first argument treated as a verb and everything after it forwarded to
    the script untouched, so that the CLI stays a thin dispatch.
52. As a **CLI user**, I want `ahk enable <key>` / `ahk disable <key>` to fold onto their per-script
    rows, so that the two-part spelling keeps working.
53. As a **CLI user**, I want a bare verb that requires a value to print its help instead of running,
    so that I do not launch a script with a missing argument.
54. As a **CLI user**, I want the script's own exit code propagated, so that
    `dashboard status && dashboard restart-all` composes in a shell.
55. As a **CLI user**, I want Ctrl+C to cancel the child rather than orphan it, so that no script is
    left running after I interrupt.

### Appearance and customization

56. As a **Dashboard user**, I want Dark and Light themes to render correctly and switch at runtime,
    so that the app is comfortable in either environment.
57. As a **Dashboard user**, I want the same eight accent swatches (Blue, Indigo, Violet, Rose, Amber,
    Emerald, Teal, Slate) plus a custom HEX picker, so that my existing choice still exists.
58. As a **Dashboard user**, I want accent changes to apply to the selected tab, buttons, badges and
    header band, so that colour has a visible presence in the chrome.
59. As a **Dashboard user**, I want theme and accent to be applied before the first frame, so that I
    never see a default repaint.
60. As a **Dashboard user**, I want no Mica/Acrylic backdrop applied unconditionally, so that the
    blank-window defect cannot return on hardware where it fails.
61. As a **Dashboard user**, I want app font family and size previewed live and persisted on Apply
    Settings, so that I can see a typeface before committing to it.
62. As a **Dashboard user**, I want the font list to open with standard faces and offer a final
    `Custom (All Fonts)...` entry that enumerates installed fonts once, off the UI thread, so that
    opening the list never lags.
63. As a **Dashboard user**, I want a console font list restricted to monospaced faces with the same
    sentinel entry, so that a proportional face can never be chosen for output.
64. As a **Dashboard user**, I want UI scale at 100 % / 125 % / 150 % implemented as a CSS root scale
    and **verified at 125 % on the portrait monitor**, so that text and controls grow together instead
    of overflowing.
65. As a **Dashboard user**, I want a Factory Reset that previews defaults and requires confirmation,
    so that a destructive reset is never a single stray click.

### Settings, AutoHotkey and diagnostics

66. As a **Dashboard user**, I want settings stored as JSON in the app data directory with every field
    defaulted, so that a file written by an older build upgrades silently instead of producing zeros.
67. As a **Dashboard user**, I want values clamped on load and before save, so that no code path can
    persist something the UI cannot render.
68. As a **Dashboard user**, I want writes to be atomic (temp then rename), so that a crash mid-save
    cannot leave a truncated file.
69. As a **Dashboard user**, I want a corrupt settings file moved aside with a timestamp and reported,
    rather than overwritten, so that my previous preferences survive.
70. As a **Dashboard user**, I want an Open Folder action for the settings directory, so that I can
    inspect or back it up by hand.
71. As a **Dashboard user**, I want the AutoHotkey tab to show each shipped script's manifest metadata
    and its real on-disk state, so that the tab opens showing what is actually configured.
72. As a **Dashboard user**, I want AHK changes staged as a selection and committed by a serial Apply
    that stops at the first failure, so that three scripts cannot interleave writes to one generated
    file.
73. As a **Dashboard user**, I want AHK state re-read after a bulk verb completes, so that the radio
    pairs do not show a state the scripts have already left.
74. As a **Dashboard user**, I want the AHK diagnostics rows rendered from the registry, so that a new
    check appears by being added there and nowhere else.
75. As a **Dashboard user**, I want a Status verb that is strictly read-only, so that I can check
    health on a working installation without changing anything.

### Distribution and maintainability

76. As a **user installing the Dashboard**, I want exactly one EXE in `releases\rust\`, so that
    deployment is a copy with no installer step.
77. As a **user launching the Dashboard**, I want the app icon, window icon, favicon and About tab
    image all taken from the existing `logo.ico`, so that the product identity is unchanged.
78. As a **maintainer**, I want the executable to keep the name the ignore rule, shortcuts and docs
    already reference, so that no shipped script has to change.
79. As a **maintainer**, I want dependency versions pinned exactly rather than floating, so that a
    restore cannot change rendering with no code change.
80. As a **maintainer**, I want one registry table to remain the single source for GUI rows, CLI
    dispatch, `--help` and elevation messages, so that adding a verb stays a one-row change.
81. As a **maintainer**, I want the regression net translated rather than dropped, so that the
    contracts proven by the current test suites stay proven.
82. As a **maintainer**, I want every ticket to end in runtime evidence rather than a claim, so that
    "it builds" is never mistaken for "it works".
83. As a **maintainer**, I want all shipped text to remain English, so that the product language rule
    holds.
84. As a **Davood (project owner)**, I want speed and beauty pursued together in this version, with
    neither spent to buy the other, so that the stated priority order is honoured.

## Implementation Decisions

### Stack

| Layer | Decision |
|---|---|
| Shell | Rust + **Tauri v2** |
| Frontend | **Svelte 5** + TypeScript + Vite |
| Styling | **Tailwind CSS**, design tokens expressed as CSS custom properties |
| Icons | **Lucide Icons** |
| Components | **Hand-built** — no component library (full control of the Fluent-like look, no library weight) |
| Async runtime | `tokio` |
| Windows API | `windows-sys` / `windows` crate for token elevation and `ShellExecuteExW` |
| Dependencies | Pinned to exact versions, mirroring the existing csproj discipline |

### Behavioural contract

1. **Script-first (ADR-0009) is not relaxed.** The Rust core owns no system logic. 35 verbs resolve to
   the existing scripts. No `.ps1` file, installer step or config generator is modified.
2. **One registry table** feeds four consumers: GUI rows, CLI dispatch, `--help` output, and the
   elevation dialog's feature list. It is the only place a verb is defined.
3. **Dual entry point (ADR-0013).** Arguments present → headless CLI mode; no arguments → GUI. Exit
   codes: the script's own code, **740** for a missing elevation privilege, **2** for a parse error,
   **127** for a missing script.
4. **Argument rules preserved:** fixed registry arguments are appended before user arguments (PowerShell
   takes the last occurrence of a parameter); `ahk` two-part spelling folds onto its per-script rows;
   a bare verb whose declared shape requires a value prints help instead of running.
5. **Process engine:** off-thread async execution, both streams read concurrently, no blocking waits on
   the runtime. A run carries a cancellation token and a 300 s default budget; cancellation and
   timeout are recorded as **different facts** and reported differently. Either path kills the whole
   process tree.
6. **No-lag output:** lines accumulate in the backend and are emitted to the frontend in **~50 ms
   batches — one emit per window, never one per line**. The frontend appends the whole batch. Output
   is capped at ~200,000 characters, trimmed on a line boundary.

### IPC surface (API contract)

| Direction | Kind | Purpose | Payload essentials |
|---|---|---|---|
| FE → Rust | command | list the registry | all verb rows: verb, tab, label, help, arguments shape, requiresAdmin, isReadOnly, fixedArguments, hint, actionLabel, numericOnly, renderInGui |
| FE → Rust | command | run a verb | verb, extra argument list, per-row value already applied |
| Rust → FE | event | streamed output | batch of lines, run id |
| Rust → FE | event | run finished | exit code, duration ms, verb, cancelled flag, timed-out flag, summary text |
| FE → Rust | command | cancel run | run id |
| FE → Rust | command | settings get / save / reset | full settings document |
| FE → Rust | command | theme get / set / cycle | dark|light, scheme name, custom hex |
| FE → Rust | command | fonts list | tier (standard \| all), monospace-only flag |
| FE → Rust | command | elevation probe / relaunch | verb name; returns elevated flag, refusal message, admin feature list |
| FE → Rust | command | app info | product, version, executable path, scripts path, settings path, runtime description |
| FE → Rust | command | open path / url / copy | target, kind (folder \| url \| clipboard) |
| FE → Rust | command | AHK state read / apply | per-script pending states; returns applied states and stop-on-failure result |

Error contract: every command returns a typed success or a typed failure; a failure never throws
across the boundary and never leaves the UI without a status message.

### State and persistence

- **Settings document:** same fields and defaults as the current build (theme, colorScheme, fontSize,
  fontFamily, uiScale, consolePercent, accentColor, consoleFontFamily, consoleFontSize, plus the
  `Toggles` and `AhkScriptStates` maps). Defaults live on the type. Loads are normalized (theme/
  scheme/font defaults; fontSize 8–40, uiScale 50–300, consolePercent 10–60, consoleFontSize 8–32).
  Save is atomic; a corrupt file is quarantined with a timestamp and reported, never overwritten.
- **Single reactive store** in the frontend owns console share, theme, accent, busy state and per-tab
  output, replacing the current weak-reference broadcast: one console percentage, every tab reads it.
- **Preview now, persist on Apply** for typeface/size/scale; theme and accent from the header persist
  immediately (matching current behaviour).

### Visual system

- Theme and accent are CSS custom properties on the root; Dark/Light swaps the token set, accent
  rewrites the accent tokens (solid, 18 %, 10 %, 65 %, and a left-to-right header gradient).
- The visual system stays token-driven with **no literal colours in components** — the same rule the
  current stylesheet enforces.
- **No unconditional Mica/Acrylic/vibrancy.** The blank-window defect (D21) is the reason; any future
  backdrop must be conditional with a graceful fallback.
- UI scale is a **CSS root scale (rem/zoom)**, verified at **125 %** on the portrait monitor.

### Assets

All identity assets — application icon, window/taskbar icon, favicon and the About tab image — are
taken from the existing **`logo.ico`** resource in the WPF project's `Resources` folder. No new
artwork is introduced.

### Packaging

- Output is **one EXE**, copied to **`H:\Repo\komorebi-1click\releases\rust\`**. No MSI/NSIS bundler
  artefact is part of the deliverable.
- The executable keeps the name the ignore rule, shortcuts and documentation already reference, so
  that **no shipped script changes**.
- The build must run **on Windows** (MSVC toolchain + WebView2, both verified present); WSL drives it
  through the documented Windows-execution path. WSL `cargo` is only a fast inner loop for
  platform-independent modules.

### Feature parity

Every feature of the .NET 8 WPF build ships, plus faster/better implementations of them. Nothing is
dropped: all eight tabs, all 35 verbs, the CLI twin, elevation policy, theming, fonts, console
behaviour, AHK staging, About actions and crash logging all remain.

## Testing Decisions

### What makes a good test here

A good test asserts **externally observable behaviour only** — exit codes, emitted output, resulting
file state, IPC responses, and what the user can see on screen. It must not assert internal structure
(the presence of a private field, the name of a module, the shape of an internal buffer), because
those change freely during a rewrite while the contract does not. Where a current suite asserts
implementation detail, the translated test should re-express it as the behaviour that detail existed
to guarantee.

### Seams (proposed — confirm before ticket creation)

| Priority | Seam | What it proves | Why this seam |
|---|---|---|---|
| **Primary (the one)** | **Verb dispatch**: verb + arguments in → `ScriptResult` / exit code out | registry lookup, script resolution, argument ordering, process launch, streaming, cancel, timeout, tree kill, exit codes | It is the **highest** point both surfaces share: the CLI twin exercises the identical code path a GUI button does, headless, with no human clicking. One seam covers most of the contract. |
| Secondary | **Tauri IPC boundary**: command/event request-response | settings, theme, fonts, elevation gate, app info, error contract | Everything that is not "run a script" is observable here without a UI |
| Tertiary | **Rendered UI** | row shape, READ-ONLY badge, disabled-while-busy, input visibility, numeric filtering | Only needed where a visual rule has no backend equivalent |

### Modules covered

Registry completeness (every declared verb resolves to a real script) · argument splitting · scripts
directory locator · settings round-trip, clamping and quarantine · elevation gate **ordering** ·
help generation · batched output under a chatty script · cancel/timeout tree kill · AHK serial
apply with stop-on-failure · numeric value filtering.

### Prior art

- `tests/ticket10-dashboard-shell.tests.ps1` — 123 assertions; registry → runner → PowerShell →
  script proven end to end through the CLI twin.
- `tests/ticket11-threading.tests.ps1` — 67 assertions; off-thread execution, batching, cancel, tree
  kill, non-zero exit surfacing, measured startup.
- `tests/ticket12-theme-elevation.tests.ps1` — **asserts the elevation gate appears before the launch**
  (a gate after launch is worse than none); theme switch probes.
- `tests/ticket13-publish.tests.ps1`, `ticket13-runtime.tests.ps1` — publish flags and runtime.
- `tests/ticket15-shell-resources.tests.ps1` — shell/resource assertions.
- `tests/TESTING.md`, `tests/sandbox-*` — harness and clean-machine verification.

### Runtime evidence required (not config-text claims)

- `demo-stream` with a large line count: UI stays responsive, output batches, cancel kills the tree,
  a 3 s budget reports `TIMED OUT` not `FAILED`, no orphaned processes remain.
- CLI exercised for real: `--help` byte size + exit 0, and a read-only verb streaming live output.
- Startup time, binary size and idle RAM **measured** and reported against the targets.
- All eight tabs visually checked in the running EXE (Webview2 rendering differs from WPF).
- 125 % UI scale checked on the portrait monitor.

### Test execution policy (project rule)

Safe tests — those that touch no running component and change no configuration — run immediately when
their ticket completes. Tests that are destructive, or that need a VM/Sandbox, are collected in the
tests directory and run only after all tickets are implemented. No install test runs on the
production reference machine.

## Out of Scope

- **Any modification to the 62 PowerShell scripts**, the installer, config generation, or the AHK
  scripts. They are the contract, not the subject.
- **Removal or modification of the WPF application.** It keeps shipping; the Rust build lands beside
  it in `releases\rust\` until this spec's verification passes.
- **Renaming the shipped executable** — deliberately avoided so that `ignore-dashboard`, shortcuts and
  docs need no change.
- **Bundler installers** (MSI/NSIS) and any auto-update mechanism.
- **Cross-platform support.** Windows 11 x64 only.
- **Upgrading komorebi, WHKD, YASB or AutoHotkey**, or changing their configuration.
- **Changing the elevation policy** in ADR-0012, or the verb set in ADR-0013.
- **Mica / Acrylic / vibrancy window effects** (the D21 blank-window defect).
- **Localization.** Shipped text remains English.
- **Publishing these planning/spec documents to the public GitHub repo** as a deliverable of this
  stage — they live in the publish tree because that is where project docs live, but distribution is
  a separate decision.

## Further Notes

- **Decisions confirmed by Davood for this spec:** Svelte 5 + Tailwind CSS + Lucide Icons; Tailwind
  with hand-built components; a single EXE output written to `releases\rust\`; all identity assets
  taken from the existing `logo.ico`; UI scale as CSS rem/zoom verified at 125 %; elevation relaunch
  via `ShellExecuteExW`; and the standing priority that this version must be **fast first, beautiful
  and modern alongside** — never one at the cost of the other.
- **Adopted recommendations where no explicit answer was given** (flag here, correct if wrong):
  - *Test strategy* — hybrid: `cargo test` for platform-independent logic, runtime probes for
    streaming/elevation, and the CLI end-to-end path retained as the primary seam.
  - *Full-font enumeration* — port the tiered list including the `Custom (All Fonts)...` sentinel,
    because it is a visible, deliberately designed feature of the Customization tab.
  - *Document placement* — this stage's documents live on the publish side only; no mirrored copy in
    the dev tree.
- **Executable name kept as-is** (`KomorebiDashboard.exe`) so `ignore-dashboard.ps1`, shortcuts and
  documentation continue to work untouched. If a rename is ever wanted, it must be a single ticket
  that updates every reference in the same change.
- **Prerequisite before implementation:** no Tauri CLI exists on either the Windows or the WSL side
  yet. Installing it is the first action of the scaffold ticket.
- **Build runs on Windows**, not in WSL: the MSVC link step and WebView2 are Windows-only. WSL reaches
  Windows through the documented `win-exec.sh` path with the guard bypass granted for this project.
- **Seams are a proposal.** The primary seam is the verb-dispatch boundary reached through the CLI
  twin; if a different seam is preferred, say so before the tickets are written, because every test
  decision above hangs off it.
