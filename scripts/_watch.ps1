$ErrorActionPreference = 'Continue'
$kc = 'C:\Program Files\komorebi\bin\komorebic.exe'

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WATCH {
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

Write-Host "=== WATCH: poll every 2s for 30s, report NEW visible windows ===" -ForegroundColor Cyan
$seen = @{}
for ($i=0; $i -lt 15; $i++) {
    $m = Managed
    foreach ($h in [WATCH]::All()) {
        if (-not [WATCH]::IsWindowVisible($h)) { continue }
        $hh = [int64]$h
        if ($seen.ContainsKey($hh)) { continue }
        $seen[$hh] = $true
        $man = ($m -contains $hh)
        $t = [WATCH]::Txt($h)
        if ($t.Length -gt 45) { $t = $t.Substring(0,45) }
        Write-Host ("  [{0,2}s] NEW {1,-10} {2,-18} 0x{3} L={4} C={5} managed={6}  '{7}'" -f ($i*2), $hh, [WATCH]::Cls($h), [WATCH]::Ex($h).ToString('X8'), [WATCH]::Layered($h), [WATCH]::Cloaked($h), $man, $t) -ForegroundColor $(if ($man) { 'Green' } else { 'Yellow' })
    }
    Start-Sleep -Seconds 2
}
Write-Host "=== watch done ===" -ForegroundColor Cyan
