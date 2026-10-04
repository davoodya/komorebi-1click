# toggle-transparency.ps1
# Toggles the ACTIVE (foreground) window between a given transparency and fully
# opaque.
#
#   powershell -ExecutionPolicy Bypass -File toggle-transparency.ps1
#   powershell -ExecutionPolicy Bypass -File toggle-transparency.ps1 -Percent 50
#
# -Percent (default 85) is how transparent the window becomes: 85 = 85%
# transparent (alpha 38/255 ~= 15% opacity), 0 = fully opaque. It reuses the
# existing SetLayeredWindowAttributes code path; only the target alpha changes.
[CmdletBinding()]
param(
    [ValidateRange(0, 100)]
    [int]$Percent = 85
)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinTransp {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int n, int v);
  [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr h, uint c, byte a, uint f);
  [DllImport("user32.dll")] public static extern bool GetLayeredWindowAttributes(IntPtr h, out uint c, out byte a, out uint f);
}
"@
$h = [WinTransp]::GetForegroundWindow()
if ($h -eq [IntPtr]::Zero) { exit }
$GWL_EXSTYLE  = -20
$WS_EX_LAYERED = 0x00080000
$LWA_ALPHA    = 2
$cur = [WinTransp]::GetWindowLong($h, $GWL_EXSTYLE)
if (($cur -band $WS_EX_LAYERED) -ne $WS_EX_LAYERED) {
  [WinTransp]::SetWindowLong($h, $GWL_EXSTYLE, $cur -bor $WS_EX_LAYERED) | Out-Null
}
$null = 0; $a = 0; $f = 0
[void][WinTransp]::GetLayeredWindowAttributes($h, [ref]$null, [ref]$a, [ref]$f)
# alpha for the requested transparency: 255 * (100 - Percent) / 100
$targetAlpha = [byte][Math]::Round(255 * (100 - $Percent) / 100)
# if currently transparent-ish -> restore; else apply the requested transparency
if ($a -gt 0 -and $a -lt 250) {
  [void][WinTransp]::SetLayeredWindowAttributes($h, 0, 255, $LWA_ALPHA)
} else {
  [void][WinTransp]::SetLayeredWindowAttributes($h, 0, $targetAlpha, $LWA_ALPHA)
}
