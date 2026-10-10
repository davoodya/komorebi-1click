# Rust dashboard — tests, split for who runs them

Two lists, one boundary: **automatic tests never touch the live stack.** The production reference
machine's Komorebi / WHKD / YASB processes, configs and behaviour are never launched, restarted,
edited or killed by anything in the Automatic list — every automatic check is either pure logic
(Rust/frontend), static analysis, a read-only CLI verb, or a **refused** admin verb (the elevation
gate proves itself by refusing *before* anything can start). Everything that would change live state
runs **only inside Windows Sandbox** (`tests/sandbox-test-suite.ps1`, driven by
`docs/sandbox-test-harness.ps1`) or by Davood by hand.

The gate reason this split exists: ADR-0008 forbids install/uninstall/restart testing on the
production reference machine. The automatic list below was audited against it.

---

## Automatic tests — an AI agent may run these (no live-stack impact)

All commands run from WSL through `~/.hermes/scripts/win-exec.sh pwsh '<script>'`; logs land in
`tests/.build/*.log` so they are readable from the WSL side.

### A. Rust core logic — `cargo test` (30 tests)

```
Set-Location <repo>\src\Komorb…DashboardRust\src-tauri; cargo test
```

- Pure logic: registry, elevation gate, summary, batch/threading model, schema.
- The only shell-backed tests use `C:\…\repo-dir-that-does-not-exist` for `run_script`, so nothing
  executes; the one real test runs `status --timeout-seconds 5` (read-only).

### B. Frontend logic — `npm test` (78 tests) and typecheck

```
Set-Location <repo>\src\Komorb…DashboardRust; npm test
Set-Location <repo>\src\Komorb…DashboardRust; npx tsc -p tsconfig.json --noEmit
```

- vitest suites for theme/elevation/console/registry stores; tsc clean.

### C. Static PowerShell suites — no launch, no install, no process control

```
tests\ticket05-06-07.tests.ps1                  # AHK/VBS/registry contracts (91)
tests\ticket08-ahk.tests.ps1                    # AHK script syntax + registry contracts (26)
tests\t09-irm-e2e.tests.ps1                     # IRM geometry/summary shapes (7)
tests\ticket12-runtime.tests.ps1                # runtime guards
tests\ticket12-theme-elevation.tests.ps1        # theme + elevation contracts (48)
tests\ticket12-rust-elevation.tests.ps1         # elevation gate contracts, incl. review pins (28)
node tests\check-shipped-text.mjs               # shipped English/text policy (235 files)
```

> Counts are from the last actual run on 2026-10-10 (session 11):
> ticket08 26 · ticket09-irm 7 · ticket05-06-07 91 · ticket12-runtime 16 ·
> ticket12-theme-elevation 48 · ticket12-rust-elevation 28. Some suites above are
> owned by the concurrent installer track (`ticket10-dashboard-shell`,
> `ticket11-threading`, `ticket10-registry-parity`, `ticket09-exe-wrapper`) —
> run them as that track's green, do not edit them from here.

### D. Shipped-artifact checks — the gate makes these safe by construction

Run against `releases\rust\Komorb…Dashboard.exe`:

1. `--help` → exit 0, lists every verb, advertises `-BackupPath` (startup ledger: shipped text).
2. `status --timeout-seconds 5` → exit 0 (read-only verb).
3. `kill-all` **unelevated** → exit **740**, stderr names the admin features, **stdout empty**
   (nothing launched). This is ticket 12's end-to-end proof *through the shipped binary*, and it is
   safe on any machine because the gate refuses before any process action.
4. SHA256 of the published EXE equals the value recorded in the release pins
   (`tests/rust-release-pins.json` — the single source of truth; the EXE itself is
   deliberately untracked per `.gitignore`, and `tests/sandbox-test-suite.ps1`
   §T13 reads the same file).

### E. Static read-only komorebi check (allowed on the production machine)

- `komorebic check` — config validation only; it does not restart or reload anything.

---

## Manual tests — Davood runs these by hand

On the production machine (Davood's box) or a spare machine — never automated:

### Window and chrome
1. Launch `releases\rust\Komorb…Dashboard.exe` → the main window opens, WebView2 renders, all tabs
   are reachable.
2. 125% display scaling (and the portrait monitor) → text is legible, nothing clipped.

### Theme (ticket 12)
3. Click the header theme toggle → Light/Dark switches immediately, accent colour with it.
4. Relaunch the dashboard → the last choice persists.
5. Corrupt the stored value (localStorage) → the app falls back to Dark and does not crash.

### Elevation (ticket 12)
6. **Unelevated**: click an admin row → the dialog appears with the exact title
   `Rerun as Administrator`, the buttons `Rerun as Administrator` / `Cancel`, and the feature list
   generated from the registry (not a generic message).
7. **Accept**: click Rerun → the UAC prompt appears → after accepting, the elevated instance
   replaces the current one.
8. **Decline**: click Rerun → decline the UAC prompt → **no error state**, the window stays usable
   (ticket 05's contract: declined UAC returns cleanly).
9. **Elevated**: run an admin verb from the elevated dashboard → it runs and its output streams.

### Console / threading (ticket 11)
10. Run the chatty script (high line count) → the UI never freezes, output arrives in batches.
11. Start one verb while another is streaming → both continue independently; stopping one leaves
    the other running.

### Windows Sandbox only (via the harness — never on the production machine)
12. Clean install → dashboard + binaries verified (`tests\sandbox-test-suite.ps1`, sections
    T01–T13, incl. the §T13 published-EXE checks: existence, size, SHA256, no-.NET run, the 740
    gate).
13. Second install → idempotent; uninstall → clean.
14. Win11 pass first; the Win10 verification run is a Davood task (no Win10 machine in this lab).

---

## What the Sandbox suite already covers for the dashboard

| Section | Covers |
|---|---|
| T13.1 | published EXE exists; size + SHA256 read from `tests/rust-release-pins.json` (one source of truth) |
| T13.2 | runs with **no .NET runtime on PATH** in the Sandbox |
| T13.3 | admin verb unelevated → 740 + features named + nothing launched |

The GUI-launch, theme-toggle-click, and UAC accept/decline checks stay manual (ticket 14): the
harness runs the installer and the CLI surface, and Davood clicks the window.
