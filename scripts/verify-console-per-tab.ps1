# verify-console-per-tab.ps1
#
# Decisive per-tab check of the console pane.
#
# WHY A FRESH PROCESS PER TAB
#   WPF keeps a TabControl's previously-selected content realized for a while, so
#   a single run that walks several tabs can find the previous tab's console
#   element and report a console on a tab that has none. Starting the app once per
#   tab and selecting a single tab removes that cross-talk entirely: whatever is
#   in the tree was built by that one tab.
#
# Usage: pwsh -File verify-console-per-tab.ps1 -ExePath <path>

param([Parameter(Mandatory = $true)][string]$ExePath)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

function Test-Tab([string]$TabName, [string]$ExePath) {
    $proc = Start-Process $ExePath -PassThru
    try {
        Start-Sleep -Seconds 14

        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $pidCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc.Id)
        $win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $pidCond)
        if (-not $win) { return 'window not found' }

        $tabCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, $TabName)
        $tab = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $tabCond)
        if (-not $tab) { return 'tab not found' }

        $tab.GetCurrentPattern(
            [System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Seconds 2

        # The console header carries a Clear button; the pane itself is a
        # multi-line read-only Edit. Either one proves the pane is rendered.
        $clearCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, 'Clear')
        $clear = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $clearCond)

        $editCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Edit)
        $edits = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $editCond)

        $clearState = if ($clear) {
            "present/offscreen=$($clear.Current.IsOffscreen)"
        } else { 'absent' }

        return "Clear=$clearState  EditControls=$($edits.Count)"
    }
    finally {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}

# Expectation: the four tabs that RUN things keep the console; Customization and
# About do not. TabLayout's ShowConsole="False" on those two is the claim.
$expectations = [ordered]@{
    'Kill and Start'       = 'console'
    'Restart and Reloading'= 'console'
    'Settings'             = 'console'
    'Customization'        = 'none'
    'AutoHotkey Scripts'   = 'console'
    'Debugging'            = 'console'
    'Uninstall and Cleanup'= 'console'
    'About'                = 'none'
}

$fail = 0
foreach ($tab in $expectations.Keys) {
    $result = Test-Tab -TabName $tab -ExePath $ExePath
    $want = $expectations[$tab]
    $has = $result -match 'Clear=present/offscreen=False' -or $result -match 'EditControls=[1-9]'

    $ok = if ($want -eq 'console') { $has } else { -not $has }
    if (-not $ok) { $fail++ }

    '{0,-22} want={1,-8} {2}  {3}' -f $tab, $want, $(if ($ok) { 'PASS' } else { 'FAIL' }), $result
}

"`nfailures: $fail"
exit $fail