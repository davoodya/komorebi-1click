$ErrorActionPreference = 'Continue'

# Use Shell.FileOperation to trigger the native Windows copy progress dialog
$src = 'C:\Users\DavoodYa\AppData\Local\Temp\copysrc'
$dst = 'C:\Users\DavoodYa\AppData\Local\Temp\copydst2'
New-Item -ItemType Directory -Force -Path $dst | Out-Null

# Create large files if not exist
for ($i=1; $i -le 3; $i++) {
  $f = Join-Path $src ("file" + $i + ".bin")
  if (-not (Test-Path $f)) {
    $fs = [System.IO.File]::Create($f)
    $fs.SetLength(3GB)
    $fs.Close()
  }
}

Write-Host "starting Shell copy of 9GB (will show progress dialog)..."
$shell = New-Object -ComObject Shell.Application
$srcFolder = $shell.Namespace($src)
$dstFolder = $shell.Namespace($dst)
# CopyHere triggers the native progress dialog
$dstFolder.CopyHere($srcFolder.Items(), 16)  # 16 = no progress dialog flag? No, 0 = show dialog
Write-Host "copy initiated"
