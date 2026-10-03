# Sensor temp -> colored HTML (icon + value change color together) for YASB custom widgets
# Usage: powershell -NoProfile -File sensor-color.ps1 -SensorId /intelcpu/0/temperature/0 -Type cpu
param(
    [Parameter(Mandatory=$true)][string]$SensorId,
    [Parameter(Mandatory=$true)][ValidateSet('cpu','gpu')][string]$Type
)
$ErrorActionPreference = 'SilentlyContinue'
$icon = @{ cpu = '&#xE86C;'; gpu = '&#xE9CA;' }[$Type]
try {
    $r = Invoke-WebRequest -Uri ("http://localhost:8085/Sensor?action=Get&id=" + $SensorId) -UseBasicParsing -TimeoutSec 4
    $j = $r.Content | ConvertFrom-Json
    $t = [math]::Round([double]$j.value)
} catch {
    $t = $null
}

if ($null -eq $t) {
    # sensor unavailable: neutral gray, keep icon visible
    Write-Output ("<span style=""color:#8a8a8a;font-family:'Segoe Fluent Icons'"">" + $icon + "</span> <span style=""color:#8a8a8a"">--&deg;C</span>")
    exit
}

if ($Type -eq 'cpu') {
    if ($t -gt 85)     { $c = '#ff6b6b' }   # pastel red
    elseif ($t -ge 70) { $c = '#f1fa8c' }   # yellow
    else               { $c = '#22d3ee' }   # cyan
} else { # gpu
    if ($t -gt 73)     { $c = '#ff6b6b' }   # pastel red
    elseif ($t -ge 65) { $c = '#f1fa8c' }   # yellow
    else               { $c = '#76b900' }   # NVIDIA green
}
Write-Output ("<span style=""color:$c;font-family:'Segoe Fluent Icons'"">" + $icon + "</span> <span style=""color:$c"">$t&deg;C</span>")
