# Ticket 12 — measure and publish the Rust dashboard deliverable.
#
# Measures the built binary (runtime-up latency, working set, size, hash),
# then copies it into releases\rust\ and prints the measurements as JSON.
# The hash pins live in tests\rust-release-pins.json — after a rebuild, run
# this script and update that file from its output.
#
# Why runtime-up and not window-ready: a GUI window started from a
# non-interactive context (this bridge) renders on another desktop, so the
# parent process's MainWindowHandle stays 0 even though the window exists —
# polling it would report a false 20 s. The first WebView2 child process is
# an honest, observable readiness signal instead (the runtime is up), and the
# window-latency number is measured on the desktop by hand.
#
# usage: pwsh -NoProfile -File tests\rust-release-measure.ps1

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repo 'src\KomorebiDashboardRust\src-tauri\target\release\KomorebiDashboard.exe'
if (-not (Test-Path $src)) { throw "missing built binary: $src" }

# --- measure the built binary before publishing ---
$proc = Start-Process -FilePath $src -PassThru
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$runtimeUp = $false
while ($sw.ElapsedMilliseconds -lt 20000) {
    if ($proc.HasExited) { throw "the dashboard exited during startup" }
    $child = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($proc.Id)" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'msedgewebview2*' }
    if ($child) { $runtimeUp = $true; break }
    Start-Sleep -Milliseconds 20
}
$runtimeMs = $sw.ElapsedMilliseconds
if (-not $runtimeUp) { throw "no WebView2 runtime appeared within 20 s" }

# Idle memory: after the runtime is up, let the shell settle and read the set.
Start-Sleep -Seconds 3
$live = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if (-not $live) { throw "the dashboard exited before the memory sample" }
$ws = $live.WorkingSet64
$priv = $live.PrivateWorkingSet64

try { $live.CloseMainWindow() | Out-Null } catch {}
Start-Sleep -Milliseconds 500
if (-not $live.HasExited) { $live.Kill() | Out-Null }

$size = (Get-Item $src).Length
$sha = (Get-FileHash $src -Algorithm SHA256).Hash.ToLower()

# --- publish: releases\rust, via the destination object's own .Name ---
$dstDir = Join-Path $repo 'releases\rust'
New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
$dst = Join-Path $dstDir 'KomorebiDashboard.exe'
Copy-Item $src $dst -Force
$dstSha = (Get-FileHash $dst -Algorithm SHA256).Hash.ToLower()
$dstSize = (Get-Item $dst).Length

[pscustomobject]@{
    runtimeUpMs   = $runtimeMs
    workingSetMB  = [math]::Round($ws / 1MB, 1)
    privateMB     = [math]::Round($priv / 1MB, 1)
    sizeBytes     = $size
    sha256        = $sha
    dstSha256     = $dstSha
    dstSizeBytes  = $dstSize
    publishedSame = ($sha -eq $dstSha -and $size -eq $dstSize)
} | ConvertTo-Json -Compress
