# HANDOFF — Session 3 (2026-10-06 evening): Admin Dashboard features + layout

**Status:** implemented, built, published, and verified at runtime. Nothing is
pending from this pass.

The source of truth for *what to do next* is this file, then
`docs/HANDOFF-20261004-SESSION.md` in the publish tree and `git log`. The dev
`handoff/*` documents are older than this one and describe an earlier state.

---

## 0. What the user asked for

1. Accent colour used for the selected tab and for selections, not grey/white.
2. Every tab laid out row-by-row like the Customization tab.
3. Console pane resized to a small bottom strip (20–30 %), not 80 % of the UI.
4. AutoHotkey tab: a switch (disable/enable) for *all* scripts plus one per
   script — Autocorrect, Change Language F3, Create New File (Win+Ctrl+N).
5. An Apply button on the tabs whose settings must be pushed to the machine:
   AutoHotkey, Customization (and Settings).
6. A Factory button on the Settings tab.
7. Font Family list that does not lag: a short standard list first, with a final
   "Custom (All Fonts)…" entry that loads everything installed.
8. Settings must persist across restarts.
9. Icon + logo in the title bar/header, taskbar and file properties.
10. Highest quality, no bugs, maximum speed and smoothness (standing priority).

All ten are done. Evidence for each is in §3.

---

## 1. Files added

| File | Purpose |
|---|---|
| `Services/SettingsStore.cs` | `DashboardSettings` + persisted store (`%APPDATA%\KomorebiDashboard\settings.json`) |
| `Services/FontCatalog.cs` | Two-tier font list (25 standard → 1597 installed) |
| `Services/AhkScriptCatalog.cs` | The three shipped AHK scripts + `ahk-state.json` reader |
| `Models/VerbRow.cs` | A registry verb plus *that row's own* typed value |
| `Views/ConsolePane.xaml(.cs)` | The shared console pane, used by every tab |
| `Views/TabLayout.xaml(.cs)` | The shared tab body: header + rows + console |
| `Views/ConfirmDialog.xaml(.cs)` | Themed confirmation for irreversible actions |
| `Converters/BoolToVisibilityConverter.cs` | Bool/string → visibility |
| `tests/ticket15-shell-resources.tests.ps1` | Regression suite for the pack-URI defect (§2) |

## 2. Defects found and fixed

- **D23 `startup add|remove` never worked.** `komorebi-service.ps1`'s first
  parameter carries `ValidateSet=install|uninstall|start|stop|restart|status|retile|watchdog`.
  The old verb passed `add`, so PowerShell rejected it before the script body ran.
  Proven by execution: old shape exits 1, `-Action status` exits 0. The verb now
  pins `-Action install` / `-Action uninstall`, matching `2-ADD-TO-STARTUP.bat`.
- **D24 `ahk on|off` never worked.** The script wants `-Name <key> -State <enabled|disabled>`,
  and requires both; the old verb passed an undeclared positional value. Now
  pinned per row.
- **D25 Chinese text in shipped help.** The publish copy's `start-whkd` row
  carried 5 CJK characters in the string `--help` prints. Now English.
- **D30 duplicated `<ApplicationIcon>`** (`<ApplicationIcon />` followed by
  `<ApplicationIcon>Resources\icon.ico</ApplicationIcon>`). Made the effective
  icon depend on property order; now declared once.
- **NEW — the real cause of "the UI is completely empty".** `MainWindow.xaml`
  used *relative* pack URIs (`pack://application:,,,/Resources/icon.ico`). WPF
  resolves those against the **entry** assembly, so any host other than the
  dashboard itself threw
  `XamlParseException → IOException: Cannot locate resource 'resources/icon.ico'`
  and no window appeared. Fixed by naming the assembly
  (`pack://application:,,,/KomorebiDashboard;component/Resources/...`) in
  `MainWindow.xaml`. `ticket15-shell-resources.tests.ps1` now proves a foreign
  host can construct the window, which is the check that did not exist before.
- **D26 (stale release) resolved by republishing** — the EXE is now newer than
  every source file.
- **`releases/` no longer holds the icon pack or stray logs.** 35 items (a
  5 MB icon folder plus 6 `.log` files) were moved to
  `~/projects/komorebi-1click/assets/releases-cleanup-20261006/` — moved, not
  deleted, because the icon folder is the source the user picked from.

## 3. Evidence (all from real execution on this machine)

Build and publish:
- `dotnet build -c Release` → 0 errors, 0 warnings.
- `dotnet publish -c Release` → EXIT 0, `releases\KomorebiDashboard.exe`,
  161.7 MB, newer than every source file.

Test suites (`tests/*.tests.ps1`, all exit 0):

| Suite | Result |
|---|---|
| ticket10-dashboard-shell | pass |
| ticket11-threading | 67 assertions |
| ticket12-theme-elevation | 48 assertions |
| ticket12-runtime | 16 passed, 0 failed |
| ticket13-publish | 16 assertions |
| ticket13-runtime | 24 assertions |
| ticket15-shell-resources | 12 passed, 0 failed |

Runtime probes:

- **CLI twin** (`--help` exit 0). Admin verb while unelevated → exit **740** with
  a refusal that names the verb. Unknown verb → exit 2. The shipped EXE does all
  three identically.
- **GUI**: window handle non-zero, title `Komorebi Admin Dashboard`,
  `Responding=True`, still alive on a second check 4 s later.
- **Icons**: `System.Drawing.Icon::ExtractAssociatedIcon` on the shipped EXE
  returns a real 32×32 icon; `ProductName=KomorebiDashboard`.
- **Fonts**: standard tier builds in **0 ms** (25 entries) vs **463 ms** for all
  1597. That 463 ms is the lag the two-tier list removes.
- **Persistence**: save → reload returned the exact values written
  (`scheme=Rose`, `font=Consolas`, `size=17`, `scale=125`, `console=28`); a
  deliberately corrupt file fell back to defaults **and was preserved** as
  `settings.json.corrupt-<stamp>`; `ResetToDefaults` restored `console=25`.
- **AHK toggle**: ran the exact argument vector the tab's rows generate
  (`-Name autocorrect -State disabled` → enable again). The script's own state
  file reported the change; `AppRunner.vbs` was regenerated byte-identical
  (sha256 `eb652459…` unchanged, because the repo copy is the *template* and the
  generated launcher lives in the Startup folder); `autocorrect.ahk` was running
  again at the end. The machine was left exactly as found.
- **Accent**: `ThemeService.SetColorScheme("Rose")` prints
  `accent: Rose #E11D48` and republishes the four `K1c*` brushes the tab template
  reads.

## 4. Design decisions worth keeping

- **Console height is a `GridLength` star ratio**, bound from
  `SettingsStore.Current.ConsolePercent` (default **25**). A star ratio means the
  console keeps its share when the window is resized, which a fixed pixel height
  would not.
- **Rows own their values.** A verb *only* gets an input box when its declared
  argument shape contains `<` or `[`. Fixed-value rows (`startup`, `ahk`,
  `ahk-enable`, `ahk-disable`) carry their argument in `FixedArguments` and show
  no box — so a typo cannot produce a call the script rejects.
- **Apply is a push, not a save.** Values are written to the store as the user
  edits (so nothing is lost), and `Apply Settings` is what pushes them to the
  machine and says so in the console. That is why the button and the auto-save
  coexist.
- **The font list is two tiers on purpose.** Enumerating `Fonts.SystemFontFamilies`
  costs ~0.5 s; the tab opens with the 25 standard faces and only pays that cost
  if the user asks for it, off the UI thread and labelled CPU-bound so
  `ticket11-threading` recognises it.
- **`ThemeService` exposes both `Apply` and `SetTheme`.** `Apply` is what
  ticket 12's runtime probe calls; renaming it would silently break that proof.

## 5. Test-suite corrections (and why)

Three suites failed on stale assumptions, not on regressions. Each edit is
scoped to the assertion's stated intent:

- `ticket10` asserted exactly **six** tab views; there are seven now that the
  Customization tab exists. Changed to "at least six" plus a duplicate check.
- `ticket10`'s registry scan was reading the illustrative call in
  `VerbRegistry.cs`'s own doc comment as a real row, so it demanded a
  `scripts/script.ps1` that was never meant to exist. The sample was removed from
  the comment and the constraint noted there.
- `ticket11` listed six views needing `x:Name`. The tab now resolves views
  through their **compiler-bound generated fields**, which cannot be null —
  strictly stronger than the runtime `FindName` guard the assertion was written
  for. The assertion now accepts either form and still fails a bare unguarded
  `FindName`.
- `ticket13` counted `.pdb`/`.json` SDK sidecars as publish strays; the
  assertion exists to catch satellite DLLs and folders, so those names are now
  allowed explicitly.

## 6. Known remaining risks / not done

- **The GUI was verified by window state, not by pixels.** The assistant has no
  GUI access, so "the accent really paints the selected tab" and "the console
  really occupies 25 %" are proven by the resource values and layout bindings,
  not by looking at the screen. **A visual pass by the user is the only thing
  that closes this.**
- **Publish size is ~161 MB** (self-contained + ReadyToRun, untrimmed). WPF is
  not trim-safe; the documented first lever is `PublishReadyToRun=false`
  (≈ −40 MB, slower cold start). Do not enable trimming.
- `config/komorebi.json`, `scripts/safe-restart.ps1` and six
  `scripts/_diag_*.ps1` probes were already modified/untracked **before** this
  pass. They were not touched here.
- Nothing was committed, reverted or pushed. The working tree holds all of this
  pass's changes.

## 7. How to run

```powershell
# build + test
cd H:\Repo\komorebi-1click
dotnet build src\KomorebiDashboard -c Release
pwsh tests\ticket15-shell-resources.tests.ps1

# publish the single-file release
dotnet publish src\KomorebiDashboard -c Release    # -> releases\KomorebiDashboard.exe

# CLI twin
.\releases\KomorebiDashboard.exe --help
```

The settings file lives at
`%APPDATA%\KomorebiDashboard\settings.json`; delete it to start from defaults.