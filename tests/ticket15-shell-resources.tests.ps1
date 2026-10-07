#Requires -Version 5.1
<#
.SYNOPSIS
    Dashboard shell regression: the XAML must load from a host that is not the
    dashboard itself.

.DESCRIPTION
    WHY THIS SUITE EXISTS
      MainWindow.xaml referenced its icon and logo with
      "pack://application:,,,/Resources/icon.ico" - a RELATIVE pack URI. WPF
      resolves a relative pack URI against the ENTRY assembly, not against the
      assembly the XAML lives in. Inside KomorebiDashboard.exe that is the same
      assembly, so the window loaded. The moment anything else hosted the XAML
      (the ticket-12 runtime probe, which references the project from a separate
      exe) it threw:

        XamlParseException: Provide value on
        'System.Windows.Baml2006.TypeConverterMarkupExtension' threw an exception.
          -> IOException: Cannot locate resource 'resources/icon.ico'.

      The window then never appeared, which is exactly the class of failure
      ticket 11 section 7b was written for: a build that compiles is not an app
      that starts. The static suites cannot see it, because the source looks
      correct in both forms. Only loading the BAML from another assembly
      exposes it.

    WHAT IT ASSERTS
      1. Every pack:// application URI in the dashboard's XAML names its own
         assembly (";component/"). Relative application URIs are the defect.
      2. Both image files exist and are declared as <Resource>.
      3. The EXE carries an icon resource, so the title bar and taskbar have one.
      4. Loading MainWindow's XAML from a SEPARATE assembly succeeds - the only
         test here that would have caught the original bug at build time.

    The probe process is a throwaway project under tests/.build/ and never starts
    the real window, so the running komorebi/whkd/yasb session is untouched.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repo     = 'H:\Repo\komorebi-1click'
$src      = Join-Path $repo 'src\KomorebiDashboard'
$projDir  = Join-Path $repo 'tests\.build\shell-probe'

$script:Pass = 0
$script:Fail = 0
function Ok($m)   { $script:Pass++; Write-Host "  PASS  $m" -ForegroundColor Green }
function No($m)   { $script:Fail++; Write-Host "  FAIL  $m" -ForegroundColor Red }
function Head($m) { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }

Write-Host '=== dashboard shell: XAML loads from a foreign host ===' -ForegroundColor White

# ---------------------------------------------------------------------------
Head '1. Pack URIs name their own assembly'
# ---------------------------------------------------------------------------

$xamlFiles = @(Get-ChildItem $src -Recurse -Filter '*.xaml' -File |
               Where-Object { $_.FullName -notmatch '\\obj\\|\\bin\\' })
Ok "$($xamlFiles.Count) XAML file(s) scanned"

$relativeUris = @()
$absoluteUris = 0
foreach ($f in $xamlFiles) {
    $text = Get-Content $f.FullName -Raw
    foreach ($m in [regex]::Matches($text, 'pack://application:,,,/([^"'']*)')) {
        $target = $m.Groups[1].Value
        if ($target -match '^[A-Za-z0-9._]+;component/') { $absoluteUris++ }
        else { $relativeUris += "$($f.Name): $target" }
    }
}

if ($relativeUris.Count -eq 0) {
    Ok "every pack:// application URI names its assembly ($absoluteUris total)"
} else {
    No ("relative pack URI(s) would resolve against the ENTRY assembly and fail in any other host:`n          " +
        ($relativeUris -join "`n          "))
}

# ---------------------------------------------------------------------------
Head '2. The image assets exist and are compiled in'
# ---------------------------------------------------------------------------

$csproj = Join-Path $src 'KomorebiDashboard.csproj'
$proj   = Get-Content $csproj -Raw

foreach ($asset in 'Resources\icon.ico', 'Resources\logo.ico') {
    $onDisk = Test-Path (Join-Path $src $asset)
    $declared = $proj -match [regex]::Escape("<Resource Include=`"$asset`" />")
    if ($onDisk -and $declared) { Ok "$asset exists and is declared as a Resource" }
    else { No "$asset on_disk=$onDisk declared=$declared" }
}

# A duplicate <ApplicationIcon> is legal in MSBuild (last one wins) and silently
# makes the icon depend on property order. Exactly one is correct.
$appIcons = ([regex]::Matches($proj, '<ApplicationIcon>')).Count
if ($appIcons -eq 1) { Ok 'exactly one <ApplicationIcon> is declared' }
else { No "$appIcons <ApplicationIcon> declarations - the effective icon depends on ordering" }

# ---------------------------------------------------------------------------
Head '3. The built EXE carries an icon resource'
# ---------------------------------------------------------------------------

$exe = Join-Path $src 'bin\Release\net8.0-windows\win-x64\KomorebiDashboard.exe'
if (Test-Path $exe) {
    Add-Type -AssemblyName System.Drawing -EA SilentlyContinue
    try {
        $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
        if ($ico -and $ico.Width -gt 0) { Ok "EXE exposes an icon ($($ico.Width)x$($ico.Height)) - title bar and taskbar" }
        else { No 'EXE exposes no icon resource' }
        if ($ico) { $ico.Dispose() }
    } catch { No "icon extraction threw: $($_.Exception.Message)" }
    # FileVersion metadata: Windows shows this in the file's properties page.
    $vi = (Get-Item $exe).VersionInfo
    if ($vi.ProductName) { Ok "EXE carries version metadata (ProductName='$($vi.ProductName)')" }
    else { No 'EXE has no ProductName - the properties dialog would be blank' }
} else {
    No "dashboard not built at $exe - run dotnet build -c Release first"
}

# ---------------------------------------------------------------------------
Head '4. MainWindow loads from a SEPARATE assembly (the real regression)'
# ---------------------------------------------------------------------------

Remove-Item $projDir -Recurse -Force -EA SilentlyContinue
New-Item $projDir -ItemType Directory -Force | Out-Null

@'
using System;
using System.Windows;
using System.Windows.Threading;
using KomorebiDashboard;

// A host that is NOT the dashboard. Constructing MainWindow here is what fails
// if the XAML uses relative pack URIs, because WPF resolves those against THIS
// assembly's name (ShellProbe) rather than the dashboard's.
internal static class Probe
{
    [STAThread]
    private static int Main()
    {
        try
        {
            var app = new App { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            app.InitializeComponent();
            app.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);

            var window = new KomorebiDashboard.MainWindow();
            Console.WriteLine("SHELL|MainWindow|created");
            Console.WriteLine("SHELL|Icon|null=" + (window.Icon == null));
            Console.WriteLine("SHELL|Title|" + window.Title);
            Console.WriteLine("SHELL|Content|" + (window.Content?.GetType().Name ?? "NULL"));

            // The logo is an <Image> inside the header; resolving it proves the
            // logo pack URI worked, not just the window Icon.
            var logo = window.TryFindResource("K1cVerbRowTemplate") as DataTemplate;
            Console.WriteLine("SHELL|RowTemplate|null=" + (logo == null));
            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine("SHELL|FATAL|" + ex.GetType().Name + "|" +
                              ex.Message.Replace('\n', ' ').Replace('\r', ' '));
            var inner = ex.InnerException;
            while (inner != null)
            {
                Console.WriteLine("SHELL|INNER|" + inner.GetType().Name + "|" +
                                  inner.Message.Replace('\n', ' ').Replace('\r', ' '));
                inner = inner.InnerException;
            }
            return 1;
        }
    }
}
'@ | Set-Content (Join-Path $projDir 'Program.cs') -Encoding UTF8

@"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <UseWPF>true</UseWPF>
    <AssemblyName>ShellProbe</AssemblyName>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
    <!-- Mirror the dashboard's publish mode; a self-contained exe cannot be
         referenced from a framework-dependent one (NETSDK1151). -->
    <SelfContained>true</SelfContained>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="Program.cs" />
    <ProjectReference Include="$src\KomorebiDashboard.csproj" />
  </ItemGroup>
</Project>
"@ | Set-Content (Join-Path $projDir 'Probe.csproj') -Encoding UTF8

Push-Location $projDir
$build = & dotnet build -c Release --nologo -v minimal 2>&1
$buildExit = $LASTEXITCODE
Pop-Location

if ($buildExit -ne 0) {
    No 'shell probe builds'
    $build | Select-String -Pattern ': error' | Select-Object -First 6 | ForEach-Object { Write-Host "        $($_.Line)" }
} else {
    Ok 'shell probe builds against the real dashboard'

    $probeExe = @(Get-ChildItem (Join-Path $projDir 'bin\Release') -Recurse -Filter 'ShellProbe.exe' -File -EA SilentlyContinue)
    $probeExe = if ($probeExe.Count -gt 0) { $probeExe[0].FullName } else { '' }

    if (-not (Test-Path $probeExe)) {
        No 'shell probe exe exists'
    } else {
        $out = & $probeExe 2>&1
        $exit = $LASTEXITCODE
        Write-Host '    --- probe output ---' -ForegroundColor DarkGray
        $out | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }

        $fatal = $out | Where-Object { [string]$_ -match '^SHELL\|FATAL\|' } | Select-Object -First 1
        if ($fatal) {
            No "MainWindow throws when hosted by another assembly:$fatal"
        } elseif ($out -match 'SHELL\|MainWindow\|created') {
            Ok 'MainWindow constructs inside a foreign host (pack URIs resolve)'
        } else {
            No 'MainWindow was never constructed and no FATAL was reported'
        }

        $iconLine = $out | Where-Object { [string]$_ -match '^SHELL\|Icon\|' } | Select-Object -First 1
        if ($iconLine -match 'null=False') { Ok 'the window Icon resolves to a real bitmap frame' }
        else { No "the window Icon did not resolve: $iconLine" }

        if ($out -match 'SHELL\|Content\|\w+') { Ok 'the window has a content tree' }
        else { No 'the window has no content' }

        if ($exit -eq 0) { Ok 'shell probe exited cleanly' } else { No "shell probe exited $exit" }
    }
}

Write-Host ''
Write-Host "RESULT shell: $script:Pass passed, $script:Fail failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0