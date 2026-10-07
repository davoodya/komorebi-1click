# verify-buttons.ps1
#
# Collects the button labels actually rendered on a tab, to prove that rows are
# named after their verb rather than all saying "Run".
#
# Reads the live window through UI Automation, so it reports what the user sees.
#
# Usage: pwsh -File verify-buttons.ps1 -ExePath <path> -Tab "<tab name>"

param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [string]$Tab = 'Settings'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$proc = Start-Process $ExePath -PassThru
Start-Sleep -Seconds 14

try {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $pidCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc.Id)
    $win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $pidCond)
    if (-not $win) { throw 'window not found' }

    $tabCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $Tab)
    $tabEl = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $tabCond)
    if (-not $tabEl) { throw "tab not found: $Tab" }
    $tabEl.GetCurrentPattern(
        [System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Start-Sleep -Seconds 2

    # Buttons, including ones inside the generated row template.
    $btnCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    $buttons = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)

    "buttons on the '$Tab' tab: $($buttons.Count)"
    foreach ($b in $buttons) {
        '  - ' + $b.Current.Name
    }

    $names = @()
    foreach ($b in $buttons) { $names += $b.Current.Name }

    "`nlabels that are exactly 'Run': $(($names | Where-Object { $_ -eq 'Run' }).Count)"
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}