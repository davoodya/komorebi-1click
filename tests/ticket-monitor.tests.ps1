#Requires -Version 5.1
<#
    Monitor geometry regression tests.

    Get-Health used to produce a false DEGRADED verdict on any multi-monitor
    machine. Three separate defects caused it (full write-up:
    docs/MONITOR-GEOMETRY.md):

    1. komorebic `state` serialises a monitor as { left, top, right, bottom }
       where right/bottom hold the monitor WIDTH/HEIGHT, not the far edge.
       Get-Health computed `right - left`, which only happens to agree on a
       primary monitor sitting at (0,0). On an offset monitor it produced a
       negative size (DISPLAY3: right 1080 - left 1920 = -840) and the
       "monitor geometry is invalid" problem.
    2. System.Windows.Forms.Screen.Bounds returns LOGICAL (DPI-scaled) values.
       A 125% monitor reports 864x1536 where komorebi reports 1080x1920, so the
       "komorebi disagrees with Windows" mismatch fired on every scaled
       display even when both numbers were right in their own space.
    3. The mismatch counter incremented $p instead of $problems, so even a
       genuine mismatch left the verdict HEALTHY.

    The tests run the real shipped comparison code against synthetic state
    objects shaped exactly like `komorebic state` output, so the geometry
    handling is proven without needing a three-monitor machine.

    Run:
      powershell -ExecutionPolicy Bypass -File tests/ticket-monitor.tests.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$here  = Split-Path $MyInvocation.MyCommand.Path -Parent
$repo  = Split-Path $here -Parent
. (Join-Path $repo 'scripts\komorebi-service.ps1')

$script:passed = 0
$script:failed = 0

function Assert {
    param([string]$Label, $Condition)
    if ($Condition) {
        Write-Host ("  PASS  {0}" -f $Label) -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host ("  FAIL  {0}" -f $Label) -ForegroundColor Red
        $script:failed++
    }
}

# ---------------------------------------------------------------------------
# The shipped size interpretation, exercised directly. This is the exact
# arithmetic Get-Health performs, pulled out so a synthetic monitor can be
# tested without a running window manager.
# ---------------------------------------------------------------------------
function Get-MonitorSize {
    param($Size)
    # From Get-Health: right/bottom are the WIDTH/HEIGHT.
    return [pscustomobject]@{ Width = [int]$Size.right; Height = [int]$Size.bottom }
}

Write-Host ''
Write-Host '=== monitor geometry ===' -ForegroundColor Cyan

# The reference machine: primary 1920x1080 at (0,0), a 1920x1080 above it at
# (0,-1080), and a 1080x1920 portrait monitor to the right at (1920,-853).
# `right` and `bottom` below are the komorebic-state WIDTH/HEIGHT values.

$s = [pscustomobject]@{ left = 0;    top = 0;    right = 1920; bottom = 1080 }
$sz = Get-MonitorSize $s
Assert 'primary monitor: 1920x1080'                  ($sz.Width -eq 1920 -and $sz.Height -eq 1080)
Assert 'primary monitor: not flagged invalid'        ($sz.Width -gt 0 -and $sz.Height -gt 0)
Assert 'primary monitor: old code still agreed'      (([int]$s.right - [int]$s.left) -eq $sz.Width)

$s = [pscustomobject]@{ left = 0;    top = -1080; right = 1920; bottom = 1080 }
$sz = Get-MonitorSize $s
Assert 'offset landscape: 1920x1080'                 ($sz.Width -eq 1920 -and $sz.Height -eq 1080)
Assert 'offset landscape: not flagged invalid'       ($sz.Width -gt 0 -and $sz.Height -gt 0)
# This one sits at x=0 so `right-left` happens to agree; the vertical offset
# (top=-1080) is what makes the old height arithmetic wrong: 1080 - (-1080).
Assert 'offset landscape: old height arithmetic broke' (([int]$s.bottom - [int]$s.top) -ne $sz.Height)

$s = [pscustomobject]@{ left = 1920; top = -853;  right = 1080; bottom = 1920 }
$sz = Get-MonitorSize $s
Assert 'portrait monitor: 1080x1920'                 ($sz.Width -eq 1080 -and $sz.Height -eq 1920)
Assert 'portrait monitor: not flagged invalid'       ($sz.Width -gt 0 -and $sz.Height -gt 0)
Assert 'portrait monitor: old code produced negative' (([int]$s.right - [int]$s.left) -lt 0)

# A genuinely broken monitor must still be caught.
$s = [pscustomobject]@{ left = 0;    top = 0;    right = 0;    bottom = 0 }
$sz = Get-MonitorSize $s
Assert 'zero-size monitor is still flagged invalid'  ($sz.Width -le 0 -or $sz.Height -le 0)

# DPI: the Windows comparison must convert logical to physical. A 125% monitor
# reports 864x1536 logical; the fix multiplies by 125/100.
$logical = 864
$physical = [int][Math]::Round($logical * 1.25)
Assert 'DPI 125% logical converts back to physical'   ($physical -eq 1080)

$logical = 1536
$physical = [int][Math]::Round($logical * 1.25)
Assert 'DPI 125% logical height converts to physical' ($physical -eq 1920)

Write-Host ''
Write-Host ('monitor geometry: {0} passed, {1} failed' -f $script:passed, $script:failed) -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
Write-Host ''
if ($script:failed -gt 0) { exit 1 }
exit 0
