# verify-features.ps1
#
# Runtime proof for the header buttons, the About tab's contents and the
# customization controls, driven through UI Automation against the real window.
#
# Why this exists: the previous pass shipped nothing the user could see because
# the source was never built into the delivered EXE. Reading the markup proves
# nothing; this asserts against the running binary.
#
# Usage: pwsh -File verify-features.ps1 -ExePath <path to KomorebiDashboard.exe>

param([Parameter(Mandatory = $true)][string]$ExePath)

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

    function Find-ByName([string]$name) {
        $c = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, $name)
        return $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c)
    }

    function Select-Tab([string]$name) {
        $t = Find-ByName $name
        if (-not $t) { throw "tab not found: $name" }
        $t.GetCurrentPattern(
            [System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 1500
    }

    function All-Names {
        $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        $out = @()
        foreach ($e in $all) {
            $n = $e.Current.Name
            if ($n) { $out += $n }
        }
        return $out
    }

    $fail = 0
    function Check([string]$label, [bool]$ok, [string]$detail = '') {
        if (-not $ok) { $script:fail++ }
        '{0,-44} {1}  {2}' -f $label, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail
    }

    # --- Header buttons: both the theme and the accent switch, side by side -----
    Check 'header has Toggle Theme' ([bool](Find-ByName 'Toggle Theme'))
    Check 'header has Toggle Color' ([bool](Find-ByName 'Toggle Color'))
    Check 'header has NO Factory Reset button' (-not [bool](Find-ByName 'Factory Reset'))

    # --- About tab ------------------------------------------------------------
    Select-Tab 'About'
    $about = All-Names

    Check 'About shows the product name'  ([bool]($about -match 'Komorebi')) 
    Check 'About shows the author'        ([bool]($about -match 'Davood'))
    Check 'About has Open GitHub button'  ([bool](Find-ByName 'Open GitHub'))
    Check 'About has Open Website button' ([bool](Find-ByName 'Open Website'))
    Check 'About has an executable row'   ([bool]($about -match 'Executable'))
    Check 'About has no Run button'       (-not [bool](Find-ByName 'Run'))

    # --- Customization: the console rows and the accent controls ---------------
    Select-Tab 'Customization'
    $cust = All-Names

    Check 'Customization has Custom Color'      ([bool](Find-ByName 'Custom Color'))
    Check 'Customization shows Console Font Family' ([bool]($cust -match 'Console Font Family'))
    Check 'Customization shows Console Font Size'   ([bool]($cust -match 'Console Font Size'))
    Check 'Customization shows Console pane height' ([bool]($cust -match 'Console pane height'))

    # --- Settings: the ignore row, and no console-height slider ---------------
    Select-Tab 'Settings'
    $set = All-Names

    Check 'Settings has the ignore row'      ([bool]($set -match 'Ignore KomorebiDashboard'))
    Check 'Settings has Factory Reset'       ([bool](Find-ByName 'Reset All Settings'))
    Check 'Settings has NO console height row' (-not [bool]($set -match 'Console pane height'))

    "`nfailures: $fail"
    exit $fail
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}