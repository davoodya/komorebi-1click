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
    if ($script:DryRun) {
        Write-Host 'Mode: DRY RUN - nothing is installed or changed' -ForegroundColor Cyan
    }
    Write-Host ''
}

function Write-InstallerFooter {
    Write-Host ''
    Write-Host 'Installation complete.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'The AutoHotkey scripts start on the next logon via the' -ForegroundColor DarkGray
    Write-Host 'generated AppRunner.vbs in the Startup folder.' -ForegroundColor DarkGray
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

function Write-StepOutcome {
    <#
      Prints the step status honestly in BOTH modes: the dry-run wording when
      nothing was actually written (the "[DRY-RUN] would ..." lines above it
      carry the intention), and the real wording after a real action.
    #>
    param(
        [Parameter(Mandatory)][string]$Dry,
        [Parameter(Mandatory)][string]$Real
    )
    if ($script:DryRun) { Write-StepSkipped $Dry } else { Write-StepDone $Real }
}

# ===========================================================================
# Failure reporting
# ===========================================================================

<#
.SYNOPSIS
    Reports a failed installer step the way the specification requires:
    the failing step, the underlying cause, and the concrete remedy.

.DESCRIPTION
    Accepts EITHER an ErrorRecord (the normal case: called from a catch block
    with `-ErrorRecord $_`) OR an explicit Cause/Remedy pair. A catch block
    hands over an ErrorRecord, so accepting both keeps every call site
    simple while still allowing a hand-written cause when the failure is a
    logical one that threw no exception.
#>
function Report-InstallerFailure {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter()][string]$Cause,
        [Parameter()][string]$Remedy,
        [Parameter()]$ErrorRecord
    )

    # Normalise: an ErrorRecord is the common input, but the message we want
    # the user to read is the innermost one — most MSI and .NET failures wrap
    # the real reason two or three layers deep.
    if (-not $Cause -and $ErrorRecord) {
        $msg = $ErrorRecord.Exception.Message
        $inner = $ErrorRecord.Exception
        while ($inner.InnerException) { $inner = $inner.InnerException; $msg = $inner.Message }
        $Cause = $msg
    }
    if (-not $Cause) { $Cause = 'No additional detail was captured.' }
    if (-not $Remedy) {
        $Remedy = 'Resolve the reported cause, then run the installer again. Every completed step is detected and skipped, so only this step re-runs.'
    }

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

<#
.SYNOPSIS
    Final summary line for an aborted install.
#>
function Write-InstallerFailureFooter {
    param([Parameter(Mandatory)][string]$Reason)
    Write-Host ''
    Write-Host 'INSTALL ABORTED' -ForegroundColor Red
    Write-Host ('  Reason: {0}' -f $Reason) -ForegroundColor Red
    Write-Host '  Fix the reported cause and run this installer again.' -ForegroundColor Yellow
    Write-Host '  Nothing after the failing step was modified.' -ForegroundColor DarkGray
    Write-Host ''
}

# ===========================================================================
# Preconditions
# ===========================================================================

function Assert-ArchitectureSupported {
    $arch = $env:PROCESSOR_ARCHITECTURE
    # NOTE: no ternary operator — the installer must run on Windows
    # PowerShell 5.1 (the inbox shell on every supported Windows build), and
    # the `? :` operator is PowerShell 7+ only.
    if (-not $arch) {
        $arch = if ([System.IntPtr]::Size -eq 8) { 'AMD64' } else { 'x86' }
    }

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
        -Remedy 'Relaunch as administrator: right-click Install.ps1 (or komorebi-1click-install.exe) and choose "Run as administrator", or run it from an elevated PowerShell window.'
    throw 'Installer is not elevated'
}

<#
.SYNOPSIS
    Runs the installer with administrator privileges: silently when it already
    has them, otherwise by relaunching the script through the UAC prompt and
    forwarding the outcome.
.DESCRIPTION
    The MSIs write into C:\Program Files, so elevation is mandatory. A
    non-elevated run used to be *refused* (print a report, throw, exit 1) —
    and because the launcher window closed immediately after, the double-click
    and "Run with PowerShell" paths just looked dead ("nothing happened and
    it didn't proceed"). The installer now asks for elevation itself, exactly
    like the EXE wrapper does, so one interaction reaches the install.

    -SkipElevationCheck bypasses this entirely: the EXE wrapper elevates
    first, and the Sandbox suite runs pre-elevated.

    The KOMOREBI_1CLICK_ELEVATED_LAUNCH marker makes the relaunched child
    refuse loudly instead of raising a second prompt if the elevation did not
    actually take.
#>
function Invoke-InstallerElevation {
    param([string[]]$Arguments)

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]$identity
    if ($principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Step 'Running as Administrator.'
        return
    }

    if ($env:KOMOREBI_1CLICK_ELEVATED_LAUNCH -or -not $PSCommandPath) {
        # Already relaunched once (or running from memory without a file to
        # re-execute): report and refuse rather than prompt again.
        Assert-RunningElevated
    }

    Write-Host ''
    Write-Host '  Administrator privileges are required. Approve the Windows' -ForegroundColor Yellow
    Write-Host '  elevation prompt to continue the installation.' -ForegroundColor Yellow
    Write-Host ''

    # Build the child argument string the way the wrapper does: .NET
    # Framework's ProcessStartInfo has no ArgumentList, so quote only values
    # that actually need it.
    $shell = (Get-Process -Id $PID).Path
    $childArgs = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    if ($Arguments) { $childArgs += ' ' + ($Arguments -join ' ') }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName        = $shell
    $psi.Arguments       = $childArgs
    $psi.UseShellExecute = $true          # required for the runas verb
    $psi.Verb            = 'runas'
    $psi.WorkingDirectory = Split-Path $PSCommandPath -Parent

    # The marker stops a still-non-elevated child from prompting forever.
    $env:KOMOREBI_1CLICK_ELEVATED_LAUNCH = '1'

    try {
        $elevated = [System.Diagnostics.Process]::Start($psi)
    } catch {
        $env:KOMOREBI_1CLICK_ELEVATED_LAUNCH = $null
        Report-InstallerFailure `
            -Step   'Elevation check' `
            -Cause  'The elevation request was declined or could not be started.' `
            -Remedy 'Run Install.ps1 again and approve the elevation prompt, or right-click it and choose "Run as administrator".'
        throw 'Elevation was declined'
    }

    if ($null -eq $elevated) {
        Report-InstallerFailure `
            -Step   'Elevation check' `
            -Cause  'The elevated relaunch did not start.' `
            -Remedy 'Run Install.ps1 again and approve the elevation prompt, or right-click it and choose "Run as administrator".'
        throw 'Elevation failed'
    }

    $elevated.WaitForExit()
    exit $elevated.ExitCode
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
        if ($script:DryRun) {
            Show-DryRunAction ("install " + $payloadPath + " with msiexec")
            $exitCode = 0
        } else {
            $exitCode = Start-Process -FilePath 'msiexec.exe' `
                -ArgumentList @('/i', "`"$payloadPath`"", '/quiet', '/norestart', 'REBOOT=Suppress') `
                -Wait -PassThru -NoNewWindow |
                Select-Object -ExpandProperty ExitCode
        }
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
    if (-not $script:DryRun -and -not $nowInstalled) {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  'msiexec reported success, but the product is not registered afterwards.' `
            -Remedy "Check that '$($Payload.file)' is a valid MSI for this Windows build, then re-run this installer."
        throw "$DisplayName did not register after a successful msiexec exit code"
    }

    if (-not $script:DryRun -and -not (Test-Path -LiteralPath $DetectionProbe)) {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  "The product registered, but the expected file is not present: $DetectionProbe" `
            -Remedy "An antivirus or a group policy may have removed the installed files. Check $DetectionProbe, then re-run this installer."
        throw "$DisplayName registered but its expected file is missing"
    }

    if ($script:DryRun) {
        Write-StepSkipped ("$DisplayName {0} would be installed." -f $ExpectedVersion)
    } else {
        Write-StepDone ("$DisplayName {0} installed." -f $nowInstalled)
    }
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
        if ($script:DryRun) {
            Show-DryRunAction ("install " + $payloadPath + " (silent setup)")
            $exitCode = 0
        } else {
            $process = Start-Process -FilePath $payloadPath -ArgumentList '/S' -Wait -PassThru
            $exitCode = $process.ExitCode
        }
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
    if (-not $script:DryRun -and -not (Test-Path -LiteralPath $exe)) {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  "The setup reported success, but $exe is not present." `
            -Remedy "An antivirus may have quarantined the install. Check $env:ProgramFiles\AutoHotkey, then re-run this installer."
        throw 'AutoHotkey v1 setup succeeded but AutoHotkey.exe is missing'
    }

    if ($script:DryRun) { Write-StepSkipped 'AutoHotkey v1 would be installed.' } else { Write-StepDone ('AutoHotkey v1 installed.') }
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
        if ($script:DryRun) {
            Show-DryRunAction ("install " + $payloadPath + " (silent setup)")
            $exitCode = 0
        } else {
            $process = Start-Process -FilePath $payloadPath -ArgumentList '/silent' -Wait -PassThru
            $exitCode = $process.ExitCode
        }
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
    if (-not $script:DryRun -and -not (Test-Path -LiteralPath $exe)) {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  "The setup reported success, but $exe is not present." `
            -Remedy "Check $env:ProgramFiles\AutoHotkey\v2. If the directory is absent, an antivirus removed it; re-run this installer."
        throw 'AutoHotkey v2 setup succeeded but AutoHotkey64.exe is missing'
    }

    if ($script:DryRun) { Write-StepSkipped 'AutoHotkey v2 would be installed.' } else { Write-StepDone ('AutoHotkey v2 installed.') }
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
# Dry-run mode (2026-10-10)
#
# Set-InstallerDryRun turns every mutating action into a printed intention, so
# the WHOLE pipeline (payload integrity, state detection, config comparison,
# PATH/task/patch steps) can be exercised on a live, working machine without
# changing a single byte of it. Reads and comparisons stay real: the state the
# pipeline reports is the machine's true state. Put together with the Windows
# Sandbox suites, a verification run never needs to disturb a live install.
# ===========================================================================

# Initialise the flag ONLY when it does not exist yet. Install.ps1 declares
# -DryRun as a switch PARAMETER, which lives in this very script scope once this
# file is dot-sourced, so an unconditional assignment here reset the caller's
# requested value to $false and dry-run mode stayed completely inert: the
# banner never printed and every guard stayed off (found 2026-10-10).
if (-not (Test-Path variable:script:DryRun)) { $script:DryRun = $false }

function Set-InstallerDryRun {
    param([switch]$Enabled)
    $script:DryRun = [bool]$Enabled
}

function Show-DryRunAction {
    param([string]$What)
    Write-Host ("    [DRY-RUN] would " + $What) -ForegroundColor Cyan
}

function New-InstallerDirectory {
    param([string]$Path)
    if ($script:DryRun) { Show-DryRunAction ("create directory " + $Path); return }
    [System.IO.Directory]::CreateDirectory($Path) | Out-Null
}

function Copy-InstallerFile {
    param(
        [string]$LiteralPath,
        [string]$Destination,
        [string]$Description = ''
    )
    if ($script:DryRun) {
        Show-DryRunAction ("copy " + $(if ($Description) { $Description } else { "$LiteralPath -> $Destination" }))
        return
    }
    Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force
}

function Write-InstallerFile {
    param(
        [string]$Path,
        [string]$Content,
        [string]$Description = ''
    )
    if ($script:DryRun) {
        Show-DryRunAction ("write " + $(if ($Description) { $Description } else { $Path }))
        return
    }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-InstallerAction {
    <#
      Runs a mutating action, or - in dry-run mode - prints what WOULD happen
      and skips it. Used for the actions that are not file writes (scheduled
      tasks, komorebic stop/start, yasb autostart, shortcut creation).
    #>
    param(
        [string]$Description,
        [scriptblock]$Action
    )
    if ($script:DryRun) { Show-DryRunAction $Description; return }
    & $Action
}

# ===========================================================================
# Komorebi access-denied patch (docs/Access-Denied-Solving, 2026-10-10)
#
# WHAT IT FIXES
#   komorebi 0.1.41 spawns konsole/konsole subprocesses under an elevated
#   Windows Terminal. Without the patch the child VOC bridge dies with
#   "Access is denied" (0x80070005) and takes the whole WM down two seconds
#   later. The defect is GitHub issue #1463; upstream has not shipped a fix in
#   0.1.41 (2025-08-25) and no later stable exists, so the repair has to be
#   local.
#
# WHAT THIS DOES
#   The repository carries the PRE-PATCHED komorebi.exe under
#   docs\Access-Denied-Solving\Komorebi-Patched — byte-identical to what
#   Access-Denied-0x80070005-fixing.ps1 produces on the unpatched binary.
#   This step deploys it over the MSI-installed one right after the Komorebi
#   install step, hash-verified before and after, idempotent on re-runs.
#
# WHY A COPY AND NOT A PATCH-AT-INSTALL-TIME
#   The two patch sites (0x2898E9 and 0x28D7E4) are binary offsets pinned to
#   this exact komorebi 0.1.41 build. Copying a pinned, hash-verified binary
#   is deterministic and auditable; re-deriving the offsets at install time
#   risks patching a future build wrongly. The fixing script stays the
#   manual-repair path.
#
# The pristine MSI binary is preserved once as komorebi.exe.orig next to the
# installed binary, and a running instance is stopped and restarted through
# the same socket pairing whkd needs (LGUG2Z/komorebi#956).
# ===========================================================================

# SHA256 of the committed pre-patched binary; also pinned in
# binaries\payloads.sha256.json (verified on every run by
# Test-PayloadIntegrity, and again here before anything is copied).
$script:KomorebiPatchedSha256 = '52B631CDCC5E5495342542740A52F57594B9B540E24E2888BD23F1D41B7E3ABB'

function Get-PatchedKomorebiPath {
    param([Parameter(Mandatory)][string]$RepoRoot)
    return (Join-Path $RepoRoot 'docs\Access-Denied-Solving\Komorebi-Patched\komorebi.exe')
}

function Install-KomorebiPatch {
    <#
    .SYNOPSIS
        Deploys the pre-patched komorebi.exe over the MSI-installed binary.
    .DESCRIPTION
        State-detected: when the installed binary already matches the pinned
        hash, nothing happens. The SHA256 of the repository copy is checked
        before the copy and the deployed file is re-checked after it, so the
        step can never claim success without the exact binary being present.
    #>
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$PatchedSha256 = $script:KomorebiPatchedSha256
    )

    $stepName  = 'Install the Komorebi access-denied patch'
    $komorebic = Join-Path $env:ProgramFiles 'komorebi\bin\komorebic.exe'
    $installed = Join-Path $env:ProgramFiles 'komorebi\bin\komorebi.exe'

    if (-not (Test-Path -LiteralPath $installed)) {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  "The installed komorebi.exe was not found at '$installed'." `
            -Remedy 'Install the Komorebi MSI first (its step runs before this one).'
        throw 'komorebi.exe is missing'
    }

    $patched = Get-PatchedKomorebiPath -RepoRoot $RepoRoot
    if (-not (Test-Path -LiteralPath $patched)) {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  "The pre-patched komorebi.exe is missing from the repository: $patched" `
            -Remedy 'Re-clone or re-extract this repository; the patched binary is part of it (docs\Access-Denied-Solving\Komorebi-Patched).'
        throw 'patched komorebi.exe is missing from the repository'
    }

    $patchedHash = (Get-FileHash -LiteralPath $patched -Algorithm SHA256).Hash
    if ($patchedHash -ne $PatchedSha256) {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  ("The repository's pre-patched binary does not match its pin.`n      expected {0}`n      found    {1}" -f $PatchedSha256, $patchedHash) `
            -Remedy 'Re-extract docs\Access-Denied-Solving from the repository. Do not continue: an unverified binary must never be deployed.'
        throw 'patched komorebi.exe failed integrity verification'
    }

    $installedHash = (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash
    if ($installedHash -eq $PatchedSha256) {
        Write-StepSkipped 'Komorebi already carries the access-denied patch.'
        return
    }

    # --- stop the running pair so the binary file is not locked ---------------
    $wasRunning = ($null -ne (Get-Process -Name 'komorebi' -ErrorAction SilentlyContinue))
    if ($wasRunning) {
        if (Test-Path -LiteralPath $komorebic) { Invoke-InstallerAction "stop komorebi and whkd (komorebic stop --whkd)" { & $komorebic stop --whkd 2>&1 | Out-Null } }
        Start-Sleep -Seconds 2
        if ($null -ne (Get-Process -Name 'komorebi' -ErrorAction SilentlyContinue)) {
            if (-not $script:DryRun) { Stop-Process -Name 'komorebi' -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Seconds 1
        }
    }

    # --- preserve the pristine binary once, then deploy the patched one ------
    try {
        $orig = Join-Path (Split-Path $installed -Parent) 'komorebi.exe.orig'
        if (-not (Test-Path -LiteralPath $orig)) {
            Copy-InstallerFile -LiteralPath $installed -Destination $orig -Description "preserve the MSI-installed binary as komorebi.exe.orig"
            Write-StepDone 'Preserved the original binary as komorebi.exe.orig.'
        }
        Copy-InstallerFile -LiteralPath $patched -Destination $installed -Description "deploy the patched komorebi.exe"
    } catch {
        Report-InstallerFailure `
            -Step   $stepName `
            -Cause  $_.Exception.Message `
            -Remedy 'Close Komorebi and try again; an antivirus or a running instance can hold the binary open.'
        throw
    }

    # --- verify the deployed file is EXACTLY the pinned binary -----------------
    if ($script:DryRun) {
        Show-DryRunAction ('verify the deployed komorebi.exe matches the pinned SHA256 ' + $PatchedSha256)
    } else {
        $afterHash = (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash
        if ($afterHash -ne $PatchedSha256) {
            Report-InstallerFailure `
                -Step   $stepName `
                -Cause  ("The deployed komorebi.exe does not match the pinned patched binary.`n      expected {0}`n      found    {1}" -f $PatchedSha256, $afterHash) `
                -Remedy 'Restore komorebi.exe.orig from the install directory and investigate; the copy did not land intact.'
            throw 'patched komorebi.exe did not deploy intact'
        }
    }

    # --- bring the pair back through the same socket pairing whkd needs --------
    if ($wasRunning -and (Test-Path -LiteralPath $komorebic)) {
        Invoke-InstallerAction "start komorebi with whkd again (komorebic start --whkd)" { & $komorebic start --whkd 2>&1 | Out-Null }
        Start-Sleep -Seconds 2
        if ($null -eq (Get-Process -Name 'komorebi' -ErrorAction SilentlyContinue)) {
            Report-InstallerFailure `
                -Step   $stepName `
                -Cause  'The patched binary was deployed, but Komorebi did not start again.' `
                -Remedy 'Start it once manually from the Komorebi logon task, or run: komorebic start --whkd'
            throw 'Komorebi did not restart after the patch'
        }
    }

    Write-StepDone 'Komorebi replaced with the patched build (SHA256 verified).'
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
    # display_index_preferences + the ASC (app-specific configuration) path.
    param(
        [Parameter(Mandatory)][string]   $TemplatePath,
        [Parameter(Mandatory)][string]   $OutputPath,
        [Parameter(Mandatory)][string[]] $Displays
    )

    $template = Get-Content $TemplatePath -Raw -Encoding UTF8 | ConvertFrom-Json

    # app_specific_configuration_path handling (repaired 2026-10-10, finding F3
    # of docs/installation-system-repairing/AUDIT-2026-10-10). Previous state:
    # this line rewrote the template's portable value to the absolute
    # %USERPROFILE%\applications.json, while the installer actually deploys the
    # file at %USERPROFILE%\.config\komorebi\applications.json - komorebi then
    # died reading the missing file (gate 4, asc.rs:40) after every successful
    # install. komorebic check cannot catch that (verified: it exits 0 with a
    # non-existent ASC file), so Install-Configuration re-validates it below.
    #
    # The template already carries the correct portable form and komorebi DOES
    # expand %VAR% in this field (verified against 0.1.41 in
    # docs/Access-Denied-Solving/Access-Denied-(0x80070005)-Bug-Solving.md), so
    # the portable value is kept as-is in the default layout, and only an
    # active KOMOREBI_CONFIG_HOME override (which relocates the whole config
    # home) forces an absolute path.
    $configHome  = Split-Path $OutputPath -Parent
    $deployedAsc = Join-Path $configHome 'applications.json'

    $ascPath = $template.app_specific_configuration_path
    if ($env:KOMOREBI_CONFIG_HOME) {
        $template.app_specific_configuration_path = $deployedAsc
    } elseif ($ascPath) {
        $expanded = [Environment]::ExpandEnvironmentVariables([string]$ascPath).Replace('\\', '\')
        if ($expanded -ne $deployedAsc) {
            # The template value points somewhere other than where this
            # installer deploys the file: normalise to the deployed location,
            # kept portable via %USERPROFILE% so no machine path is baked in.
            $template.app_specific_configuration_path = '%USERPROFILE%\.config\komorebi\applications.json'
        }
    } else {
        $template.app_specific_configuration_path = '%USERPROFILE%\.config\komorebi\applications.json'
    }

    $template.monitors = Get-GeneratedMonitors -Displays $Displays
    $template.display_index_preferences = Get-GeneratedDisplayIndexPreferences -Displays $Displays

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-InstallerDirectory $dir }

    # Depth 100 covers the nested monitors/workspaces tree. The emitted file is
    # UTF8 without a BOM: komorebi's JSON parser is serde_json, which is fine
    # with UTF8, but a BOM on a file that Rust reads via fs::read can surface as
    # a stray character in error messages.
    $json = $template | ConvertTo-Json -Depth 100
    Write-InstallerFile -Path $OutputPath -Content $json
}

function New-Whkdrc {
    # whkdrc is copied VERBATIM with one exception: the source machine's own
    # paths are rewritten to the target user's. Several bindings reference
    # files under the source user's %USERPROFILE%: the restart-whkd.cmd shim,
    # the komorebi-resize.json save/load targets, toggle-transparency.ps1 and
    # safe-restart.ps1. The shim and the resize targets are generated by the
    # installer alongside this file (the resize file as empty runtime state,
    # the shim with this machine's komorebic path); toggle-transparency.ps1
    # and safe-restart.ps1 are copied verbatim by the companion-script block
    # below. Without those, the hotkeys would silently do nothing on another
    # machine — the same class of bug as the app_specific_configuration_path
    # issue.
    #
    # The komorebic.exe path (C:\Progra~1\komorebi\bin\...) is the vendor
    # install default and stays untouched.
    param([Parameter(Mandatory)][string] $TemplatePath, [Parameter(Mandatory)][string] $OutputPath)

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-InstallerDirectory $dir }

    $content = Get-Content $TemplatePath -Raw -Encoding UTF8
    $targetProfile = $env:USERPROFILE.TrimEnd('\')

    # Use [regex]::Replace rather than the -replace operator: in .NET replacement
    # strings a literal backslash is an escape prefix, so -replace would double
    # every backslash in the target path. Passing the text to the Regex.Replace
    # overload that takes a plain string avoids that interpretation.
        $rewritten = [regex]::Replace($content, [regex]::Escape('C:\Users\DavoodYa'), $targetProfile)

    Write-InstallerFile -Path $OutputPath -Content $rewritten
}

function New-RestartWhkdCmd {
    # The alt+o hotkey needs a single command that stops komorebi and starts it
    # again with --whkd, because whkd 0.2.10 PANICS when one key is bound twice
    # in the same whkdrc (verified against the installed binary) — the two
    # halves cannot be two bindings. This wrapper is written next to the whkdrc
    # that references it, with this machine's komorebic.exe path substituted in.
    param(
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$KomorebicPath
    )

    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        throw "restart-whkd.cmd template missing: $TemplatePath"
    }

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-InstallerDirectory $dir }

    $content = Get-Content -LiteralPath $TemplatePath -Raw -Encoding ASCII
    # Neither operand is a pattern here: the placeholder is a literal token and
    # the path is literal text. Use the Regex.Replace overload with a plain
    # replacement string so backslashes in the path survive verbatim (both
    # [regex]::Escape and the -replace operator would corrupt them).
    $rewritten = [regex]::Replace($content, '__KOMOREBIC_EXE__', $KomorebicPath)

    # CRLF, no BOM: cmd.exe tolerates a BOM on .cmd files but a UTF-8 BOM before
    # @echo off has been known to break older shells, and the file is pure ASCII.
    $enc = New-Object System.Text.UTF8Encoding($false)
    Write-InstallerFile -Path $OutputPath -Content ($rewritten -replace "`r`n|`n", "`r`n")
}

function New-ApplicationsJson {
    # applications.json is copied VERBATIM. The companion file must sit next to
    # the komorebi.json that references it, i.e. in the komorebi config home.
    param([Parameter(Mandatory)][string] $TemplatePath, [Parameter(Mandatory)][string] $OutputPath)

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-InstallerDirectory $dir }
    Copy-InstallerFile -LiteralPath $TemplatePath -Destination $OutputPath -Description "applications.json into the config home"
}

function New-KomorebiResizeJson {
    # Pure runtime state. It is CREATED EMPTY and never shipped with content:
    # whkdrc binds save-resize / load-resize against it, and shipping one
    # machine's resize state would apply it to another machine.
    param([Parameter(Mandatory)][string] $OutputPath)

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-InstallerDirectory $dir }
    Write-InstallerFile -Path $OutputPath -Content ''
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
    if (-not (Test-Path $dir)) { New-InstallerDirectory $dir }

    $content = Get-Content $TemplatePath -Raw -Encoding UTF8
    $pattern = '(?<=powershell -NoProfile -ExecutionPolicy Bypass -File )\\?[^"]*?sensor-color\.ps1'
    # The YAML file stores the path with doubled backslashes, so the replacement
    # text must be escaped the same way. [regex]::Replace with a plain string
    # would treat a lone backslash as an escape prefix; use the MatchEvaluator
    # overload so the replacement is inserted literally.
    $escapedTarget = $SensorScript -replace '\\', '\\'
    $rewritten = [regex]::Replace($content, $pattern, { param($m) $escapedTarget })

    Write-InstallerFile -Path $OutputPath -Content $rewritten
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
        Write-StepOutcome `
            -Dry  ('Komorebi configuration would be generated for {0} monitor(s): {1}.' -f `
            $displays.Count, ($displays -join ', ')) `
            -Real ('Komorebi configuration generated for {0} monitor(s): {1}.' -f `
            $displays.Count, ($displays -join ', '))
    }

    # --- WHKD ----------------------------------------------------------------
    # whkdrc is generated (source paths rewritten to this user's), so compare
    # the RENDERED result rather than the template hash.
    $whkdrcTemplate = Join-Path $template 'whkdrc'
    $targetProfile = $env:USERPROFILE.TrimEnd('\')
        $expectedWhkdrc = [regex]::Replace((Get-Content $whkdrcTemplate -Raw -Encoding UTF8), [regex]::Escape('C:\Users\DavoodYa'), $targetProfile)
    $whkdrcUpToDate = (Test-Path $whkdrc) -and ((Get-Content $whkdrc -Raw -Encoding UTF8) -ceq $expectedWhkdrc)
    if ($whkdrcUpToDate) {
        Write-StepSkipped 'whkdrc is already in place.'
    } else {
        New-Whkdrc -TemplatePath $whkdrcTemplate -OutputPath $whkdrc
        Write-StepOutcome -Dry 'whkdrc would be copied with the target user paths.' -Real 'whkdrc copied with the target user paths.'
    }

    # --- the alt+o restart wrapper ------------------------------------------
    # whkdrc's alt+o binding calls this wrapper, which performs the whkd restart
    # as a single command (whkd 0.2.10 panics on a duplicate binding). The
    # whkdrc path is generated per machine, so the wrapper has to be generated
    # per machine too, with this machine's komorebic.exe substituted in.
    $restartWhkdTemplate = Join-Path $template 'restart-whkd.cmd'
    $restartWhkdPath     = Join-Path $configHome '..\restart-whkd.cmd'
    $komorebic           = Join-Path $env:ProgramFiles 'komorebi\bin\komorebic.exe'
    $expectedWrapper = [regex]::Replace((Get-Content $restartWhkdTemplate -Raw -Encoding ASCII), '__KOMOREBIC_EXE__', $komorebic)
    $wrapperUpToDate = (Test-Path $restartWhkdPath) -and ((Get-Content $restartWhkdPath -Raw -Encoding ASCII) -ceq $expectedWrapper)
    if ($wrapperUpToDate) {
        Write-StepSkipped 'restart-whkd.cmd is already generated for this machine.'
    } else {
        New-RestartWhkdCmd -TemplatePath $restartWhkdTemplate -OutputPath $restartWhkdPath -KomorebicPath $komorebic
        Write-StepOutcome -Dry "restart-whkd.cmd would be generated with this machine's komorebic path." -Real "restart-whkd.cmd generated with this machine's komorebic path."
    }

    # --- applications.json ---------------------------------------------------
    if ((Test-Path $applications) -and ((Get-FileHash $applications -Algorithm SHA256).Hash -eq (Get-FileHash (Join-Path $template 'applications.json') -Algorithm SHA256).Hash)) {
        Write-StepSkipped 'applications.json is already in place.'
    } else {
        New-ApplicationsJson -TemplatePath (Join-Path $template 'applications.json') -OutputPath $applications
        Write-StepOutcome -Dry 'applications.json would be copied.' -Real 'applications.json copied.'
    }

    # --- ASC path sanity (repaired 2026-10-10, finding F3) -------------------
    # komorebi reads the file referenced by app_specific_configuration_path at
    # startup and dies (asc.rs:40) when it is missing — AFTER a "successful"
    # install. komorebic check does not catch that (verified against 0.1.41:
    # it exits 0 with a non-existent ASC file), so the generated config is
    # checked here, while the user is still watching the install.
    if (Test-Path -LiteralPath $komorebiJson) {
        $ascRef = (Get-Content -LiteralPath $komorebiJson -Raw -Encoding UTF8 | ConvertFrom-Json).app_specific_configuration_path
        if ($ascRef) {
            $ascExpanded = [Environment]::ExpandEnvironmentVariables([string]$ascRef).Replace('\\', '\')
            if (-not (Test-Path -LiteralPath $ascExpanded)) {
                Report-InstallerFailure `
                    -Step   'Generate configuration' `
                    -Cause  "app_specific_configuration_path in the generated config points at '$ascExpanded', which does not exist. Komorebi would die reading it on startup." `
                    -Remedy "Repair the path in $komorebiJson by hand, or move applications.json next to it, then re-run this installer."
                throw 'generated komorebi.json references a missing applications.json'
            }
            Write-StepDone ("ASC path resolves to the deployed applications.json ({0})." -f $ascExpanded)
        }
    }

    # --- resize state (created empty, always) --------------------------------
    New-KomorebiResizeJson -OutputPath $resizeState
    if (-not (Test-Path -LiteralPath $resizeState)) {
        # Dry run: the empty state file was never written, so there is nothing
        # to inspect. The real run takes the branch below.
        Write-StepSkipped 'komorebi-resize.json would be created empty (runtime state).'
    } elseif ((Get-Item $resizeState).Length -eq 0) {
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

    # --- whkdrc companion scripts (the whkdrc hotkeys above point at these) ---
    # Three bindings reference scripts that must sit next to the whkdrc itself:
    #   alt + shift + o     -> restart-whkd.cmd   (generated above, ticket 03)
    #   alt + ctrl + t      -> toggle-transparency.ps1
    #   alt + ctrl + shift + r -> safe-restart.ps1
    # These are shipped VERBATIM from scripts\ — they are already portable
    # (ticket 06: they resolve every binary through common.ps1 or $PSScriptRoot)
    # — so a plain copy is byte-identical and idempotent by content hash.
    # safe-restart.ps1 additionally needs to find komorebi-service.ps1, which
    # stays in the repo, so the installer writes the repo path into a marker
    # file next to the copy (see the script's own resolution block).
    # Without these the hotkeys would run a missing file and silently do
    # nothing (same bug class as the source-machine path issue).
    $companions = @(
        @{ Name = 'toggle-transparency.ps1'; Bind = 'alt + ctrl + t';      Marker = $null }
        @{ Name = 'safe-restart.ps1';        Bind = 'alt + ctrl + shift + r'; Marker = 'safe-restart.repo.txt' }
    )
    foreach ($c in $companions) {
        $srcPath  = Join-Path $RepoRoot ('scripts\' + $c.Name)
        $destPath = Join-Path $configHome $c.Name
        if (-not (Test-Path -LiteralPath $srcPath)) {
            Report-InstallerFailure `
                -Step   ('Install the ' + $c.Bind + ' companion script') `
                -Cause  ("The script the whkdrc hotkey {0} calls is missing from the repository: {1}" -f $c.Bind, $srcPath) `
                -Remedy 'Re-clone or re-extract this repository so scripts\ carries the management scripts.'
            throw ("companion script missing: {0}" -f $srcPath)
        }

        $upToDate = (Test-Path -LiteralPath $destPath) -and
            ((Get-FileHash -LiteralPath $destPath -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $srcPath -Algorithm SHA256).Hash)

        # safe-restart.ps1 resolves komorebi-service.ps1 through this marker, so
        # its idempotency check must cover both files.
        $markerPath = $null
        if ($c.Marker) {
            $markerPath = Join-Path $configHome $c.Marker
            $expectedMarker = $RepoRoot.TrimEnd('\')
            $markerOk = (Test-Path -LiteralPath $markerPath) -and
                (((Get-Content -LiteralPath $markerPath -Raw) -replace "`r`n|`n", '').Trim() -ceq $expectedMarker)
            $upToDate = $upToDate -and $markerOk
        }

        if ($upToDate) {
            Write-StepSkipped ('{0} is already in place (the {1} hotkey).' -f $c.Name, $c.Bind)
        } else {
            Copy-InstallerFile -LiteralPath $srcPath -Destination $destPath -Description ("companion script " + $c.Name)
            if ($markerPath) {
                Write-InstallerFile -Path $markerPath -Content ($RepoRoot.TrimEnd('\') + "`r`n")
            }
            Write-StepOutcome -Dry ('{0} would be installed (the {1} hotkey).' -f $c.Name, $c.Bind) -Real ('{0} installed (the {1} hotkey).' -f $c.Name, $c.Bind)
        }
    }

    # --- Validation ----------------------------------------------------------
    if (-not $SkipValidation -and -not (Test-Path -LiteralPath $komorebiJson)) {
        # Dry run: the configuration was not written, so there is no file for
        # komorebic to validate. Say so instead of failing on a missing file.
        Write-StepSkipped 'komorebic check skipped in dry run (the configuration was not written).'
    } elseif (-not $SkipValidation) {
        Write-Step 'Validating the generated configuration'
        $report = Test-GeneratedConfig -Komorebic $komorebic -ConfigPath $komorebiJson
        if ($report) {
            Write-Host ("    {0}" -f ($report -split "`n" | Select-Object -First 6) -join "`n    ") -ForegroundColor DarkGray
        }
        Write-StepDone 'komorebic check passed.'
    }
}

# ===========================================================================
# AutoHotkey startup launcher (ticket 05, ADR-0010)
#
# The three .ahk scripts are shipped in the repo under autohotkey\ and started
# at logon by a generated AppRunner.vbs in the Startup folder. The VBS is
# GENERATED, never copied: its RunHidden lines are rewritten to this machine's
# interpreter paths and this repo's script paths, so no path in the shipped
# file ever references another machine.
#
#   v1 interpreter  C:\Program Files\AutoHotkey\AutoHotkey.exe       -> autocorrect.ahk, ChangeLangF3.ahk
#   v2 interpreter  C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe  -> NewFile.ahk
#
# The scripts are NOT compiled to EXE (ADR-0010: the bundled Ahk2Exe is the
# v1.1.37 compiler and cannot compile the v2 script; manual attempts failed).
# ===========================================================================

# The shipped scripts, in the fixed order the generated VBS emits them.
# Interpreter = 'v1' or 'v2'. Enabled = $true by default; ticket 08's
# enable/disable mechanism flips this and regenerates the VBS, so a disabled
# script is emitted as a commented-out line rather than removed.
$script:AutoHotkeyScripts = @(
    @{ Name = 'autocorrect';    File = 'autocorrect.ahk';    Interpreter = 'v1' }
    @{ Name = 'ChangeLangF3';   File = 'ChangeLangF3.ahk';   Interpreter = 'v1' }
    @{ Name = 'NewFile';        File = 'NewFile.ahk';        Interpreter = 'v2' }
)

function Get-AhkInterpreterPath {
    # Resolves the interpreter for a script's AutoHotkey version to the
    # vendor-default path written by the two committed setups.
    param([Parameter(Mandatory)][ValidateSet('v1','v2')][string]$Version)

    if ($Version -eq 'v1') {
        return (Join-Path $env:ProgramFiles 'AutoHotkey\AutoHotkey.exe')
    }
    return (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe')
}

function Test-AhkInterpreterAvailable {
    # Both interpreters must exist before a single line is generated, otherwise
    # the Startup launcher would point at a non-existent EXE and silently do
    # nothing at every logon.
    param([Parameter(Mandatory)][string]$Version)

    $exe = Get-AhkInterpreterPath -Version $Version
    return (Test-Path -LiteralPath $exe)
}

function Get-AppRunnerTemplate {
    # The shipped template carries the RunHidden/RunNormal helpers and an
    # insertion marker. The installer rewrites only the generated block, so the
    # helpers stay exactly as shipped.
    param([Parameter(Mandatory)][string]$RepoRoot)

    $template = Join-Path $RepoRoot 'autohotkey\AppRunner.vbs'
    if (-not (Test-Path -LiteralPath $template)) {
        Report-InstallerFailure `
            -Step   'Generate AppRunner.vbs' `
            -Cause  "The AppRunner template is missing: $template" `
            -Remedy 'Re-clone or re-extract this repository; autohotkey\AppRunner.vbs is part of it.'
        throw "AppRunner template missing: $template"
    }
    return $template
}

<#
.SYNOPSIS
    The path to the enable/disable state file for the AutoHotkey scripts.

.DESCRIPTION
    One JSON file in the repo's autohotkey\ directory holds which of the three
    shipped scripts are currently enabled. The generated AppRunner.vbs is a
    derived artifact: it is rewritten from this state every time a script is
    toggled, so the VBS is never edited by hand and never drifts. Keeping the
    state in the repo (not in .config) means it travels with the repo and the
    installer's idempotency check sees it on a re-run.
#>
function Get-AhkStateFile {
    param([Parameter(Mandatory)][string]$RepoRoot)
    return (Join-Path $RepoRoot 'autohotkey\ahk-state.json')
}

<#
.SYNOPSIS
    Reads the enable/disable state, layered over the defaults.
#>
function Get-AhkEnabledState {
    param([Parameter(Mandatory)][string]$RepoRoot)

    # Default: everything enabled. Start from the manifest so a state file that
    # predates a newly shipped script does not disable it by absence.
    $state = @{}
    foreach ($script in $script:AutoHotkeyScripts) { $state[$script.Name] = $true }

    $file = Get-AhkStateFile -RepoRoot $RepoRoot
    if (Test-Path -LiteralPath $file) {
        try {
            $saved = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
            # Only names that still exist in the manifest are honoured; a name
            # that was removed from the repo is ignored, not carried forever.
            foreach ($name in $saved.PSObject.Properties.Name) {
                $known = @($script:AutoHotkeyScripts | Where-Object { $_.Name -ieq $name })
                if ($known.Count -eq 1) {
                    $val = $saved.$name
                    if ($val -is [bool]) { $state[$known[0].Name] = $val }
                }
            }
        } catch {
            # A corrupt state file must never break the installer. Fall back to
            # the defaults and note it, so the user still gets a working setup.
            Write-Host '  ahk-state.json could not be read; using defaults (all enabled)' -ForegroundColor Yellow
        }
    }
    return $state
}

<#
.SYNOPSIS
    Writes the enable/disable state and regenerates AppRunner.vbs to match.
#>
function Set-AhkEnabledState {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][hashtable]$State,
        # Internal: used by the test suite to redirect the Startup VBS into a
        # sandbox so a test run never touches the real Startup folder.
        [string] $StartupDirOverride
    )

    $file = Get-AhkStateFile -RepoRoot $RepoRoot
    $dir  = Split-Path $file -Parent
    if (-not (Test-Path $dir)) { New-InstallerDirectory $dir }

    # Write with an ordered object so the file is stable and diffable.
    $ordered = [ordered]@{}
    foreach ($script in $script:AutoHotkeyScripts) {
        $name = $script.Name
        $ordered[$name] = [bool]$State[$name]
    }
    if ($script:DryRun) { Show-DryRunAction ("write " + $file) } else { $ordered | ConvertTo-Json | Set-Content -LiteralPath $file -Encoding UTF8 }

    # Layer the just-written state onto the in-memory manifest BEFORE rendering.
    # Without this the file says one thing and the regenerated VBS keeps every
    # script live: the disable appears to work until the next logon, when
    # everything comes back. ahk-toggle.ps1 depends on this function, and the
    # ticket-08 tests once passed with the state file correct and the generated
    # VBS wrong, because they only round-tripped the file.
    Apply-AhkEnabledState -RepoRoot $RepoRoot

    # Regenerate the Startup VBS so the change takes effect at the next logon.
    $template = Get-AppRunnerTemplate -RepoRoot $RepoRoot
    if ($StartupDirOverride) {
        $output = Join-Path $StartupDirOverride 'AppRunner.vbs'
    } else {
        $output = Join-Path ([Environment]::GetFolderPath('Startup')) 'AppRunner.vbs'
    }
    $ahkDir   = Join-Path $RepoRoot 'autohotkey'
    New-AppRunnerVbs -TemplatePath $template -OutputPath $output -AhkDir $ahkDir
}

<#
.SYNOPSIS
    Copies the persisted state onto the in-memory manifest so the VBS
    generator sees the current Enabled flags.
#>
function Apply-AhkEnabledState {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $state = Get-AhkEnabledState -RepoRoot $RepoRoot
    for ($i = 0; $i -lt $script:AutoHotkeyScripts.Count; $i++) {
        $name = $script:AutoHotkeyScripts[$i].Name
        if ($state.ContainsKey($name)) {
            $script:AutoHotkeyScripts[$i]['Enabled'] = [bool]$state[$name]
        }
    }
}

function Test-AppRunnerUpToDate {
    # True when the Startup copy already holds exactly the lines this machine
    # and this repo produce, so a re-run regenerates nothing. This compares the
    # rendered result, not a template hash: the generated content depends on
    # both the repo path and the installed interpreters.
    param(
        [Parameter(Mandatory)][string]   $TemplatePath,
        [Parameter(Mandatory)][string]   $OutputPath,
        [Parameter(Mandatory)][string]   $AhkDir
    )

    if (-not (Test-Path -LiteralPath $OutputPath)) { return $false }
    $expected = Get-GeneratedAppRunnerContent -TemplatePath $TemplatePath -AhkDir $AhkDir
    $actual = [System.IO.File]::ReadAllText($OutputPath)
    return ($actual -ceq $expected)
}

function Get-GeneratedAppRunnerContent {
    # Renders the final VBS text: the shipped template with one RunHidden line
    # per enabled script inserted at the marker, each pointing at the right
    # interpreter and the repo-relative script path.
    param(
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][string]$AhkDir
    )

    $template = Get-Content -LiteralPath $TemplatePath -Raw

    $lines = @()
    foreach ($script in $script:AutoHotkeyScripts) {
        $interpreter = Get-AhkInterpreterPath -Version $script.Interpreter
        $scriptPath  = Join-Path $AhkDir $script.File
        # VBScript escaping: the whole command is ONE VBS string, so each path
        # is quoted with "" (an escaped quote) inside it, and the trailing """
        # closes the string. Both paths are quoted because the repository path
        # can contain spaces; a bare unquoted path would break the Run call.
        $run = 'RunHidden """{0}"" ""{1}"""' -f $interpreter, $scriptPath

        # A disabled script is emitted as a COMMENTED-OUT line, not omitted.
        # That keeps the script's position in the file stable across
        # enable/disable cycles and shows the user at a glance what is off.
        # The comment marker is the script's Name so the enable/disable
        # machinery can find its own line back without parsing quotes.
        $isEnabled = $true
        if ($script.ContainsKey('Enabled')) { $isEnabled = [bool]$script.Enabled }
        if ($isEnabled) {
            $lines += $run
        } else {
            $lines += "' [disabled:{0}] {1}" -f $script.Name, $run
        }
    }

    # Insert the generated block at the marker line. The marker is replaced
    # wholesale, so regenerating after a ticket-08 enable/disable change
    # produces a clean block with no leftover lines.
    $markerLine = "' AppRunnerEnd"
    $block = ($lines -join "`r`n")
    $template = $template -replace [regex]::Escape($markerLine), $block
    return $template
}

function New-AppRunnerVbs {
    # Writes the generated VBS to the Startup folder. The file is CRLF with no
    # BOM: VBScript parses either, but the shipped template is CRLF and a BOM
    # on a .vbs file can break the wscript host on older builds.
    param(
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$AhkDir
    )

    $content = Get-GeneratedAppRunnerContent -TemplatePath $TemplatePath -AhkDir $AhkDir

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-InstallerDirectory $dir }

    # UTF8 without a BOM, CRLF. VBScript parses either line ending, but the
    # shipped template is CRLF and staying byte-identical to it keeps the
    # idempotency comparison exact. The write goes through the guarded helper
    # (same UTF8-no-BOM encoding), so a dry run prints the intention instead of
    # overwriting the real Startup folder.
    Write-InstallerFile -Path $OutputPath -Content $content -Description 'AppRunner.vbs into the Startup folder'
}

function Install-AutoHotkeyStartup {
    # The ticket 05 entry point. Installs the three scripts and generates the
    # startup launcher. Idempotent: a re-run regenerates the VBS only when its
    # rendered content would change.
    param([Parameter(Mandatory)][string]$RepoRoot)

    Write-Step 'Setting up the AutoHotkey startup launcher'

    # --- preconditions -------------------------------------------------------
    $missing = @()
    foreach ($version in 'v1','v2') {
        if (-not (Test-AhkInterpreterAvailable -Version $version)) {
            $missing += (Get-AhkInterpreterPath -Version $version)
        }
    }
    if ($missing.Count -gt 0) {
        $list = ($missing -join "`n    ")
        Report-InstallerFailure `
            -Step   'Generate AppRunner.vbs' `
            -Cause  "The AutoHotkey interpreter(s) are not installed:`n    $list" `
            -Remedy 'The AutoHotkey install steps run before this one. If they were skipped as already-installed but the interpreters are absent, install AutoHotkey v1 and v2 manually first.'
        throw 'AutoHotkey interpreters are required before the startup launcher can be generated'
    }

    # --- the scripts must be present in the repo -----------------------------
    $ahkDir = Join-Path $RepoRoot 'autohotkey'
    $missingScripts = @($script:AutoHotkeyScripts | Where-Object { -not (Test-Path -LiteralPath (Join-Path $ahkDir $_.File)) })
    if ($missingScripts.Count -gt 0) {
        $list = (($missingScripts | ForEach-Object { $_.File }) -join "`n    ")
        Report-InstallerFailure `
            -Step   'Generate AppRunner.vbs' `
            -Cause  "The AutoHotkey script(s) are missing from the repository:`n    $list" `
            -Remedy 'Re-clone or re-extract this repository so autohotkey\ contains all three scripts.'
        throw 'AutoHotkey scripts are missing from the repository'
    }

    # Layer the persisted enable/disable state onto the manifest BEFORE the VBS
    # is rendered, so a re-install preserves what the user toggled off. Without
    # this the installer would silently re-enable everything.
    Apply-AhkEnabledState -RepoRoot $RepoRoot

    # --- generate the startup launcher ---------------------------------------
    $template = Get-AppRunnerTemplate -RepoRoot $RepoRoot
    $startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
    $outputPath = Join-Path $startupDir 'AppRunner.vbs'

    if (Test-AppRunnerUpToDate -TemplatePath $template -OutputPath $outputPath -AhkDir $ahkDir) {
        Write-StepSkipped 'AppRunner.vbs is already generated for this machine and repository.'
    } else {
        New-AppRunnerVbs -TemplatePath $template -OutputPath $outputPath -AhkDir $ahkDir
        Write-StepOutcome -Dry 'AppRunner.vbs would be generated in the Startup folder.' -Real 'AppRunner.vbs generated in the Startup folder.'
    }

    # --- verify the result ---------------------------------------------------
    if ($script:DryRun) {
        # Dry run: the file was not written, so there is nothing to read back.
        # The real run performs the full reference check below.
        Show-DryRunAction 'verify the generated AppRunner.vbs references every shipped script and interpreter'
        return
    }
    if (-not (Test-Path -LiteralPath $outputPath)) {
        throw "AppRunner.vbs was not written to '$outputPath'."
    }

    $generated = Get-Content -LiteralPath $outputPath -Raw
    foreach ($script in $script:AutoHotkeyScripts) {
        $needle = (Join-Path $ahkDir $script.File)
        if ($generated -notlike "*$needle*") {
            throw "AppRunner.vbs does not reference $($script.File)."
        }
    }

    # Nothing in the generated file may reference a path that does not exist on
    # this machine: a stale AppRunner.vbs from another install would silently
    # run nothing at every logon.
    foreach ($script in $script:AutoHotkeyScripts) {
        $interpreter = Get-AhkInterpreterPath -Version $script.Interpreter
        if ($generated -notlike "*$interpreter*") {
            throw "AppRunner.vbs does not use the $($script.Interpreter) interpreter for $($script.File)."
        }
    }
}

# ===========================================================================
# Startup machinery (ticket 04, ADR-0002 + ADR-0016)
#
# Registers the two scheduled tasks and YASB autostart so the whole environment
# comes back on logon and self-heals. The two invariants that must never regress
# are the watchdog mutex (Global\komorebi-service-start) and the redirection of
# BOTH stdout and stderr of komorebi/whkd — both live in komorebi-service.ps1
# and are reproduced unconditionally here.
#
#   Komorebi          logon trigger (delayed 25s) -> komorebic start --whkd
#   KomorebiWatchdog  every 5 minutes             -> komorebi-service.ps1 -Action watchdog
#   YASB              yasbc enable-autostart (writes HKCU\...\Run)
#
# BOTH tasks are registered -RunLevel Highest. Without it, applications launched
# as Administrator are silently unmanageable (UIPI), and the watchdog must be
# Highest too or a respawned Komorebi silently drops back to Medium integrity
# after the first watchdog restart (ADR-0016).
# ===========================================================================

$script:TaskName      = 'Komorebi'
$script:WatchTaskName = 'KomorebiWatchdog'
$script:WatchdogMinutes = 5

function Get-KomorebiScheduledTask {
    param([Parameter(Mandatory)][string] $Name)
    return (Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue)
}

function Test-ScheduledTaskRunLevelHighest {
    # ADR-0016: this is a correctness requirement, not a preference. A task
    # registered without Highest silently fails to manage elevated windows.
    param([Parameter(Mandatory)][string] $Name)

    $task = Get-KomorebiScheduledTask -Name $Name
    if (-not $task) { return $false }
    return ($task.Principal.RunLevel -eq [Microsoft.PowerShell.Cmdletization.GeneratedTypes.ScheduledTask.RunLevelEnum]::Highest)
}

function Get-KomorebicPath {
    # komorebic must be resolvable by bare name before YASB launches: YASB reads
    # PATH once at launch and never re-reads it, so a bar that started before the
    # PATH entry exists stays dead until it is restarted.
    $kb = Join-Path $env:ProgramFiles 'komorebi\bin\komorebic.exe'
    if (Test-Path $kb) { return $kb }
    return $null
}

function Test-KomorebicOnPath {
    # True when komorebic.exe resolves from the machine PATH. The MSIs add this
    # entry, but a machine that had komorebi installed under a different path, or
    # whose PATH was rebuilt, can end up without it.
    $cmd = Get-Command komorebic.exe -ErrorAction SilentlyContinue
    return [bool]$cmd
}

function Add-KomorebicToPath {
    # Idempotent: only appends when the entry is genuinely absent, and never
    # duplicates an existing entry pointing at the same directory.
    param([Parameter(Mandatory)][string] $KomorebicPath)

    $dir = Split-Path $KomorebicPath -Parent
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $entries = if ($machinePath) { $machinePath.Split(';') } else { @() }
    $already = $entries | Where-Object { $_ -and ($_.TrimEnd('\') -ieq $dir.TrimEnd('\')) }
    if ($already) { return $false }

    $newPath = if ($machinePath) { "$machinePath;$dir" } else { $dir }
    if ($script:DryRun) { Show-DryRunAction ("append " + $dir + " to the machine PATH") } else { [Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine') }
    $env:Path = "$env:Path;$dir"
    return $true
}

function New-WatchdogLauncher {
    # Task Scheduler creates a console for powershell.exe and only hides it
    # afterwards, so a watchdog task pointed straight at powershell.exe flashes a
    # console window every interval. Compiling this as a GUI-subsystem app means
    # Windows never allocates it a console at all. It forwards every argument to
    # the real powershell.exe and waits, so the watchdog logic is untouched.
    param([Parameter(Mandatory)][string] $RepoRoot)

    $cs  = Join-Path $RepoRoot 'scripts\komorebi-watchdog.cs'
    $exeDir = Join-Path $env:USERPROFILE 'bin'
    $exe = Join-Path $exeDir 'komorebi-watchdog.exe'
    $csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'

    if (-not (Test-Path $cs))  { return $null }
    if (-not (Test-Path $csc)) { return $null }

    if (-not (Test-Path $exeDir)) { New-InstallerDirectory $exeDir }

    if ($script:DryRun) {
        Show-DryRunAction ("compile the windowless watchdog launcher: " + $exe)
        return $exe
    }
    & $csc /nologo /target:winexe /optimize+ "/out:$exe" $cs 2>&1 | Out-Null
    if (-not (Test-Path $exe)) { return $null }

    # Verify the produced binary really is GUI-subsystem (PE header subsystem = 2).
    # If it came out as a console app it would still flash, so drop it and let the
    # caller fall back to powershell.exe rather than ship a blinking task.
    $bytes = [System.IO.File]::ReadAllBytes($exe)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    $subsystem = [BitConverter]::ToUInt16($bytes, $peOffset + 0x5c)
    if ($subsystem -ne 2) {
        Remove-Item $exe -Force -ErrorAction SilentlyContinue
        return $null
    }
    return $exe
}

function Remove-LegacyStartupShortcut {
    # An old Startup-folder komorebi.lnk races the scheduled task and can start a
    # second komorebi against the same socket. It is removed unconditionally.
    $lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\komorebi.lnk'
    if (Test-Path $lnk) {
        Invoke-InstallerAction ("remove the legacy Startup shortcut " + $lnk) {
            Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue
        }
        return $true
    }
    return $false
}

function Register-KomorebiLogonTask {
    # The logon task. Created only when absent, always at RunLevel Highest.
    param([Parameter(Mandatory)][string] $KomorebicPath)

    $taskAction = New-ScheduledTaskAction -Execute $KomorebicPath -Argument 'start --whkd'
    # The 25s delay lets the taskbar and YASB settle first; starting komorebi
    # before the shell is fully up can leave the bar without a tray icon.
    $taskTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $taskTrigger.Delay = 'PT25S'

    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
        -LogonType Interactive -RunLevel Highest
    $taskSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -StartWhenAvailable

    Invoke-InstallerAction ("register the scheduled task " + $script:TaskName) {
        Register-ScheduledTask -TaskName $script:TaskName `
            -Action $taskAction -Trigger $taskTrigger `
            -Principal $principal -Settings $taskSettings `
            -Description 'komorebi window manager with whkd hotkeys' -Force | Out-Null
    }
}

function Register-KomorebiWatchdogTask {
    # The self-healing task. Same principal/settings as the logon task (so also
    # Highest), repeating every $script:WatchdogMinutes, invoking the watchdog
    # action of komorebi-service.ps1 through the windowless launcher.
    param(
        [Parameter(Mandatory)][string] $ServiceScript,
        [Parameter(Mandatory)][string] $WatchdogExe
    )

    $args = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Action watchdog -WatchdogMinutes {1}' -f `
        $ServiceScript, $script:WatchdogMinutes

    if ($WatchdogExe) {
        $taskAction = New-ScheduledTaskAction -Execute $WatchdogExe -Argument $args
    } else {
        # No GUI launcher available: fall back to powershell.exe. This still
        # works, it just flashes a console once per interval.
        $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument ("-WindowStyle Hidden " + $args)
    }

    $taskTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) `
        -RepetitionInterval (New-TimeSpan -Minutes $script:WatchdogMinutes) `
        -RepetitionDuration (New-TimeSpan -Days 3650)

    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
        -LogonType Interactive -RunLevel Highest
    $taskSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -StartWhenAvailable

    Invoke-InstallerAction ("register the scheduled task " + $script:WatchTaskName) {
        Register-ScheduledTask -TaskName $script:WatchTaskName `
            -Action $taskAction -Trigger $taskTrigger `
            -Principal $principal -Settings $taskSettings `
            -Description 'restarts komorebi only if the WM has died' -Force | Out-Null
    }
}

function Enable-YasbAutostart {
    # YASB's own mechanism: no Admin needed, idempotent, and if YASB ever changes
    # how it autostarts we follow it for free instead of maintaining a hand-rolled
    # Run key that drifts (ADR-0002).
    $yasbc = Get-Command yasbc -ErrorAction SilentlyContinue
    if (-not $yasbc) { return $false }
    Invoke-InstallerAction "enable YASB autostart (yasbc enable-autostart)" { & $yasbc.Source enable-autostart 2>&1 | Out-Null }
    return $true
}

function New-YasbAutostartFallback {
    # Used only when yasbc enable-autostart does not work. YASB resolves
    # komorebic.exe from PATH at launch, so this must run after the PATH step.
    param([Parameter(Mandatory)][string] $YasbExe)

    $startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
    if (-not (Test-Path $startupDir)) { New-InstallerDirectory $startupDir }
    $lnk = Join-Path $startupDir 'YASB.lnk'

    Invoke-InstallerAction ("create the YASB Startup shortcut " + $lnk) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($lnk)
        $shortcut.TargetPath = $YasbExe
        $shortcut.WindowStyle = 7   # minimized; the bar is a windowless app anyway
        $shortcut.Description = 'YASB status bar'
        $shortcut.Save()
    }
    return $true
}

function Test-YasbAutostartEnabled {
    # The primary mechanism writes HKCU\...\Run; the fallback writes a Startup
    # shortcut. Either counts as autostart being enabled.
    $runKey = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
    if ($runKey) {
        $hasRunEntry = $runKey.PSObject.Properties | Where-Object {
            $_.Value -and ($_.Value -match 'yasb\.exe')
        }
        if ($hasRunEntry) { return $true }
    }
    return (Test-Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\YASB.lnk'))
}

function Install-StartupTasks {
    # The ticket 04 entry point. Registers the two scheduled tasks and YASB
    # autostart, then verifies all three. Idempotent: re-running leaves exactly
    # the same state.
    param([Parameter(Mandatory)][string] $RepoRoot)

    Write-Step 'Setting up startup tasks'

    # --- PATH must be right before anything launches -------------------------
    $komorebic = Get-KomorebicPath
    if (-not $komorebic) {
        throw "komorebic.exe not found at '$(Join-Path $env:ProgramFiles 'komorebi\bin\komorebic.exe')'. Install the binaries before setting up startup."
    }
    if (Test-KomorebicOnPath) {
        Write-StepSkipped 'komorebic.exe is already on the machine PATH.'
    } else {
        Add-KomorebicToPath -KomorebicPath $komorebic | Out-Null
        Write-StepDone 'Added komorebic.exe to the machine PATH.'
    }

    # --- the old racing Startup shortcut goes first --------------------------
    if (Remove-LegacyStartupShortcut) {
        Write-StepDone 'Removed the legacy Startup shortcut (it would race the logon task).'
    }

    # --- the windowless watchdog launcher ------------------------------------
    $watchdogExe = New-WatchdogLauncher -RepoRoot $RepoRoot
    if ($watchdogExe) {
        if ($script:DryRun) {
            Write-StepSkipped 'Windowless watchdog launcher would be compiled (no console flash).'
        } else {
            Write-StepDone 'Built the windowless watchdog launcher (no console flash).'
        }
    } else {
        Write-StepSkipped 'Watchdog launcher unavailable; the watchdog task will use powershell.exe.'
    }

    $serviceScript = Join-Path $RepoRoot 'scripts\komorebi-service.ps1'
    if (-not (Test-Path $serviceScript)) {
        throw "komorebi-service.ps1 not found at '$serviceScript'."
    }

    # --- the logon task ------------------------------------------------------
    if (Test-ScheduledTaskRunLevelHighest -Name $script:TaskName) {
        Write-StepSkipped "Scheduled task '$($script:TaskName)' is already registered at RunLevel Highest."
    } else {
        Register-KomorebiLogonTask -KomorebicPath $komorebic
        if (-not $script:DryRun -and -not (Test-ScheduledTaskRunLevelHighest -Name $script:TaskName)) {
            throw "Scheduled task '$($script:TaskName)' was registered but is not at RunLevel Highest. Elevated windows would be unmanageable."
        }
        if ($script:DryRun) {
            Write-StepSkipped "Scheduled task '$($script:TaskName)' would be registered (logon, RunLevel Highest)."
        } else {
            Write-StepDone "Scheduled task '$($script:TaskName)' registered (logon, RunLevel Highest)."
        }
    }

    # --- the watchdog task ---------------------------------------------------
    if (Test-ScheduledTaskRunLevelHighest -Name $script:WatchTaskName) {
        Write-StepSkipped "Scheduled task '$($script:WatchTaskName)' is already registered at RunLevel Highest."
    } else {
        Register-KomorebiWatchdogTask -ServiceScript $serviceScript -WatchdogExe $watchdogExe
        if (-not $script:DryRun -and -not (Test-ScheduledTaskRunLevelHighest -Name $script:WatchTaskName)) {
            throw "Scheduled task '$($script:WatchTaskName)' was registered but is not at RunLevel Highest. A respawned Komorebi would silently drop to Medium integrity."
        }
        if ($script:DryRun) {
            Write-StepSkipped "Scheduled task '$($script:WatchTaskName)' would be registered (every $($script:WatchdogMinutes) min, RunLevel Highest)."
        } else {
            Write-StepDone "Scheduled task '$($script:WatchTaskName)' registered (every $($script:WatchdogMinutes) min, RunLevel Highest)."
        }
    }

    # --- YASB autostart ------------------------------------------------------
    $yasbExe = Join-Path $env:ProgramFiles 'YASB\yasb.exe'
    if (Test-YasbAutostartEnabled) {
        Write-StepSkipped 'YASB autostart is already enabled.'
    } elseif (Enable-YasbAutostart) {
        if (Test-YasbAutostartEnabled) {
            if ($script:DryRun) {
            Write-StepSkipped 'YASB autostart would be enabled via yasbc enable-autostart.'
        } else {
            Write-StepDone 'YASB autostart enabled via yasbc enable-autostart.'
        }
        } else {
            # The primary mechanism reported success but did not take effect.
            # Use the fallback rather than declare autostart done.
            New-YasbAutostartFallback -YasbExe $yasbExe | Out-Null
            if ($script:DryRun) {
            Write-StepSkipped 'YASB autostart would be enabled via the Startup-folder fallback.'
        } else {
            Write-StepDone 'YASB autostart enabled via the Startup-folder fallback.'
        }
        }
    } elseif (Test-Path $yasbExe) {
        New-YasbAutostartFallback -YasbExe $yasbExe | Out-Null
        if ($script:DryRun) {
            Write-StepSkipped 'YASB autostart would be enabled via the Startup-folder fallback.'
        } else {
            Write-StepDone 'YASB autostart enabled via the Startup-folder fallback.'
        }
    } else {
        throw 'YASB is not installed, so its autostart cannot be set up.'
    }
}
