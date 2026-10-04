#Requires -Version 5.1
<#
.SYNOPSIS
    Ticket 12 runtime proof: theme repaint + elevation gate.

.DESCRIPTION
    The static suite (tests/ticket12-theme-elevation.tests.ps1) can only read the
    source. This one proves the two claims that actually matter, at runtime:

      1. Switching theme genuinely repaints. It resolves the REAL brush that
         WPF hands to the window background before and after a toggle and
         compares the colours. A variable that flips while the UI stays the same
         would pass a unit test and fail here.
      2. The elevation gate decides from the live token, per verb, and refuses
         admin verbs while the process is unelevated.

    Everything runs in a throwaway probe process against the dashboard assembly.
    It never touches komorebi, whkd or yasb: no Stop-Process, no taskkill, no
    script execution. Read-only with respect to the running system.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repo    = 'H:\Repo\komorebi-1click'
$projDir = Join-Path $repo 'src\KomorebiDashboard'
$probeDir = Join-Path $repo 'tests\.build\ticket12-probe'
# Resolved, not hardcoded: ticket 13's RuntimeIdentifier moves the build
# output into a win-x64\ subfolder. This suite THROWS when the EXE is
# absent, so the resolver matters more here than anywhere else.
. (Join-Path $PSScriptRoot 'dashboard-paths.ps1')
$exePath = Resolve-DashboardExe -Src $projDir
if (-not $exePath) { $exePath = Join-Path $projDir 'bin\Release\net8.0-windows\KomorebiDashboard.exe' }

$script:Pass = 0
$script:Fail = 0
function Ok($msg)   { $script:Pass++; Write-Host "  PASS  $msg" -ForegroundColor Green }
function No($msg)   { $script:Fail++; Write-Host "  FAIL  $msg" -ForegroundColor Red }
function Head($msg) { Write-Host ""; Write-Host "== $msg" -ForegroundColor Cyan }

if (-not (Test-Path $exePath)) { throw "dashboard not built: $exePath" }

# ---------------------------------------------------------------------------
Head 'Probe project builds against the real dashboard'
# ---------------------------------------------------------------------------

Remove-Item $probeDir -Recurse -Force -EA SilentlyContinue
New-Item $probeDir -ItemType Directory -Force | Out-Null

@'
using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using KomorebiDashboard.Services;

namespace Ticket12Probe
{
    /// <summary>
    /// Hosts its own WPF Application, drives the dashboard's REAL ThemeService
    /// and ElevationService, and reports what WPF actually resolved.
    ///
    /// It reads Application.Current.Resources rather than ThemeService's fields:
    /// the point is to observe the resolved brush, not the intent to change it.
    /// </summary>
    public static class Probe
    {
        [STAThread]
        public static int Main()
        {
            // The REAL App, not a bare Application. This mattered: a bare
            // `new Application()` skips App.xaml entirely, so no WPF-UI dictionary
            // was ever merged (MergedDictionaries.Count == 0) and every
            // TryFindResource returned NULL. The first run of this probe
            // "passed" the deterministic check only because NULL == NULL, and
            // failed the two repaint checks for that reason alone.
            //
            // InitializeComponent() is what loads App.xaml's merged
            // ThemesDictionary. OnStartup is deliberately NOT run: it would
            // show the real MainWindow, which is the app's own launch test.
            var app = new KomorebiDashboard.App { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            app.InitializeComponent();

            int rc;
            try
            {
                // Let WPF settle before resources are read.
                app.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);

                Elevation();
                Theme();
                Controls();

                rc = 0;
            }
            catch (Exception ex)
            {
                Console.WriteLine("FATAL|" + ex.GetType().Name + "|" + ex.Message.Replace('\n', ' '));
                rc = 1;
            }
            finally
            {
                app.Shutdown();
            }
            return rc;
        }

        // ---- elevation ----------------------------------------------------
        private static void Elevation()
        {
            Console.WriteLine("ELV|IsElevated|" + ElevationService.IsElevated);
            Console.WriteLine("ELV|ExitCode|" + ElevationService.InsufficientPrivilegeExitCode);

            foreach (var name in new[] { "kill-komorebi", "restart-yasb", "kill-whkd" })
            {
                var def = VerbRegistry.Find(name);
                if (def == null)
                {
                    Console.WriteLine("ELV|Verb|" + name + "|UNKNOWN_VERB");
                    continue;
                }
                Console.WriteLine(string.Format(
                    "ELV|Verb|{0}|needs={1}|can={2}",
                    name,
                    def.RequiresAdmin,
                    ElevationService.CanRun(def)));
            }

            var admin = VerbRegistry.Find("kill-komorebi");
            if (admin != null)
                Console.WriteLine("ELV|Refusal|" + Flatten(ElevationService.RefusalMessage(admin)));

            Console.WriteLine("ELV|AdminVerbs|" + string.Join(",", ElevationService.AdminVerbNames()));
        }


        // ---- do real controls get WPF-UI styling? --------------------------
        // The colour brushes resolving proves the PALETTE loaded, not that the
        // Button/TabControl templates came with it. App.xaml merges a single
        // ThemesDictionary rather than a separate Controls.xaml, so this is
        // what actually decides whether the UI looks Fluent or like stock WPF.
        private static void Controls()
        {
            var app = Application.Current;
            ThemeService.Apply(Wpf.Ui.Appearance.ApplicationTheme.Dark);

            int appKeys = 0;
            foreach (var _ in app.Resources.Keys) appKeys++;
            Console.WriteLine("CTL|AppKeyCount|" + appKeys);

            int mergedKeys = 0;
            foreach (var d in app.Resources.MergedDictionaries)
                foreach (var _ in d.Keys) mergedKeys++;
            Console.WriteLine("CTL|MergedKeyCount|" + mergedKeys);

            // Control-theme-only resources. These exist if the full Fluent
            // control theme merged, not merely a colour palette.
            var names = new List<string>();
            foreach (var d in app.Resources.MergedDictionaries)
                foreach (var k in d.Keys) names.Add(k.ToString());
            foreach (var n in names.Where(n => n.IndexOf("ccent", StringComparison.OrdinalIgnoreCase) >= 0)
                                    .OrderBy(n => n).Take(12))
                Console.WriteLine("CTL|AccentKey|" + n);

            foreach (var key in new[]
            {
                "ControlFillColorDefaultBrush",
                "ControlStrokeColorDefaultBrush",
                "SystemAccentColor",
                "LayerFillColorDefaultBrush",
            })
            {
                var v = app.TryFindResource(key);
                Console.WriteLine("CTL|Resource|" + key + "|" + (v == null ? "NULL" : Hex(v as Brush)));
            }
        }

        // ---- theme --------------------------------------------------------
        private static void Theme()
        {
            ThemeService.Apply(Wpf.Ui.Appearance.ApplicationTheme.Dark);
            var dark = Snapshot("DARK");

            ThemeService.Apply(Wpf.Ui.Appearance.ApplicationTheme.Light);
            var light = Snapshot("LIGHT");

            ThemeService.Apply(Wpf.Ui.Appearance.ApplicationTheme.Dark);
            var darkAgain = Snapshot("DARK_AGAIN");

            Console.WriteLine("THM|WindowBrushChanged|" + (dark.Background != light.Background));
            Console.WriteLine("THM|TextBrushChanged|" + (dark.Text != light.Text));
            Console.WriteLine("THM|RepaintDeterministic|" + (dark.Background == darkAgain.Background));
            Console.WriteLine("THM|DarkBackground|" + dark.Background);
            Console.WriteLine("THM|LightBackground|" + light.Background);
            Console.WriteLine("THM|DarkText|" + dark.Text);
            Console.WriteLine("THM|LightText|" + light.Text);
        }

        private static (string Background, string Text, string Merged) Snapshot(string label)
        {
            var app = Application.Current;
            var res = app.Resources;

            if (res.MergedDictionaries.Count == 0)
            {
                Console.WriteLine("THM|ERROR|App.xaml dictionaries were not merged - probe is not measuring the real app");
            }

            var bg  = app.TryFindResource("ApplicationBackgroundBrush") as Brush;
            var txt = app.TryFindResource("TextFillColorPrimaryBrush") as Brush
                   ?? app.TryFindResource("Foreground") as Brush;

            Console.WriteLine(string.Format(
                "THM|{0}|bg={1}|text={2}|merged={3}|theme={4}",
                label, Hex(bg), Hex(txt), res.MergedDictionaries.Count, ThemeService.CurrentTheme));

            return (Hex(bg), Hex(txt), res.MergedDictionaries.Count.ToString());
        }

        private static string Hex(Brush b) =>
            b is SolidColorBrush scb
                ? string.Format("{0:X2}{1:X2}{2:X2}", scb.Color.R, scb.Color.G, scb.Color.B)
                : (b == null ? "NULL" : b.GetType().Name);

        private static string Flatten(string s) =>
            s.Replace("\r", " ").Replace("\n", " ").Trim();
    }
}
'@ | Set-Content (Join-Path $probeDir 'Probe.cs') -Encoding UTF8

@"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <UseWPF>true</UseWPF>
    <Nullable>enable</Nullable>
    <AssemblyName>Ticket12Probe</AssemblyName>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
    <!--
      SelfContained + RuntimeIdentifier are NOT cosmetic here. Ticket 13 made the
      dashboard self-contained, and a self-contained exe cannot be referenced by
      a framework-dependent one:

        error NETSDK1151: The referenced project ... is a self-contained
        executable. A self-contained executable cannot be referenced by a
        non self-contained executable.

      So the probe must match, or it cannot build at all. This is the probe
      being forced to track a product decision - worth knowing, because it means
      the two projects are now coupled by the publish mode.
    -->
    <SelfContained>true</SelfContained>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="Probe.cs" />
    <ProjectReference Include="$projDir\KomorebiDashboard.csproj" />
  </ItemGroup>
</Project>
"@ | Set-Content (Join-Path $probeDir 'Probe.csproj') -Encoding UTF8

Push-Location $probeDir
$buildOut = & dotnet build -c Release --nologo -v minimal 2>&1
$buildExit = $LASTEXITCODE
Pop-Location

if ($buildExit -ne 0) {
    No 'probe builds'
    $buildOut | Select-String -Pattern 'error' | Select-Object -First 8 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
    Write-Host "`nRESULT theme+elevation: $script:Pass passed, $script:Fail failed"
    exit 1
}
Ok 'probe builds against the real dashboard'

# Resolved by glob, not by a fixed path: the probe now carries
# RuntimeIdentifier=win-x64 (see the csproj note above), so its output lands in
# a win-x64\ subfolder exactly as the dashboard's does.
$probeExe = @(Get-ChildItem (Join-Path $probeDir 'bin\Release') -Recurse `
                            -Filter 'Ticket12Probe.exe' -File -EA SilentlyContinue)
$probeExe = if ($probeExe.Count -gt 0) { $probeExe[0].FullName } else { '' }
if (-not (Test-Path $probeExe)) { No "probe exe exists ($probeExe)" } else { Ok 'probe exe exists' }

Write-Host ''
Write-Host '  --- probe output ---'
$out = & $probeExe 2>&1
$out | ForEach-Object { Write-Host "    $_" }
$probeExit = $LASTEXITCODE
Write-Host ''

# ---------------------------------------------------------------------------
Head 'Elevation gate (live token, per verb)'
# ---------------------------------------------------------------------------

$kv = @{}
foreach ($line in $out) {
    $s = [string]$line
    if ($s -match '^ELV\|IsElevated\|(.+)$')                       { $kv.admin   = $Matches[1] }
    if ($s -match '^ELV\|ExitCode\|(.+)$')                        { $kv.exit    = $Matches[1] }
    if ($s -match '^ELV\|Verb\|(.+?)\|needs=(\w+)\|can=(\w+)$')   { $kv["v_$($Matches[1])"] = "needs=$($Matches[2]);can=$($Matches[3])" }
    if ($s -match '^ELV\|Refusal\|(.+)$')                        { $kv.msg     = $Matches[1] }
}

if ($kv.ContainsKey('admin')) {
    if ($kv.admin -eq 'False') { Ok 'unelevated token reports IsElevated=False' }
    else { No "expected an unelevated token; got IsElevated=$($kv.admin)" }
} else { No 'IsRunningAsAdmin was never reported' }

if ($kv.exit -eq '740') { Ok 'refusal exit code is 740 (Win32 ERROR_ELEVATION_REQUIRED)' }
else { No "expected refusal exit 740; got '$($kv.exit)'" }

if ($kv['v_kill-komorebi'] -eq 'needs=True;can=False') {
    Ok 'kill-komorebi needs admin and is REFUSED while unelevated'
} else { No "kill-komorebi: expected needs=True;can=False; got '$($kv['v_kill-komorebi'])'" }

if ($kv['v_kill-whkd'] -eq 'needs=True;can=False') {
    Ok 'kill-whkd needs admin and is REFUSED while unelevated'
} else { No "kill-whkd: expected needs=True;can=False; got '$($kv['v_kill-whkd'])'" }

if ($kv['v_restart-yasb'] -eq 'needs=False;can=True') {
    Ok 'restart-yasb needs no admin and is ALLOWED while unelevated'
} else { No "restart-yasb: expected needs=False;can=True; got '$($kv['v_restart-yasb'])'" }

if ($kv.msg -match 'kill-komorebi') {
    Ok 'refusal message names the verb that was refused'
} else { No 'refusal message does not name the verb' }

# ---------------------------------------------------------------------------
Head 'Theme repaint (resolved brushes, not intent)'
# ---------------------------------------------------------------------------

$th = @{}
foreach ($line in $out) {
    $s = [string]$line
    if ($s -match '^THM\|WindowBrushChanged\|(.+)$')   { $th.winChanged = $Matches[1] }
    if ($s -match '^THM\|TextBrushChanged\|(.+)$')     { $th.txtChanged = $Matches[1] }
    if ($s -match '^THM\|RepaintDeterministic\|(.+)$') { $th.deterministic = $Matches[1] }
    if ($s -match '^THM\|DarkBackground\|(.+)$')        { $th.darkBg = $Matches[1] }
    if ($s -match '^THM\|LightBackground\|(.+)$')       { $th.lightBg = $Matches[1] }
    if ($s -match '^THM\|DarkText\|(.+)$')              { $th.darkTx = $Matches[1] }
    if ($s -match '^THM\|LightText\|(.+)$')             { $th.lightTx = $Matches[1] }
}

$mergedLine = $out | Where-Object { [string]$_ -match '^THM\|\w+\|bg=' } | Select-Object -First 1
if ($out -match 'THM\|ERROR\|App\.xaml dictionaries were not merged') {
    No 'probe did not load App.xaml dictionaries — results would be meaningless'
} elseif ($mergedLine -and [string]$mergedLine -match 'merged=(\d+)') {
    $mc = [int]$Matches[1]
    if ($mc -ge 1) { Ok "App.xaml dictionaries merged (count=$mc)" }
    else { No "merged dictionary count is $mc - the WPF-UI theme never loaded" }
}

# Did the full Fluent CONTROL theme load, or only the colour palette?
$ctl = @{}
foreach ($line in $out) {
    $s = [string]$line
    if ($s -match '^CTL\|AppKeyCount\|(.+)$')    { $ctl.appKeys = $Matches[1] }
    if ($s -match '^CTL\|MergedKeyCount\|(.+)$') { $ctl.mergedKeys = $Matches[1] }
    if ($s -match '^CTL\|Resource\|(.+?)\|(.+)$') { $ctl[$Matches[1]] = $Matches[2] }
}

if ($ctl.mergedKeys -and [int]$ctl.mergedKeys -ge 100) {
    Ok "the Fluent control theme loaded ($($ctl.mergedKeys) merged keys), not just a colour palette"
} else {
    No "merged dictionary has only $($ctl.mergedKeys) keys - control templates are probably missing"
}

# Only keys verified to exist in WPF-UI 4.3.0. SystemAccentColor was an
# invented name and is asserted via the accent-key dump instead.
$ctlResources = @('ControlFillColorDefaultBrush', 'ControlStrokeColorDefaultBrush',
                  'LayerFillColorDefaultBrush')
$missing = $ctlResources | Where-Object { -not $ctl.ContainsKey($_) -or $ctl[$_] -eq 'NULL' }
if ($missing.Count -eq 0) {
    Ok 'control-theme resources resolve (buttons/tabs are Fluent-styled)'
} else {
    No "control-theme resources missing: $($missing -join ', ')"
}

if ($th.winChanged -eq 'True') {
    Ok "window background really repaints: dark=$($th.darkBg) light=$($th.lightBg)"
} else { No "window background did NOT change between themes (dark=$($th.darkBg) light=$($th.lightBg))" }

if ($th.txtChanged -eq 'True') {
    Ok "text foreground really repaints: dark=$($th.darkTx) light=$($th.lightTx)"
} else { No 'text foreground did NOT change between themes' }

if ($th.deterministic -eq 'True') {
    Ok 're-applying Dark returns the identical palette (no drift)'
} else { No 'palette drifted on re-apply — theme application is not idempotent' }

# Sanity: a dark theme must actually be darker than a light one. Catches a
# "changed" pair that merely swapped two brushes of the same brightness.
if ($th.darkBg -match '^[0-9A-F]{6}$' -and $th.lightBg -match '^[0-9A-F]{6}$') {
    $lum = { param($hex)
        $r=[Convert]::ToInt32($hex.Substring(0,2),16)
        $g=[Convert]::ToInt32($hex.Substring(2,2),16)
        $b=[Convert]::ToInt32($hex.Substring(4,2),16)
        0.2126*$r + 0.7152*$g + 0.0722*$b }
    $dl = & $lum $th.darkBg
    $ll = & $lum $th.lightBg
    if ($dl -lt $ll) { Ok ("Dark palette is genuinely darker ($([int]$dl) < $[int]$ll) luminance") }
    else { No "Dark palette is not darker than Light ($([int]$dl) vs $[int]$ll)) — themes are not what they claim" }
} else { No "background colours were not concrete hex values" }

if ($probeExit -eq 0) { Ok 'probe exited cleanly' } else { No "probe exited $probeExit" }

Write-Host ''
Write-Host "RESULT theme+elevation: $script:Pass passed, $script:Fail failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
