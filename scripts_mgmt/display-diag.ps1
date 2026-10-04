# Compare what Windows reports against what komorebi computed, per display.
# Read-only. Use when 4-STATUS.bat shows a monitor with a negative width.
$ErrorActionPreference = 'Continue'

Add-Type -AssemblyName System.Windows.Forms

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Disp {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields;
        public int dmPositionX, dmPositionY;
        public int dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2;
        public int dmPanningWidth, dmPanningHeight;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
    public const int DM_POSITION = 0x00000020;
}
"@

Write-Host ""
Write-Host "=== Windows: EnumDisplaySettings (native pixels) ===" -ForegroundColor Cyan
for ($i = 1; $i -le 3; $i++) {
    $dev = "\\.\DISPLAY$i"
    $dm = New-Object Disp+DEVMODE
    $dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($dm)
    if ([Disp]::EnumDisplaySettings($dev, -1, [ref]$dm)) {
        $right  = $dm.dmPositionX + $dm.dmPelsWidth
        $bottom = $dm.dmPositionY + $dm.dmPelsHeight
        Write-Host ("  {0}  pels={1}x{2}  pos=({3},{4})  => right={5} bottom={6}" -f `
            $dev, $dm.dmPelsWidth, $dm.dmPelsHeight, $dm.dmPositionX, $dm.dmPositionY, $right, $bottom)
    } else {
        Write-Host ("  {0}  EnumDisplaySettings failed" -f $dev) -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Windows Forms (DPI-scaled logical) ===" -ForegroundColor Cyan
[System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
    $b = $_.Bounds
    Write-Host ("  {0}  x={1} y={2} w={3} h={4}  => right={5} bottom={6}" -f `
        $_.DeviceName, $b.X, $b.Y, $b.Width, $b.Height, ($b.X + $b.Width), ($b.Y + $b.Height))
}

Write-Host ""
Write-Host "=== komorebi ===" -ForegroundColor Cyan
try {
    $s = (& 'C:\Progra~1\komorebi\bin\komorebic.exe' state | Out-String) | ConvertFrom-Json
    foreach ($m in $s.monitors.elements) {
        $z  = $m.size
        $wd = [int]$z.right - [int]$z.left
        $ht = [int]$z.bottom - [int]$z.top
        $flag = if ($wd -le 0 -or $ht -le 0) { '   <<< INVALID' } else { '' }
        Write-Host ("  {0}  left={1} top={2} right={3} bottom={4}  => {5}x{6}{7}" -f `
            $m.name, $z.left, $z.top, $z.right, $z.bottom, $wd, $ht, $flag)
    }
} catch {
    Write-Host ("  could not read komorebi state: " + $_.Exception.Message) -ForegroundColor Red
}
