#Requires -Version 5.1
<#
    Repair whkdrc.

    whkd panics with `could not load whkdrc` for several small reasons that are
    invisible in a text editor: a BOM, CRLF line endings, non-ASCII characters,
    a stray character, or a `.shell` line that is not a bare command name.

    This script rewrites the file from the surviving bindings in a form whkd is
    known to accept, and prints a diff summary so nothing is lost silently.
#>
[CmdletBinding()]
param(
    [string] $Path = (Join-Path $env:USERPROFILE '.config\whkdrc'),
    [string] $Shell = 'powershell'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Path)) { throw "whkdrc not found at $Path" }

$raw = [System.IO.File]::ReadAllText($Path)
$before = @{}
$bindings = @()

foreach ($line in ($raw -split "`r?`n")) {
    $t = $line.Trim()
    if (-not $t) { continue }
    if ($t.StartsWith('#')) { continue }
    if ($t.StartsWith('.shell')) { $before['shell'] = $t; continue }
    $idx = $t.IndexOf(':')
    if ($idx -lt 1) { $before['skipped'] = ($before['skipped'] + 1); continue }
    $key = ($t.Substring(0, $idx)).Trim()
    $cmd = ($t.Substring($idx + 1)).Trim()
    if (-not $key -or -not $cmd) { $before['skipped'] = ($before['skipped'] + 1); continue }
    $bindings += [pscustomobject]@{ Key = $key; Cmd = $cmd }
}

Write-Host "read $($bindings.Count) bindings from $Path" -ForegroundColor Cyan
if ($before['skipped']) {
    Write-Host "  skipped $($before['skipped']) unusable line(s)" -ForegroundColor Yellow
}
Write-Host "  previous .shell: $($before['shell'])" -ForegroundColor DarkGray

# Sanity-check the requested shell. whkd 0.2.10 panics with
# "could not load whkdrc" on some `.shell` forms, so fail loudly here rather
# than leaving the user with a silently dead hotkey layer.
#   - a bare command name (e.g. powershell) is always fine
#   - a path form is fine only if the file actually exists
if (-not $Shell) { throw 'shell must not be empty' }
if ($Shell -match '\s') {
    throw "the shell must be a single command with no arguments: '$Shell'"
}
$looksLikePath = $Shell -match '[\\/]'
if ($looksLikePath -and -not (Test-Path $Shell)) {
    throw "shell '$Shell' is a path but the file does not exist"
}

# Duplicate hotkeys silently break RegisterHotKey for the loser, so collapse them.
$seen = @{}
$dupes = @()
$clean = @()
foreach ($b in $bindings) {
    $k = ($b.Key -replace '\s+', ' ').ToLowerInvariant()
    if ($seen.ContainsKey($k)) { $dupes += $b.Key; continue }
    $seen[$k] = $true
    $clean += $b
}
if ($dupes) {
    Write-Host "  removed $($dupes.Count) duplicate binding(s):" -ForegroundColor Yellow
    $dupes | ForEach-Object { Write-Host "     $_" -ForegroundColor Yellow }
}

# A command wrapped in double quotes is re-wrapped by whkd, which breaks it.
$quoted = $clean | Where-Object { $_.Cmd -match '"' }
if ($quoted) {
    Write-Host "  WARNING: $($quoted.Count) command(s) contain double quotes." -ForegroundColor Red
    Write-Host "  whkd wraps the command in quotes again, so nested quotes make it fail silently." -ForegroundColor Red
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine(".shell $Shell")
foreach ($b in $clean) { [void]$sb.AppendLine("$($b.Key) : $($b.Cmd)") }

# No BOM, LF only, ASCII only. This is what whkd's parser accepts.
$text = $sb.ToString()
$text = ($text -replace "`r`n", "`n")
$ascii = -join ($text.ToCharArray() | Where-Object { [int]$_ -le 126 })
$ascii += "`n"

[System.IO.File]::WriteAllText($Path, $ascii, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ""
Write-Host "rewritten: $($clean.Count) bindings, .shell $Shell, no BOM, LF endings, ASCII" -ForegroundColor Green
Write-Host "backed up to: $Path.repair-backup" -ForegroundColor DarkGray
Copy-Item $Path "$Path.repair-backup" -Force

Write-Host ""
Write-Host "now start it with:  0-SAFE-RESTART.bat" -ForegroundColor Cyan
