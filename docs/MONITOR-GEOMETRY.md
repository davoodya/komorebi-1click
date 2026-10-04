# Monitor geometry — the false DEGRADED verdict

**Date:** 2026-10-04
**Affected:** `scripts/komorebi-service.ps1` (`Get-Health`, `Get-WindowsMonitor`,
`Show-Status`), `scripts/display-diag.ps1`
**Symptom:** `4-STATUS.bat` reported `VERDICT: DEGRADED (3 problem(s))` on a
machine where Komorebi, WHKD and every hotkey were working perfectly.

---

## The reference machine

Three displays, reported by Windows as:

| Windows name | Native pixels | Scale | Position (native) |
|---|---|---|---|
| `\\.\DISPLAY1` (Dell P27, primary) | 1920x1080 | 100% | (0, 0) |
| `\\.\DISPLAY2` (Dell P23, portrait) | 1920x1080 | 125% | (0, -1080) |
| `\\.\DISPLAY3` (Samsung LS27) | 1080x1920 | 100% | (1920, -853) |

`DISPLAY3` is the portrait monitor standing on the right of the primary;
`DISPLAY2` sits above the primary.

---

## The three defects

### 1. `right`/`bottom` in `komorebic state` are width/height, not the far edge

`komorebic state` serialises each monitor as:

```json
{ "left": 1920, "top": -853, "right": 1080, "bottom": 1920 }
```

Despite the field names, `right` and `bottom` carry the monitor's **width and
height**, not its far corner. `Get-Health` computed the size as
`right - left` / `bottom - top`, which only produces the right answer when the
monitor sits at the origin. On the reference machine:

| Monitor | `right - left` | `bottom - top` | Reality |
|---|---|---|---|
| DISPLAY1 | 1920 - 0 = 1920 | 1080 - 0 = 1080 | 1920x1080 ✓ |
| DISPLAY2 | 1920 - 0 = 1920 | 1080 - (-1080) = 2160 | 1920x1080 ✗ |
| DISPLAY3 | 1080 - 1920 = **-840** | 1920 - (-853) = 2773 | 1080x1920 ✗ |

The negative width tripped `BadMonitors` → **"monitor geometry is invalid"**.

### 2. WinForms reports logical, komorebi reports physical

`System.Windows.Forms.Screen.Bounds` returns **logical** (DPI-scaled) values.
The 125% `DISPLAY2` reports `864x1536` logical where komorebi reports the
physical `1920x1080`. `Get-Health` compared the two directly and therefore
fired `MonitorMismatch` on every scaled display, printed as **"komorebi
disagrees with Windows about monitor size"**.

### 3. The mismatch counter incremented the wrong variable

```powershell
if ($h.MonitorMismatch) {
    $p++           # ← typo: the verdict counter is $problems
```

A genuine mismatch counted towards nothing, so the verdict could say HEALTHY
while real problems existed — while defects 1 and 2, both false positives, were
the only things pushing it to DEGRADED.

---

## The fix

**1.** Read the fields as the sizes they are:

```powershell
$wd = [int]$sz.right      # width
$ht = [int]$sz.bottom     # height
```

**2.** Convert the Windows rect from logical to physical pixels before
comparing, using the **monitor's own** DPI (not the system DPI, which is wrong
in any per-monitor-DPI setup). A small P/Invoke helper resolves the monitor
from the logical rect, takes its DC and reads `LOGPIXELSX`:

```powershell
$scale = [KomorebiDpi]::ScaleOf($b.X, $b.Y, $b.Width, $b.Height)
Right  = [int][Math]::Round($b.X + $b.Width * $scale)
Bottom = [int][Math]::Round($b.Y + $b.Height * $scale)
```

The cache is rebuilt per session, so a display change still picks up fresh
geometry.

**3.** `$p++` → `$problems++`.

**4.** The misleading remediation text under the mismatch warning — it told the
user to re-apply native resolution in Windows Settings, advice for a problem
the script itself had invented — was replaced with a note to check DPI scaling
and run `6-DISPLAY-DIAG.bat`.

**5.** Unnamed workspaces were also counted as a problem (`$problems++`). This
config addresses workspaces **by index** (`focus-workspace 0/1/2` in whkdrc),
so empty names are the intended design. Demoted to an informational line that
does not affect the verdict.

Zero-size containers were demoted from `[PROBLEM]` to `[WARN]` for the same
reason: `komorebic state` reports a 0x0 rect for hidden and minimised windows
(Sticky Notes, Phone Link, Settings), which is normal, not a layout fault.

The same `right - left` misreading existed in `scripts/display-diag.ps1`, which
is the script the old error message pointed users at; fixed there too.

---

## Verification

`4-STATUS.bat` on the reference machine:

```
  monitors         : 3
  tiled windows    : 12
  VERDICT: HEALTHY
```

`BadMonitors = 0`, `MonitorMismatch = 0`, and the process/socket/whkd-pairing
lines are unchanged from before — nothing else in the report moved.

The geometry handling is also covered by `tests/ticket-monitor.tests.ps1`
(12 assertions, exit 0), which feeds synthetic state objects shaped exactly
like `komorebic state` through the shipped comparison code. It covers the
primary, the vertically-offset landscape monitor, the portrait monitor, a
genuinely broken zero-size monitor (still flagged), a real disagreement with
Windows (still flagged), and the 125% logical-to-physical conversion in both
dimensions.

---

## How to read monitor indices

Komorebi and Windows do not number the displays the same way. On the reference
machine `komorebic state` orders them `DISPLAY1, DISPLAY2, DISPLAY3` while
Windows' Display Settings list the portrait P23 as monitor 2 and the Samsung as
monitor 3. Hotkeys that address a monitor by index (`focus-monitor 1`) therefore
do not address the monitor Windows calls 1. This is expected — monitor indexing
is an enumeration artefact, not a config value — and is the reason the hotkeys
that address monitors by **name** are the reliable ones.
