# ADR-0017 — Admin Dashboard rewritten in Rust + Tauri v2 with a Svelte 5 frontend

**Status:** Accepted · **Date:** 2026-10-08 · **Supersedes:** nothing · **Companion to:** ADR-0015
**Scope:** the Admin Dashboard surface only. ADR-0009 (script-first), ADR-0012 (elevation),
ADR-0013 (verb set) and ADR-0016 (elevated window management) are unchanged and still binding.

## Context

The Dashboard built under ADR-0015 — C# .NET 8, WPF, WPF-UI 4.3.0, single self-contained file — is
functionally complete and verified, but carries costs the project no longer wants to pay:

- **~170 MB** artefact and **60–120 MB** resident memory for an app whose entire job is dispatching
  verbs to PowerShell scripts.
- **~553 ms** measured time to a live window, dominated by CLR and WPF load.
- WPF-UI's native DWM backdrops produced the blank/black window defect (D21) on this hardware, and the
  fix was to switch backdrops off entirely — meaning the Fluent look was never fully delivered.
- XAML styling faults are deferred to first render, so they escape the compiler and only surface as a
  crash log; visual iteration requires rebuilding a self-contained binary.

Davood's priority order from ADR-0015 remains governing and unchanged:
**1) maximum speed · 2) lag approaching zero · 3) smoothness · 4) modern beautiful UI** — a lower
priority is never traded against a higher one. This ADR is an attempt to improve (1)–(3) *and* (4)
at once rather than trading between them.

## Decision

Rewrite the Dashboard as a **Rust + Tauri v2** application. Nothing about what the product does
changes; the shell does.

| Concern | Decision |
|---|---|
| Shell | Rust + Tauri v2 |
| Frontend | Svelte 5 + TypeScript + Vite |
| Styling | Tailwind CSS, tokens as CSS custom properties; **no literal colours in components** |
| Icons | Lucide Icons |
| Components | Hand-built — no component library |
| Async | `tokio` |
| Windows API | `windows-sys` / `windows` for token elevation and `ShellExecuteExW` with `runas` |
| UI scale | CSS root scale (rem/zoom), verified at 125 % on the portrait monitor |
| Identity assets | Existing `logo.ico` for app icon, window icon, favicon and the About image |
| Output | **One EXE** at `H:\Repo\komorebi-1click\releases\rust\`, executable name unchanged |
| Build host | Windows (MSVC + WebView2); WSL drives it through the Windows-execution path |
| Dependency versions | Pinned exactly, no floating ranges |

### What is preserved verbatim

1. **Script-first (ADR-0009):** the Rust core owns no system logic; 28 verbs dispatch to the same 62
   unchanged `.ps1` scripts.
2. **One registry table** feeding GUI rows, CLI dispatch, `--help` and the elevation dialog's feature
   list (ADR-0013 extension model).
3. **One executable, two surfaces (ADR-0013):** arguments → headless CLI, no arguments → GUI; exit
   codes 0 / script's own / **740** for missing elevation / **2** parse error / **127** missing script.
4. **Per-operation elevation (ADR-0012):** start unelevated; gate checked **before** launch; the
   three-button `Rerun as Administrator` dialog whose feature list is generated from the registry;
   relaunch elevated and exit the old instance; UAC decline is a choice, not a failure.
5. **The no-lag contract:** no blocking on the runtime; ~50 ms output batching with **one** emit per
   window rather than per line; cancellation and timeout recorded as different facts and each killing
   the whole process tree.
6. **Settings semantics:** defaults on the type, normalization on load and save, atomic write,
   corrupt-file quarantine instead of overwrite.
7. **English-only shipped text.** Every shipped string, comment and document is written in
   English — which is a statement about *language*, not about *character encoding*. Ordinary
   English typography is therefore permitted: em dashes, en dashes, curly quotes, ellipses
   and similar punctuation are English. What the rule forbids is text in another language —
   the one real violation in this project's history was a Chinese help string (defect D25).
   The strongest machine-checkable form of the rule is "no CJK, Hangul, Cyrillic, Arabic,
   Hebrew, Thai or Devanagari codepoints in shipped text (binary assets excluded)", because
   that catches a foreign-language string while leaving honest English punctuation alone.
   The original WPF dashboard that this work translates uses em dashes in its shipped UI and
   XAML as well, so ASCII-only text would be a parity regression, not an improvement.
   A check that flags every non-ASCII codepoint is a false positive: it fails on prose
   written by the very reviewers applying it.
8. **CLI-only build and publish** — no GUI IDE anywhere in the pipeline.

### What is replaced

WPF dispatchers, the weak-reference console-share broadcast, the visual-tree invalidation walk, the
`K1c*` brush publication, `LayoutTransform` scaling, XAML templates and converters, and the
self-contained .NET publish flag block. Their responsibilities move to: one frontend reactive store,
CSS custom properties, a CSS root scale, Svelte components, and a plain release build.

## Rationale

- **The heavy part was never the logic.** The app is a thin, well-partitioned shell over PowerShell.
  Its three tiers already map cleanly onto a Rust backend plus a webview frontend, which is why the
  translation can be behavioural rather than architectural.
- **Size and startup are structural, not tunable.** No combination of the .NET publish flags brings a
  170 MB self-contained binary down to the size a Tauri shell produces; the flags were already
  measured and documented as accepted costs in ADR-0015.
- **A webview frontend makes (4) cheaper without spending (1)–(3).** Tailwind and component-level
  styling remove the deferred-XAML-fault class entirely: the failure mode that produced D21 —
  compiles clean, renders black — is not expressible.
- **Rust's process control matches the contract we already promise.** Tree kill on cancel and timeout,
  concurrent stream draining and non-blocking waits are precisely the behaviours the WPF runner had to
  hand-roll and had to be tested into existence.
- **Tailwind with hand-built components** rather than a component library: the current design system is
  already owned by the app (21 self-owned resource keys, no literal colours). A library would import
  a second design language and a second set of theme assumptions.
- **Hand-built components over shadcn/Radix** keeps bundle weight and dependency surface down, which is
  the same reasoning that pinned WPF-UI exactly rather than accepting a floating range.

## Consequences

- **The PowerShell regression net must be translated or its loss accepted.** The current suites scan
  C# source for the contracts; they cannot scan Rust. The spec's test decisions choose a hybrid:
  `cargo test` for platform-independent logic, runtime probes for streaming and elevation, and the
  CLI twin retained as the primary test seam.
- **The build becomes Windows-hosted.** MSVC `link.exe` and WebView2 cannot run in WSL, so every build
  and every runtime verification happens on the Windows side, driven from WSL.
- **A new runtime dependency on WebView2** replaces the .NET dependency. WebView2 154.x is confirmed
  present on the target machine; clean-machine behaviour is a Sandbox verification item.
- **Tauri CLI must be installed** on the build host before the first ticket can produce an artefact.
- **The executable name stays unchanged** so that `ignore-dashboard`, shortcuts and documentation keep
  working. A rename becomes its own ticket that updates every reference in one change.
- **Two artefacts coexist during transition:** `releases\KomorebiDashboard.exe` (WPF, still shipping)
  and `releases\rust\` (Tauri). Replacement happens only after this ADR's verification passes.
- **Mica/Acrylic remains deliberately off.** Any future backdrop must be conditional with a graceful
  fallback, because D21 proved unconditional compositing is a launch-blocking risk on this hardware.
