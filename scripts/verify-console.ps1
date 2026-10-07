# verify-console.ps1
#
# Runtime proof for the Console pane behaviour, driven through UI Automation so
# it exercises the real window rather than reading the markup.
#
# Checks three claims:
#   1. The console pane occupies height in a tab that has one (Debugging).
#   2. It occupies NO height in Customization and About, which opt out.
#   3. Changing Console pane height in Customization actually moves the console
#      in another tab (the bug: the slider stored a value and nothing moved).
#
# Usage: pwsh -File verify-console.ps1 -ExePath <path to KomorebiDashboard.exe>

param(
    [Parameter(Mandatory = $true)][string]$ExePath
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

    function Select-Tab([string]$name) {
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, $name)
        $tab = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
        if (-not $tab) { throw "tab not found: $name" }
        $tab.GetCurrentPattern(
            [System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Start-Sleep -Milliseconds 1200
    }

    # The console's Clear button is inside the console header, so its presence is
    # a direct signal for "this tab renders the console pane".
    function Has-Console {
        $c = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, 'Clear')
        return [bool]($win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c))
    }

    # Top edge of the console's text area, in screen pixels. A taller console
    # starts higher up; a hidden console has no element at all.
    function ConsoleTop {
        $c = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, 'Clear')
        $b = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c)
        if (-not $b) { return $null }
        return [math]::Round($b.Current.BoundingRectangle.Top)
    }

    $results = [ordered]@{}

    Select-Tab 'Debugging'
    $results['Debugging has console']      = (Has-Console)
    $results['Debugging console top']      = (ConsoleTop)

    Select-Tab 'Customization'
    $results['Customization has console']  = (Has-Console)

    Select-Tab 'About'
    $results['About has console']          = (Has-Console)

    # The Customization sliders. Console pane height is the third one on the tab
    # (font size, scale, console height), so it is addressed through the row's
    # label rather than by index, which would break on any reordering.
    Select-Tab 'Customization'
    $sliderCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Slider)
    $sliders = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $sliderCond)
    $results['Customization slider count'] = $sliders.Count

    $ranges = @()
    foreach ($s in $sliders) {
        $rv = $s.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
        $ranges += [pscustomobject]@{
            name  = $s.Current.Name
            value = $rv.Current.Value
            min   = $rv.Current.Minimum
            max   = $rv.Current.Maximum
        }
    }
    $results['Customization sliders'] = ($ranges | ConvertTo-Json -Compress)

    # Drive the console-height slider (min 10, max 60) to both extremes and check
    # that another tab's console actually moves. This is the regression the user
    # reported: the value was stored, nothing on screen changed.
    $consoleSlider = $sliders | Where-Object {
        $v = $_.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
        $v.Current.Minimum -eq 10 -and $v.Current.Maximum -eq 60
    } | Select-Object -First 1

    if ($consoleSlider) {
        $rv = $consoleSlider.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)

        $rv.SetValue(10)
        Start-Sleep -Milliseconds 900
        Select-Tab 'Debugging'
        $low = ConsoleTop

        Select-Tab 'Customization'
        $rv.SetValue(60)
        Start-Sleep -Milliseconds 900
        Select-Tab 'Debugging'
        $high = ConsoleTop

        $results['console top at 10%'] = $low
        $results['console top at 60%'] = $high
        # A bigger share means the console starts higher, i.e. a SMALLER top.
        $results['height change moves console'] = ($null -ne $low -and $null -ne $high -and $high -lt $low)
    }
    else {
        $results['height change moves console'] = 'console slider not found'
    }

    $results.GetEnumerator() | ForEach-Object { '{0,-32} = {1}' -f $_.Key, $_.Value }
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}