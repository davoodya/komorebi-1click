$ErrorActionPreference = 'Continue'
$kc = 'C:\Program Files\komorebi\bin\komorebic.exe'

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class FULLSCAN {
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
    public delegate bool EnumProc(IntPtr h, IntPtr p);
    public static uint Ex(IntPtr h) { return (uint)GetWindowLong(h, -20); }
    public static bool Layered(IntPtr h) { return (Ex(h) & 0x00080000) != 0; }
    public static bool Cloaked(IntPtr h) { int v; DwmGetWindowAttribute(h, 14, out v, 4); return v != 0; }
    public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
    public static string Txt(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
    public static int Pid(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return (int)p; }
    public static List<IntPtr> All() { var l=new List<IntPtr>(); EnumWindows((h,p)=>{ l.Add(h); return true; }, IntPtr.Zero); return l; }
}
"@

function Managed {
    $raw = & $kc state 2>$null | Out-String
    if (-not $raw) { return @() }
    try { $st = $raw | ConvertFrom-Json } catch { return @() }
    $o = @()
    foreach ($m in $st.monitors.elements) {
        foreach ($ws in $m.workspaces.elements) {
            foreach ($c in @($ws.containers.elements)) { foreach ($w in @($c.windows.elements)) { $o += [int64]$w.hwnd } }
            foreach ($fw in @($ws.floating_windows.elements)) { $o += [int64]$fw.hwnd }
        }
    }
    return $o
}

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " FULL SCAN: all visible windows with full details" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  hwnd        class               exstyle    LAYERED CLOAKED managed  title" -ForegroundColor Yellow
Write-Host "  ----------  ------------------  ---------  ------- ------- -------  -----"
$m = Managed
foreach ($h in [FULLSCAN]::All()) {
    if (-not [FULLSCAN]::IsWindowVisible($h)) { continue }
    $hh = [int64]$h
    $man = ($m -contains $hh)
    $t = [FULLSCAN]::Txt($h)
    if ($t.Length -gt 50) { $t = $t.Substring(0,50) }
    Write-Host ("  {0,-10}  {1,-18}  0x{2}  {3,-7} {4,-7} {5,-7}  {6}" -f $hh, [FULLSCAN]::Cls($h), [FULLSCAN]::Ex($h).ToString('X8'), [FULLSCAN]::Layered($h), [FULLSCAN]::Cloaked($h), $man, $t) -ForegroundColor $(if ($man) { 'Green' } else { 'Gray' })
}

Write-Host ""
Write-Host "=== windows with 'Copy' or 'Delete' or 'Move' or 'Progress' in title ===" -ForegroundColor Yellow
foreach ($h in [FULLSCAN]::All()) {
    if (-not [FULLSCAN]::IsWindowVisible($h)) { continue }
    $t = [FULLSCAN]::Txt($h)
    if ($t -match 'Copy|Delete|Move|Progress|Transfer|File|Explor') {
        $hh = [int64]$h
        $man = ($m -contains $hh)
        Write-Host ("  {0,-10}  {1,-18}  managed={2}  '{3}'" -f $hh, [FULLSCAN]::Cls($h), $man, $t) -ForegroundColor $(if ($man) { 'Green' } else { 'Red' })
    }
}
