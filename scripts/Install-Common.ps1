#Requires -Version 5.1
<#
.SYNOPSIS
    Shared library for the Komorebi-1click installer.
.DESCRIPTION
    Payload verification, state detection, silent installation and failure
    reporting for the five committed payloads.

    Design rules this file enforces (from the specification and the ADRs):
      * Offline first. Nothing here touches the network.
      * Verify before act. A payload whose SHA256 does not match is never installed.
      * Detect, then install. Every step is idempotent: when the product is
        already present at the expected version, the step is skipped.
      * Fail loudly and usefully. On any failure the user is told which step
        failed, the underlying error, and the concrete action to fix it.
      * No machine-specific constants. Everything is resolved at runtime.

    Failure reporting convention: every terminating error thrown here is wrapped
    by Install-Step or by the caller into a three-part message (step, cause,
    remedy). Use throw for the cause; never call exit from this file.
#>

# ===========================================================================
# Output helpers
# ===========================================================================

function Write-InstallerHeader {
    Write-Host ''
    Write-Host 'Komorebi-1click installer' -ForegroundColor Cyan
    Write-Host ('Repository root: {0}' -f $RepoRoot) -ForegroundColor DarkGray
    Write-Host ''
}

function Write-InstallerFooter {
    Write-Host ''
    Write-Host 'Installation complete.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Configuration generation, startup tasks and the AutoHotkey' -ForegroundColor DarkGray
    Write-Host 'startup launcher are set up by later tickets.' -ForegroundColor DarkGray
    Write-Host ''
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ('  {0}' -f $Message) -ForegroundColor White
}

function Write-StepDone {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ('    {0}' -f $Message) -ForegroundColor DarkGray
}

function Write-StepSkipped {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ('    {0}' -f $Message) -ForegroundColor DarkGray
}

# ===========================================================================
# Failure reporting
# ===========================================================================

<#
.SYNOPSIS
    Reports a failed installer step the way the specification requires:
    the failing step, the underlying cause, and the concrete remedy.
#>
function Report-InstallerFailure {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$Cause,
        [Parameter(Mandatory)][string]$Remedy
    )
    Write-Host ''
    Write-Host 'INSTALL STOPPED' -ForegroundColor Red
    Write-Host ('  Failing step: {0}' -f $Step) -ForegroundColor Red
    Write-Host ('  Cause:        {0}' -f $Cause) -ForegroundColor Red
    Write-Host ('  How to fix:   {0}' -f $Remedy) -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Nothing after this step was modified. Resolve the problem above' -ForegroundColor DarkGray
    Write-Host 'and run the installer again — completed steps will be skipped.' -ForegroundColor DarkGray
    Write-Host ''
}

# ===========================================================================
# Preconditions
# ===========================================================================

function Assert-ArchitectureSupported {
    $arch = $env:PROCESSOR_ARCHITECTURE
    if (-not $arch) { $arch = [System.IntPtr]::Size -eq 8 ? 'AMD64' : 'x86' }

    if ($arch -ieq 'ARM64') {
        Report-InstallerFailure `
            -Step   'Architecture check' `
            -Cause  "This machine reports architecture '$arch' (ARM64)." `
            -Remedy 'This installer ships x64-only binaries. Run it on an x64 Windows 10/11 machine.'
        throw 'Unsupported architecture: ARM64'
    }

    if ($arch -ine 'AMD64' -and $arch -ine 'x64') {
        Report-InstallerFailure `
            -Step   'Architecture check' `
            -Cause  "This machine reports architecture '$arch'." `
            -Remedy 'A 64-bit x64 Windows installation is required.'
        throw "Unsupported architecture: $arch"
    }

    Write-Step 'Architecture check: x64 confirmed.'
}

function Assert-RunningElevated {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]$identity

    if ($principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Step 'Running as Administrator.'
        return
    }

    Report-InstallerFailure `
        -Step   'Elevation check' `
        -Cause  'This installer is not running with administrator privileges, but the MSIs install into C:\Program Files.' `
        -Remedy 'Relaunch as administrator: right-click Install.ps1 (or Install.exe) and choose "Run as administrator", or run it from an elevated PowerShell window.'
    throw 'Installer is not elevated'
}

# ===========================================================================
# Payload manifest and integrity
# ===========================================================================

<#
.SYNOPSIS
    Reads binaries/payloads.sha256.json and indexes it by file name.
#>
function Get-PayloadManifest {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Report-InstallerFailure `
            -Step   'Load payload manifest' `
            -Cause  "The payload manifest is missing: $Path" `
            -Remedy 'Re-clone or re-extract this repository; binaries\payloads.sha256.json is part of it.'
        throw "Payload manifest missing: $Path"
    }

    try {
        $manifest = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Report-InstallerFailure `
            -Step   'Load payload manifest' `
            -Cause  $_.Exception.Message `
            -Remedy "Repair or re-extract 'binaries\payloads.sha256.json' from the repository."
        throw
    }

    $index = @{}
    foreach ($entry in $manifest.binaries) {
        $fileName = Split-Path -Leaf $entry.file
        $index[$fileName] = $entry
    }
    return $index
}

<#
.SYNOPSIS
    Verifies the SHA256 of every payload against the manifest, before any
    installation runs. A mismatch names the offending file and aborts.
#>
function Test-PayloadIntegrity {
    param(
        [Parameter(Mandatory)]$Payloads,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    Write-Step 'Verifying payload integrity...'

    $missing = @()
    $mismatched = @()

    foreach ($name in ($Payloads.Keys | Sort-Object)) {
        $entry = $Payloads[$name]
        $fullPath = Join-Path $RepoRoot $entry.file

        if (-not (Test-Path -LiteralPath $fullPath)) {
            $missing += $entry.file
            continue
        }

        $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
        if ($hash -ne $entry.sha256) {
            $mismatched += [pscustomobject]@{ File = $entry.file; Expected = $entry.sha256; Actual = $hash }
        }
    }

    if ($missing.Count -gt 0) {
        $list = ($missing -join "`n    ")
        Report-InstallerFailure `
            -Step   'Verify payload integrity' `
            -Cause  "The following payload file(s) are missing:`n    $list" `
            -Remedy 'Re-clone or re-extract this repository so binaries\ contains every committed payload.'
        throw 'Payload files are missing'
    }

    if ($mismatched.Count -gt 0) {
        $detail = foreach ($m in $mismatched) {
            "    $($m.File)`n      expected $($m.Expected)`n      found    $($m.Actual)"
        }
        Report-InstallerFailure `
            -Step   'Verify payload integrity' `
            -Cause  "SHA256 mismatch (file corrupted or replaced):`n$($detail -join "`n")" `
            -Remedy 'Re-extract the affected file(s) from the repository. Do not continue: installing a payload that fails integrity verification is unsafe.'
        throw 'Payload integrity verification failed'
    }

    Write-StepDone ('All {0} payloads verified.' -f $Payloads.Count)
}

# ===========================================================================
# State detection
# ===========================================================================

<#
.SYNOPSIS
    Returns the installed version of an MSI product, or $null when absent.
.DESCRIPTION
    Reads the per-user and per-machine ARP entries. Windows keeps a copy of the
    display version in the Uninstall registry hive, so this works even when the
    MSI service is busy and does not require msiexec to be invoked.
#>
function Get-InstalledMsiVersion {
    param([Parameter(Mandatory)][string]$ProductCode)

    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $registryPaths) {
        try {
            $entry = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -ieq $ProductCode }
            if ($entry -and $entry.DisplayVersion) {
                return [string]$entry.DisplayVersion
            }
        } catch {
            # Hive absent on this Windows build — try the next one.
        }
    }
    return $null
}

<#
.SYNOPSIS
    Compares two version strings, returning $true when they are equal.
.DESCRIPTION
    Handles 1.1.30.00 vs 1.1.30 and similar padding differences by comparing
    the numeric components, not the strings.
#>
function Test-VersionEqual {
    param(
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Actual
    )

    $a = ($Expected -split '\.' | ForEach-Object { [int]$_ })
    $b = ($Actual   -split '\.' | ForEach-Object { [int]$_ })
    for ($i = 0; $i -lt [Math]::Max($a.Count, $b.Count); $i++) {
        $va = if ($i -lt $a.Count) { $a[$i] } else { 0 }
        $vb = if ($i -lt $b.Count) { $b[$i] } else { 0 }
        if ($va -ne $vb) { return $false }
    }
    return $true
}

<#
.SYNOPSIS
    True when the AutoHotkey tree reports the expected version.
.DESCRIPTION
    AutoHotkey does not use an MSI product code. Its installer writes
    HKLM\SOFTWARE\AutoHotkey\InstallDir and the version lives in the ARP entry
    named 'AutoHotkey' that the setup writes itself.
#>
function Get-InstalledAhkVersion {
    # The v1 setup writes its version to HKLM\SOFTWARE\AutoHotkey\Version. That is
    # the canonical source, so read it first.
    $regKeys = @('HKLM:\SOFTWARE\AutoHotkey', 'HKLM:\SOFTWARE\WOW6432Node\AutoHotkey', 'HKCU:\SOFTWARE\AutoHotkey')
    foreach ($key in $regKeys) {
        try {
            $entry = Get-ItemProperty $key -ErrorAction SilentlyContinue
            if ($entry -and $entry.Version) { return [string]$entry.Version }
        } catch { }
    }

    # Fallback: the ARP entry. Note the v1 setup names it after the version
    # ("AutoHotkey 1.1.30.00"), so match on a prefix, not on an exact name.
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($path in $registryPaths) {
        try {
            $entry = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like 'AutoHotkey*' }
            if ($entry -and $entry.DisplayVersion) { return [string]$entry.DisplayVersion }
        } catch { }
    }
    return $null
}

function Test-AhkV1Installed {
    param([Parameter(Mandatory)][string]$ExpectedVersion)

    $exe = Join-Path $env:ProgramFiles 'AutoHotkey\AutoHotkey.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return $false }
    $installed = Get-InstalledAhkVersion
    if (-not $installed) { return $false }
    return Test-VersionEqual -Expected $ExpectedVersion -Actual $installed
}

function Test-AhkV2Installed {
    param([Parameter(Mandatory)][string]$ExpectedVersion)

    $exe = Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return $false }

    # The v2 interpreter reports its own version on its file metadata.
    $fileVersion = (Get-Item -LiteralPath $exe -ErrorAction SilentlyContinue).VersionInfo.FileVersion
    if ($fileVersion) {
        return Test-VersionEqual -Expected $ExpectedVersion -Actual $fileVersion
    }
    return $false
}

# ===========================================================================
# Installation primitives
# ===========================================================================

<#
.SYNOPSIS
    Installs an MSI payload silently, unless the expected version is present.
.DESCRIPTION
    Installs to the vendor-default C:\Program Files\ location. No directory is
    overridden: the MSI's own directory table decides, which matches the source
    machine exactly.
#>
function Install-MsiProduct {
    param(
        [Parameter(Mandatory)]$Payload,
        [Parameter(Mandatory)][string]$ProductCode,
        [Parameter(Mandatory)][string]$ExpectedVersion,
        [Parameter(Mandatory)][string]$DetectionProbe,
        [Parameter(Mandatory)][string]$DisplayName
    )

    $stepName = "Install $DisplayName"
    $payloadPath = Join-Path $RepoRoot $Payload.file

    # --- state detection ---------------------------------------------------
    $installed = Get-InstalledMsiVersion -ProductCode $ProductCode
    if ($installed) {
        if (Test-VersionEqual -Expected $ExpectedVersion -Actual $installed) {
            Write-StepSkipped ("$DisplayName {0} is already installed." -f $installed)
            return
        }
        Write-Step ("$DisplayName is installed as {0}, expected {1}. Upgrading." -f $installed, $ExpectedVersion)
    } else {
        Write-Step ("$DisplayName is not installed. Installing {0}..." -f $ExpectedVersion)
    }

    # --- install -----------------------------------------------------------
    try {
        # REBOOT=Suppress: the components never need a reboot, and a suppressed
        # reboot keeps the install atomic from this script's point of view.
        $exitCode = Start-Process -FilePath 'msiexec.exe' `
            -ArgumentList @('/i', "`"$payloadPath`"", '/quiet', '/norestart', 'REBOOT=Suppress') `
            -Wait -PassThru -NoNewWindow |
            Select-Object -ExpandProperty ExitCode
    } catch {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  $_.Exception.Message `
            -Remedy "Run the installer as administrator. If that is not the problem, install '$($Payload.file)' manually and re-run this script."
        throw
    }

    if ($exitCode -ne 0) {
        $meaning = switch ($exitCode) {
            1602 { 'The user cancelled the installation.' }
            1603 { 'A fatal error occurred during installation. Usually the installer is not elevated, or another MSI install is already running.' }
            1618 { 'Another installation is already running. Finish or cancel it first.' }
            1625 { 'This installation is forbidden by system policy.' }
            default { "msiexec exited with code $exitCode." }
        }
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  $meaning `
            -Remedy "Install '$($Payload.file)' manually to see the full error, fix the cause, then re-run this installer. Completed steps are skipped automatically."
        throw "MSI install failed with exit code $exitCode"
    }

    # --- verify the result -------------------------------------------------
    $nowInstalled = Get-InstalledMsiVersion -ProductCode $ProductCode
    if (-not $nowInstalled) {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  'msiexec reported success, but the product is not registered afterwards.' `
            -Remedy "Check that '$($Payload.file)' is a valid MSI for this Windows build, then re-run this installer."
        throw "$DisplayName did not register after a successful msiexec exit code"
    }

    if (-not (Test-Path -LiteralPath $DetectionProbe)) {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  "The product registered, but the expected file is not present: $DetectionProbe" `
            -Remedy "An antivirus or a group policy may have removed the installed files. Check $DetectionProbe, then re-run this installer."
        throw "$DisplayName registered but its expected file is missing"
    }

    Write-StepDone ("$DisplayName {0} installed." -f $nowInstalled)
}

<#
.SYNOPSIS
    Installs AutoHotkey v1 silently.
.DESCRIPTION
    The v1 setup accepts /S for a silent install (its Installer.ahk parses /S
    into SilentMode). It installs to $env:ProgramFiles\AutoHotkey and creates
    the AutoHotkey ARP entry used for state detection.
#>
function Install-AutoHotkeyV1 {
    param([Parameter(Mandatory)]$Payload)

    $stepName = 'Install AutoHotkey v1'
    $payloadPath = Join-Path $RepoRoot $Payload.file
    $expected = $Payload.version

    if (Test-AhkV1Installed -ExpectedVersion $expected) {
        Write-StepSkipped ("AutoHotkey v1 {0} is already installed." -f $expected)
        return
    }

    $already = Get-InstalledAhkVersion
    if ($already) {
        Write-Step ("AutoHotkey is installed as {0}, expected v1 {1}. Upgrading." -f $already, $expected)
    } else {
        Write-Step ("AutoHotkey v1 {0} is not installed. Installing..." -f $expected)
    }

    try {
        $process = Start-Process -FilePath $payloadPath -ArgumentList '/S' -Wait -PassThru
        $exitCode = $process.ExitCode
    } catch {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  $_.Exception.Message `
            -Remedy "Run the installer as administrator. If that is not the problem, run '$($Payload.file) /S' manually and re-run this script."
        throw
    }

    if ($exitCode -ne 0) {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  "The AutoHotkey setup exited with code $exitCode." `
            -Remedy "Run '$($Payload.file)' manually to see its error, fix the cause, then re-run this installer."
        throw "AutoHotkey v1 setup failed with exit code $exitCode"
    }

    $exe = Join-Path $env:ProgramFiles 'AutoHotkey\AutoHotkey.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  "The setup reported success, but $exe is not present." `
            -Remedy "An antivirus may have quarantined the install. Check $env:ProgramFiles\AutoHotkey, then re-run this installer."
        throw 'AutoHotkey v1 setup succeeded but AutoHotkey.exe is missing'
    }

    Write-StepDone ('AutoHotkey v1 installed.')
}

<#
.SYNOPSIS
    Installs AutoHotkey v2 silently into the existing v1 tree.
.DESCRIPTION
    The v2 setup accepts /silent (its UX\install.ahk parses /silent into
    inst.Silent). It unpacks into the v1 installation directory and creates the
    v2 subdirectory, so v1 must already be installed.
#>
function Install-AutoHotkeyV2 {
    param([Parameter(Mandatory)]$Payload)

    $stepName = 'Install AutoHotkey v2'
    $payloadPath = Join-Path $RepoRoot $Payload.file
    $expected = $Payload.version

    if (Test-AhkV2Installed -ExpectedVersion $expected) {
        Write-StepSkipped ("AutoHotkey v2 {0} is already installed." -f $expected)
        return
    }

    # v2 needs the v1 tree to exist; it installs into <v1 dir>\v2\.
    $v1Exe = Join-Path $env:ProgramFiles 'AutoHotkey\AutoHotkey.exe'
    if (-not (Test-Path -LiteralPath $v1Exe)) {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  "AutoHotkey v1 is not installed. The v2 setup installs into the v1 tree ($v1Exe\v2)." `
            -Remedy 'The v1 step runs before this one. If it was skipped as already-installed but the v1 tree is absent, install AutoHotkey v1 manually first.'
        throw 'AutoHotkey v1 is a prerequisite for the v2 setup'
    }

    Write-Step ("AutoHotkey v2 {0} is not installed. Installing..." -f $expected)

    try {
        $process = Start-Process -FilePath $payloadPath -ArgumentList '/silent' -Wait -PassThru
        $exitCode = $process.ExitCode
    } catch {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  $_.Exception.Message `
            -Remedy "Run '$($Payload.file) /silent' manually as administrator, then re-run this script."
        throw
    }

    if ($exitCode -ne 0) {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  "The AutoHotkey v2 setup exited with code $exitCode." `
            -Remedy "Run '$($Payload.file)' manually to see its error, fix the cause, then re-run this installer."
        throw "AutoHotkey v2 setup failed with exit code $exitCode"
    }

    $exe = Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  "The setup reported success, but $exe is not present." `
            -Remedy "Check $env:ProgramFiles\AutoHotkey\v2. If the directory is absent, an antivirus removed it; re-run this installer."
        throw 'AutoHotkey v2 setup succeeded but AutoHotkey64.exe is missing'
    }

    Write-StepDone ('AutoHotkey v2 installed.')
}

# ===========================================================================
# Per-product wrappers: keep the expected versions in one place each.
# ===========================================================================

function Install-Komorebi {
    param([Parameter(Mandatory)]$Payload)
    Install-MsiProduct -Payload $Payload `
        -ProductCode    '{0611503C-EC25-4A3C-9305-4390D9E69281}' `
        -ExpectedVersion '0.1.41' `
        -DetectionProbe (Join-Path $env:ProgramFiles 'komorebi\bin\komorebic.exe') `
        -DisplayName    'Komorebi'
}

function Install-Whkd {
    param([Parameter(Mandatory)]$Payload)
    Install-MsiProduct -Payload $Payload `
        -ProductCode    '{96B2D7B2-62E0-425E-B9F3-998667C147A4}' `
        -ExpectedVersion '0.2.10' `
        -DetectionProbe (Join-Path $env:ProgramFiles 'whkd\bin\whkd.exe') `
        -DisplayName    'WHKD'
}

function Install-Yasb {
    param([Parameter(Mandatory)]$Payload)
    Install-MsiProduct -Payload $Payload `
        -ProductCode    '{B422A5E6-CEDA-42E3-84F8-F8142D0A79E3}' `
        -ExpectedVersion '2.0.7' `
        -DetectionProbe (Join-Path $env:ProgramFiles 'YASB\yasb.exe') `
        -DisplayName    'YASB'
}

# ===========================================================================
# Configuration generation (ticket 03, ADR-0003 + ADR-0016)
#
# The repo ships PORTABLE templates under config\ and the installer writes the
# machine-specific parts at install time, so a target machine ends up
# byte-for-byte identical to the source machine in everything that is truly
# portable, and correct in everything that depends on the hardware.
#
#   config\komorebi.json     template; monitors / display_index_preferences /
#                           app_specific_configuration_path are generated
#   config\whkdrc            verbatim
#   config\applications.json verbatim
#   config\config.yaml       YASB; the sensor-script path is rewritten
#   scripts\sensor-color.ps1 shipped here so the YASB path can be repo-relative
# ===========================================================================

# The single portable workspace layout. One block of this is emitted per
# detected monitor. This is the exact layout of the source machine.
$script:PortableWorkspaceLayout = @(
    @{ name = '1'; layout = 'BSP' },
    @{ name = '2'; layout = 'VerticalStack' },
    @{ name = '3'; layout = 'HorizontalStack' },
    @{ name = '4'; layout = 'VerticalStack' },
    @{ name = '5'; layout = 'VerticalStack' },
    @{ name = '6'; layout = 'VerticalStack' },
    @{ name = '7'; layout = 'VerticalStack' },
    @{ name = '8'; layout = 'VerticalStack' },
    @{ name = '9'; layout = 'VerticalStack' }
)

function Get-KomorebiConfigHome {
    # komorebi honours $env:KOMOREBI_CONFIG_HOME and otherwise defaults to
    # %USERPROFILE%\.config\komorebi. Resolve exactly the way komorebi does so
    # the generated file lands where komorebi actually reads it from.
    if ($env:KOMOREBI_CONFIG_HOME) { return $env:KOMOREBI_CONFIG_HOME }
    return (Join-Path $env:USERPROFILE '.config\komorebi')
}

function Get-DetectedDisplays {
    # Returns the GDI display device names in adapter order: DISPLAY1, DISPLAY2...
    # These are exactly the values komorebi's display_index_preferences expects
    # (the source machine's own config uses "DISPLAY1".."DISPLAY3"), and they are
    # hardware-dependent, so they must never be copied.
    Add-Type -ErrorAction SilentlyContinue -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class KomorebiDisplayEnum {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]  public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }
    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
    public static string[] GetDisplays() {
        var list = new System.Collections.Generic.List<string>();
        for (uint i = 0; i < 32; i++) {
            DISPLAY_DEVICE d = new DISPLAY_DEVICE();
            d.cb = 4 + 32 + 128 + 4 + 128 + 128;
            if (!EnumDisplayDevices(null, i, ref d, 0)) break;
            // StateFlags bit 0 = DISPLAY_DEVICE_ATTACHED_TO_DESKTOP. Only attached
            // displays are part of the layout; a detached one (e.g. a disabled
            // output on the same GPU) would otherwise consume a workspace block.
            if ((d.StateFlags & 1) != 1) continue;
            // komorebi derives its monitor name from the GDI device name with the
            // "\\.\" device prefix and any child path stripped (windows_api.rs:
            // device_name.trim_start_matches(r"\\.\").split('\\')[0]). Emit the
            // same canonical form so the generated value matches the source
            // machine's "DISPLAY1" style exactly.
            string n = d.DeviceName.TrimStart(new char[] { '\\', '.' });
            int cut = n.IndexOf('\\');
            if (cut >= 0) n = n.Substring(0, cut);
            list.Add(n);
        }
        return list.ToArray();
    }
}
'@ -Language CSharp
    return [KomorebiDisplayEnum]::GetDisplays()
}

function Get-GeneratedMonitors {
    # One MonitorConfig block per detected monitor, each carrying the same
    # portable 9-workspace layout. The schema only requires `workspaces` on a
    # MonitorConfig and only `name` on a WorkspaceConfig, so this is valid.
    param([Parameter(Mandatory)][string[]] $Displays)

    $monitors = @()
    foreach ($display in $Displays) {
        $workspaces = @()
        foreach ($ws in $script:PortableWorkspaceLayout) {
            $workspaces += [PSCustomObject]@{ name = $ws.name; layout = $ws.layout }
        }
        $monitors += [PSCustomObject]@{ workspaces = $workspaces }
    }
    , $monitors
}

function Get-GeneratedDisplayIndexPreferences {
    # Keys "0".."N-1", values = live display names. Generated, never copied.
    param([Parameter(Mandatory)][string[]] $Displays)

    $prefs = [ordered]@{}
    for ($i = 0; $i -lt $Displays.Count; $i++) {
        $prefs["$i"] = $Displays[$i]
    }
    return [PSCustomObject]$prefs
}

function Test-ConfigUpToDate {
    # True when the on-disk komorebi.json already reflects this machine's live
    # hardware, so a re-run regenerates nothing and re-running after a
    # dock/undock is what triggers the refresh.
    param([Parameter(Mandatory)][string] $ConfigPath, [Parameter(Mandatory)][string[]] $Displays)

    if (-not (Test-Path $ConfigPath)) { return $false }
    try {
        $current = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch { return $false }

    $monitors = @($current.monitors)
    if ($monitors.Count -ne $Displays.Count) { return $false }

    $prefs = $current.display_index_preferences
    for ($i = 0; $i -lt $Displays.Count; $i++) {
        if ($prefs."$i" -ne $Displays[$i]) { return $false }
    }

    # The portable layout must be intact on every monitor.
    foreach ($m in $monitors) {
        if (-not $m.workspaces) { return $false }
        if (@($m.workspaces).Count -ne $script:PortableWorkspaceLayout.Count) { return $false }
        for ($w = 0; $w -lt $script:PortableWorkspaceLayout.Count; $w++) {
            $expect = $script:PortableWorkspaceLayout[$w]
            $actual = @($m.workspaces)[$w]
            if ($actual.name -ne $expect.name -or $actual.layout -ne $expect.layout) { return $false }
        }
    }
    return $true
}

function New-KomorebiConfig {
    # Emits the final komorebi.json: template + generated monitors + generated
    # display_index_preferences + the target user's applications.json path.
    param(
        [Parameter(Mandatory)][string]   $TemplatePath,
        [Parameter(Mandatory)][string]   $OutputPath,
        [Parameter(Mandatory)][string[]] $Displays
    )

    $template = Get-Content $TemplatePath -Raw -Encoding UTF8 | ConvertFrom-Json

    # app_specific_configuration_path must be rewritten to the TARGET user's
    # absolute path. Rust does not expand PowerShell-style env vars in this
    # field, so it cannot be shipped as "%USERPROFILE%\applications.json"
    # (handoff bug #4: the source config literally contained the source
    # machine's C:\Users\DavoodYa path).
    $applicationsPath = Join-Path $env:USERPROFILE 'applications.json'
    $template.app_specific_configuration_path = $applicationsPath

    $template.monitors = Get-GeneratedMonitors -Displays $Displays
    $template.display_index_preferences = Get-GeneratedDisplayIndexPreferences -Displays $Displays

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    # Depth 100 covers the nested monitors/workspaces tree. The emitted file is
    # UTF8 without a BOM: komorebi's JSON parser is serde_json, which is fine
    # with UTF8, but a BOM on a file that Rust reads via fs::read can surface as
    # a stray character in error messages.
    $json = $template | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($OutputPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function New-Whkdrc {
    # whkdrc is copied VERBATIM with one exception: the source machine's own
    # paths are rewritten to the target user's. Three bindings reference files
    # under the source user's %USERPROFILE% (restart-whkd.cmd, the
    # komorebi-resize.json save/load targets, toggle-transparency.ps1). Those
    # hotkeys would silently do nothing on another machine if left as-is — the
    # same class of bug as the app_specific_configuration_path issue.
    #
    # The komorebic.exe path (C:\Progra~1\komorebi\bin\...) is the vendor
    # install default and stays untouched.
    param([Parameter(Mandatory)][string] $TemplatePath, [Parameter(Mandatory)][string] $OutputPath)

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $content = Get-Content $TemplatePath -Raw -Encoding UTF8
    $targetProfile = $env:USERPROFILE.TrimEnd('\')

    # Use [regex]::Replace rather than the -replace operator: in .NET replacement
    # strings a literal backslash is an escape prefix, so -replace would double
    # every backslash in the target path. Passing the text to the Regex.Replace
    # overload that takes a plain string avoids that interpretation.
    $rewritten = [regex]::Replace($content, 'C:\\Users\\DavoodYa', $targetProfile)

    [System.IO.File]::WriteAllText($OutputPath, $rewritten, (New-Object System.Text.UTF8Encoding($false)))
}

function New-ApplicationsJson {
    # applications.json is copied VERBATIM. The companion file must sit next to
    # the komorebi.json that references it, i.e. in the komorebi config home.
    param([Parameter(Mandatory)][string] $TemplatePath, [Parameter(Mandatory)][string] $OutputPath)

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item $TemplatePath $OutputPath -Force
}

function New-KomorebiResizeJson {
    # Pure runtime state. It is CREATED EMPTY and never shipped with content:
    # whkdrc binds save-resize / load-resize against it, and shipping one
    # machine's resize state would apply it to another machine.
    param([Parameter(Mandatory)][string] $OutputPath)

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($OutputPath, '', (New-Object System.Text.UTF8Encoding($false)))
}

function New-YasbConfig {
    # config.yaml is copied verbatim except the sensor-script path, which is
    # rewritten to the repo-relative sensor-color.ps1 so it never points at a
    # machine-specific location (the source machine's config pointed at
    # C:\Users\DavoodYa\Tools\sensor-color.ps1).
    #
    # Escaping note: the YAML file stores the path with doubled backslashes
    # (YAML's own escaping — `C:\\Users\\...` in the file text, which YAML
    # unescapes to `C:\Users\...` at parse time). The replacement text must be
    # escaped the same way, so every single backslash in the target path becomes
    # two in the written file. In PowerShell `-replace` treats BOTH operands as
    # regular expressions, so '\\' means a literal backslash.
    param([Parameter(Mandatory)][string] $TemplatePath, [Parameter(Mandatory)][string] $SensorScript, [Parameter(Mandatory)][string] $OutputPath)

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $content = Get-Content $TemplatePath -Raw -Encoding UTF8
    $pattern = '(?<=powershell -NoProfile -ExecutionPolicy Bypass -File )\\?[^"]*?sensor-color\.ps1'
    # The YAML file stores the path with doubled backslashes, so the replacement
    # text must be escaped the same way. [regex]::Replace with a plain string
    # would treat a lone backslash as an escape prefix; use the MatchEvaluator
    # overload so the replacement is inserted literally.
    $escapedTarget = $SensorScript -replace '\\', '\\'
    $rewritten = [regex]::Replace($content, $pattern, { param($m) $escapedTarget })

    [System.IO.File]::WriteAllText($OutputPath, $rewritten, (New-Object System.Text.UTF8Encoding($false)))
}

function Test-GeneratedConfig {
    # komorebic check is the authority: it parses the generated config and the
    # referenced files and reports schema/consistency problems. A non-zero exit
    # code aborts the install rather than declaring success on a broken config.
    param([Parameter(Mandatory)][string] $Komorebic, [Parameter(Mandatory)][string] $ConfigPath)

    if (-not (Test-Path $Komorebic)) {
        throw "komorebic.exe is not installed at '$Komorebic'. Cannot validate the generated configuration."
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Komorebic
    $psi.Arguments = "check -k `"$ConfigPath`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        $detail = ($stdout, $stderr | Where-Object { $_ } ) -join "`n"
        throw ("komorebic check failed (exit {0}): {1}" -f $proc.ExitCode, $detail.Trim())
    }
    return $stdout.Trim()
}

function Install-Configuration {
    # The ticket 03 entry point. Generates the whole Komorebi/WHKD/YASB config
    # for this machine and validates it. Every artifact is state-detected, so
    # re-running regenerates only what the live hardware changed.
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [switch] $SkipValidation
    )

    Write-Step 'Generating configuration'

    $displays = Get-DetectedDisplays
    if ($displays.Count -eq 0) {
        throw 'No displays are attached to the desktop. The Komorebi layout needs at least one monitor.'
    }

    $configHome    = Get-KomorebiConfigHome
    $komorebiJson  = Join-Path $configHome 'komorebi.json'
    $whkdrc        = Join-Path $configHome '..\whkdrc'
    $applications  = Join-Path $configHome 'applications.json'
    $resizeState   = Join-Path $configHome 'komorebi-resize.json'
    $yasbConfig    = Join-Path $env:USERPROFILE '.config\yasb\config.yaml'
    $sensorScript  = Join-Path $RepoRoot 'scripts\sensor-color.ps1'
    $komorebic     = Join-Path $env:ProgramFiles 'komorebi\bin\komorebic.exe'

    $template = Join-Path $RepoRoot 'config'

    # --- Komorebi -----------------------------------------------------------
    if (Test-ConfigUpToDate -ConfigPath $komorebiJson -Displays $displays) {
        Write-StepSkipped ('Komorebi configuration already matches this machine ({0} monitor(s)).' -f $displays.Count)
    } else {
        New-KomorebiConfig -TemplatePath (Join-Path $template 'komorebi.json') `
                           -OutputPath   $komorebiJson `
                           -Displays     $displays
        Write-StepDone ('Komorebi configuration generated for {0} monitor(s): {1}.' -f `
            $displays.Count, ($displays -join ', '))
    }

    # --- WHKD ----------------------------------------------------------------
    # whkdrc is generated (source paths rewritten to this user's), so compare
    # the RENDERED result rather than the template hash.
    $whkdrcTemplate = Join-Path $template 'whkdrc'
    $targetProfile = $env:USERPROFILE.TrimEnd('\')
    $expectedWhkdrc = [regex]::Replace((Get-Content $whkdrcTemplate -Raw -Encoding UTF8), 'C:\\Users\\DavoodYa', $targetProfile)
    $whkdrcUpToDate = (Test-Path $whkdrc) -and ((Get-Content $whkdrc -Raw -Encoding UTF8) -ceq $expectedWhkdrc)
    if ($whkdrcUpToDate) {
        Write-StepSkipped 'whkdrc is already in place.'
    } else {
        New-Whkdrc -TemplatePath $whkdrcTemplate -OutputPath $whkdrc
        Write-StepDone 'whkdrc copied with the target user paths.'
    }

    # --- applications.json ---------------------------------------------------
    if ((Test-Path $applications) -and ((Get-FileHash $applications -Algorithm SHA256).Hash -eq (Get-FileHash (Join-Path $template 'applications.json') -Algorithm SHA256).Hash)) {
        Write-StepSkipped 'applications.json is already in place.'
    } else {
        New-ApplicationsJson -TemplatePath (Join-Path $template 'applications.json') -OutputPath $applications
        Write-StepDone 'applications.json copied.'
    }

    # --- resize state (created empty, always) --------------------------------
    New-KomorebiResizeJson -OutputPath $resizeState
    if ((Get-Item $resizeState).Length -eq 0) {
        Write-StepDone 'komorebi-resize.json created empty (runtime state).'
    } else {
        Write-StepSkipped 'komorebi-resize.json already exists and holds runtime state — left untouched.'
    }

    # --- YASB ----------------------------------------------------------------
    if (Test-Path $yasbConfig) {
        Write-StepSkipped 'YASB configuration already exists — left untouched.'
    } else {
        New-YasbConfig -TemplatePath (Join-Path $template 'config.yaml') `
                       -SensorScript $sensorScript `
                       -OutputPath   $yasbConfig
        Write-StepDone 'YASB configuration generated with a repo-relative sensor path.'
    }

    # --- Validation ----------------------------------------------------------
    if (-not $SkipValidation) {
        Write-Step 'Validating the generated configuration'
        $report = Test-GeneratedConfig -Komorebic $komorebic -ConfigPath $komorebiJson
        if ($report) {
            Write-Host ("    {0}" -f ($report -split "`n" | Select-Object -First 6) -join "`n    ") -ForegroundColor DarkGray
        }
        Write-StepDone 'komorebic check passed.'
    }
}
