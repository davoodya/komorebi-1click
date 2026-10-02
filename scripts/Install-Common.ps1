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
