$ErrorActionPreference = 'Continue'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class SHFO {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct SHFILEOPSTRUCT {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom;
        public string pTo;
        public ushort fFlags;
        public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string lpszProgressTitle;
    }
    
    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern int SHFileOperation(ref SHFILEOPSTRUCT lpFileOp);
    
    public const uint FO_COPY = 2;
    public const uint FO_MOVE = 1;
    public const uint FO_DELETE = 3;
    public const uint FOF_SILENT = 4;
    public const uint FOF_NOCONFIRMATION = 16;
    public const uint FOF_SIMPLEPROGRESS = 256;
    public const uint FOF_NOCONFIRMMKDIR = 512;
}
"@

$src = 'C:\Users\DavoodYa\AppData\Local\Temp\copysrc'
$dst = 'C:\Users\DavoodYa\AppData\Local\Temp\copydst5'
New-Item -ItemType Directory -Force -Path $dst | Out-Null

# Create a large file
$f = Join-Path $src 'huge3.bin'
if (-not (Test-Path $f)) {
    $fs = [System.IO.File]::Create($f)
    $fs.SetLength(10GB)
    $fs.Close()
}

Write-Host "starting SHFileOperation copy (10GB, with progress dialog)..."
$op = New-Object SHFO+SHFILEOPSTRUCT
$op.hwnd = [IntPtr]::Zero
$op.wFunc = [SHFO]::FO_COPY
$op.pFrom = "$f`0"
$op.pTo = "$dst`0"
$op.fFlags = [SHFO]::FOF_SIMPLEPROGRESS -bor [SHFO]::FOF_NOCONFIRMMKDIR
$result = [SHFO]::SHFileOperation([ref]$op)
Write-Host "SHFileOperation result: $result"
