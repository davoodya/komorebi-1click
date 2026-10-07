#Requires -Version 5.1
<#
.SYNOPSIS
    Adds a komorebi ignore rule for KomorebiDashboard.exe, so komorebi stops
    managing the Dashboard's window.

.DESCRIPTION
    WHY THIS EXISTS
      On a multi-monitor desk komorebi mis-handles some standard WPF windows:
      the window is placed on one monitor and then dragged/retiled as if it
      belonged to another, so it appears to "cross the monitor boundary" and
      cannot be parked where the user put it. This Dashboard is a plain WPF
      window and is affected.

      It is a komorebi bug rather than a Dashboard bug, and it is not specific to
      this app -- ncpa.cpl, Device Manager and Disk Management are already
      ignored in the shipped configuration for exactly this reason. The same
      remedy applies here: a real ignore rule in komorebi.json.

    WHY AN IGNORE RULE AND NOT manage_rules
      komorebi evaluates BOTH lists and the override wins. In v0.1.41
      (komorebi/src/window.rs, window_is_eligible):

          if should_ignore && !managed_override { return false; }

      So an ignore rule does nothing if any manage_rules entry also matches the
      window. This script therefore also reports a conflicting force-manage rule
      if one is present -- silently writing an ineffective rule would look like
      success and change nothing.

    WHAT IT CHANGES
      <komorebi config home>\komorebi.json, ONE entry added to `ignore_rules`:

          { "kind": "Exe", "id": "KomorebiDashboard.exe", "matching_strategy": "Equals" }

      Matched on the executable rather than on the window title: the Dashboard
      window title is "Komorebi Admin Dashboard", and an exe rule is unaffected
      by any future title change.

      Idempotent -- the rule is recognised however it was spelled, so running
      this twice does not append a duplicate.

    WHERE THE CONFIG LIVES
      The live config home is reported by `komorebic check`. A copy of
      komorebi.json also lives in this repository, and komorebi's own
      `app_specific_configuration_path` mechanism is what relates the two.
      This script edits the LIVE file only: that is the one komorebi reads at
      run time, and the repository copy is the installer's template rather than
      a second live configuration.

.PARAMETER DryRun
    Report what would change, write nothing. Use this to inspect the decision on
    any machine before mutating a config.
.PARAMETER NoReload
    Skip the `komorebic reload-configuration` call. Used by the tests, which must
    not disturb a running window manager.
.PARAMETER KomorebiConfigPath
    Explicit path to komorebi.json. Intended for the tests, so they can operate
    on a file in a temp directory instead of the live configuration.

.OUTPUTS
    Exit code 0 when the rule is present afterwards (or would be, under -DryRun).
    1 on a failure that left the configuration unchanged. 2 on an invalid
    configuration, which is deliberately NOT rewritten.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\ignore-dashboard.ps1 -DryRun

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\ignore-dashboard.ps1
#>

[CmdletBinding()]
param(
    [switch] $DryRun,
    [switch] $NoReload,
    [string] $KomorebiConfigPath
)

$ErrorActionPreference = 'Stop'

# The exe name komorebi matches against. A rule that names a different file is
# a rule that never fires, so the one place it is written down is here.
$ExeName = 'KomorebiDashboard.exe'

# The Dashboard is a WPF window; `komorebic check` is komorebi's own config
# validator, and reload-configuration is what applies a change without a restart.
$KomorebicExe = 'komorebic'

function Write-Step  ([string]$m) { Write-Host "[ignore-dashboard] $m" -ForegroundColor Cyan }
function Write-Detail([string]$m) { Write-Host "  $m" -ForegroundColor DarkGray }

function Resolve-Komorebic {
    $cmd = Get-Command $KomorebicExe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # An elevated logon task puts komorebi's directory on PATH for the task only,
    # so a shell here may not see it. Look in the conventional install location
    # before giving up: the rule is still worth writing without the reload.
    foreach ($p in @(
        (Join-Path $env:USERPROFILE 'scoop\shims\komorebic.exe'),
        (Join-Path $env:USERPROFILE '.cargo\bin\komorebic.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\komorebi\komorebic.exe')
    )) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Resolve-KomorebiConfig([string]$Override) {
    if ($Override) { return $Override }

    # The authoritative answer: komorebi reports the config home it actually
    # uses, which respects a non-default KOMOREBI_CONFIG_HOME. Parsing
    # `komorebic check` is therefore better than assuming %USERPROFILE%.
    $komorebic = Resolve-Komorebic
    if ($komorebic) {
        try {
            $check = & $komorebic check 2>&1 | Out-String
            # komorebic annotates the home as `(<path>)` on its status lines.
            $m = [regex]::Match($check, '\((?<p>[A-Za-z]:\\[^)]*)\)')
            if ($m.Success -and (Test-Path -LiteralPath $m.Groups['p'].Value)) {
                $fromCheck = Join-Path $m.Groups['p'].Value 'komorebi.json'
                if (Test-Path -LiteralPath $fromCheck) { return $fromCheck }
            }
        } catch {
            Write-Detail "could not ask komorebic for its config home ($($_.Exception.Message))"
        }
    }

    $envHome = $env:KOMOREBI_CONFIG_HOME
    if ($envHome -and (Test-Path -LiteralPath (Join-Path $envHome 'komorebi.json'))) {
        return Join-Path $envHome 'komorebi.json'
    }

    return Join-Path $env:USERPROFILE 'komorebi.json'
}

# ---------------------------------------------------------------------------
# A rule is identified by its kind and id, NOT by string equality with the exact
# JSON we would write. A rule written by hand may omit matching_strategy, or use
# a different one, and appending a second entry would leave two rules for the
# same window: harmless to komorebi, but it makes "did this script run?" and
# "remove the rule later" both ambiguous.
# ---------------------------------------------------------------------------
function Test-RuleMatches([object]$Rule, [string]$Id) {
    if ($null -eq $Rule) { return $false }

    $kind = [string]$Rule.kind
    $rid  = [string]$Rule.id
    if ([string]::IsNullOrWhiteSpace($kind) -or [string]::IsNullOrWhiteSpace($rid)) { return $false }
    if ($kind -ne 'Exe') { return $false }

    $strategy = [string]$Rule.matching_strategy
    if ([string]::IsNullOrWhiteSpace($strategy)) { $strategy = 'Equals' }

    if ($strategy -eq 'Equals') {
        return [string]::Equals($rid, $Id, [System.StringComparison]::OrdinalIgnoreCase)
    }
    if ($strategy -eq 'Regex') {
        try { return [regex]::IsMatch($Id, $rid, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
        catch { return $false }
    }
    return $false
}

# ---------------------------------------------------------------------------
Write-Step "target: $ExeName"

$configPath = Resolve-KomorebiConfig $KomorebiConfigPath
Write-Step "komorebi config: $configPath"

if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Host "[ignore-dashboard] FAILED: komorebi.json not found at $configPath" -ForegroundColor Red
    Write-Host "  Pass -KomorebiConfigPath, or run this on a machine where komorebi is installed." -ForegroundColor Red
    exit 1
}

# Read and parse BEFORE any write decision. A file that does not parse is left
# exactly as it is: komorebi's config is not this script's to repair, and a
# partial rewrite of an unreadable file would destroy the user's settings.
try {
    $raw = Get-Content -LiteralPath $configPath -Raw
    $config = $raw | ConvertFrom-Json
}
catch {
    Write-Host "[ignore-dashboard] FAILED: komorebi.json is not valid JSON - nothing was written." -ForegroundColor Red
    Write-Detail $_.Exception.Message
    exit 2
}

if ($null -eq $config) {
    Write-Host "[ignore-dashboard] FAILED: komorebi.json parsed to null - nothing was written." -ForegroundColor Red
    exit 2
}

# ---------------------------------------------------------------------------
# Conflicting force-manage rule. This is the check that makes the output honest:
# with a matching manage_rules entry, the ignore rule below has NO effect, and
# reporting success without saying so would be a lie the user cannot see.
# ---------------------------------------------------------------------------
$conflict = $null
if ($null -ne $config.manage_rules) {
    foreach ($r in @($config.manage_rules)) {
        if (Test-RuleMatches $r $ExeName) { $conflict = $r; break }
    }
}

# ---------------------------------------------------------------------------
$alreadyIgnored = $false
if ($null -ne $config.ignore_rules) {
    foreach ($r in @($config.ignore_rules)) {
        if (Test-RuleMatches $r $ExeName) { $alreadyIgnored = $true; break }
    }
}

if ($alreadyIgnored) {
    Write-Host "[ignore-dashboard] OK: $ExeName is already ignored by komorebi." -ForegroundColor Green
} else {
    Write-Step "adding ignore rule for $ExeName"

    $newRule = [pscustomobject]@{
        kind              = 'Exe'
        id                = $ExeName
        matching_strategy = 'Equals'
    }

    # @() around the read: a single-entry array comes back from ConvertFrom-Json
    # as a scalar, and appending to a scalar is how a one-rule list is replaced
    # by a two-property object.
    $rules = @()
    if ($null -ne $config.ignore_rules) { $rules += @($config.ignore_rules) }
    $rules += $newRule

    # Depth 32 rather than the default 2. komorebi.json nests monitor and
    # workspace objects several levels deep, and at depth 2 ConvertTo-Json
    # silently replaces everything deeper with its type name - which would
    # corrupt every monitor definition in the file.
    #
    # The property may not exist: `ignore_rules` is nullable in komorebi's own
    # schema, so a hand-written or minimal config can legitimately omit it.
    # Assigning to a missing property on a PSCustomObject throws
    # ("cannot be found on this object"), which is why the branch below adds it
    # instead of assigning. A config with no ignore_rules is exactly the case
    # where this rule matters most, so failing there would be the worst outcome.
    if ($config.PSObject.Properties.Name -contains 'ignore_rules') {
        $config.ignore_rules = $rules
    } else {
        $config | Add-Member -NotePropertyName 'ignore_rules' -NotePropertyValue $rules -Force
    }

    $json = $config | ConvertTo-Json -Depth 32
}

if ($DryRun) {
    Write-Step 'DRY RUN - no file was written.'
    if ($alreadyIgnored) { Write-Host '  would change: nothing (rule already present)' }
    else {
        Write-Host '  would add to ignore_rules:'
        Write-Host "    { kind: 'Exe', id: '$ExeName', matching_strategy: 'Equals' }"
    }
} else {
    if (-not $alreadyIgnored) {
        try {
            # temp-then-replace: a crash mid-write would otherwise leave a
            # truncated komorebi.json, which komorebi refuses to load at all.
            $temp = "$configPath.tmp"
            Set-Content -LiteralPath $temp -Value $json -Encoding UTF8
            Move-Item -LiteralPath $temp -Destination $configPath -Force
            Write-Host "[ignore-dashboard] OK: ignore rule written to $configPath" -ForegroundColor Green
        }
        catch {
            Write-Host "[ignore-dashboard] FAILED: could not write $configPath" -ForegroundColor Red
            Write-Detail $_.Exception.Message
            exit 1
        }
    }
}

# ---------------------------------------------------------------------------
# Read the file back. A script that reports success because its own write call
# did not throw has not verified anything: the rule has to be in the file.
# ---------------------------------------------------------------------------
if (-not $DryRun) {
    try {
        $verify = (Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json)
        $present = $false
        if ($null -ne $verify.ignore_rules) {
            foreach ($r in @($verify.ignore_rules)) {
                if (Test-RuleMatches $r $ExeName) { $present = $true; break }
            }
        }
        if ($present) { Write-Host "[ignore-dashboard] verified: the rule is present in the saved file." -ForegroundColor Green }
        else {
            Write-Host '[ignore-dashboard] FAILED: the saved file does not contain the rule.' -ForegroundColor Red
            exit 1
        }
    }
    catch {
        Write-Host '[ignore-dashboard] FAILED: the saved file could not be re-read.' -ForegroundColor Red
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Apply without a restart. Without this the rule only takes effect the next time
# komorebi starts, which for a user pressing a button in the Dashboard is
# indistinguishable from the feature not working.
# ---------------------------------------------------------------------------
if (-not $DryRun -and -not $NoReload) {
    $komorebic = Resolve-Komorebic
    if ($komorebic) {
        try {
            $out = & $komorebic reload-configuration 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                Write-Host '[ignore-dashboard] komorebi reloaded its configuration.' -ForegroundColor Green
            } else {
                # Not a failure of the rule: the config is correct on disk and
                # will apply at the next start. Say so rather than exiting 1 and
                # implying the write did not happen.
                Write-Host '[ignore-dashboard] NOTE: komorebi did not reload automatically.' -ForegroundColor Yellow
                Write-Host "  The rule is saved and will apply the next time komorebi starts." -ForegroundColor Yellow
                Write-Detail ($out.Trim())
                exit 3
            }
        }
        catch {
            Write-Host '[ignore-dashboard] NOTE: could not run komorebic reload-configuration.' -ForegroundColor Yellow
            Write-Host '  The rule is saved and will apply the next time komorebi starts.' -ForegroundColor Yellow
            exit 3
        }
    } else {
        Write-Host '[ignore-dashboard] NOTE: komorebic was not found on PATH; skipping the reload.' -ForegroundColor Yellow
        Write-Host '  The rule is saved and will apply the next time komorebi starts.' -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
if ($null -ne $conflict) {
    Write-Host '[ignore-dashboard] WARNING: a komorebi manage_rules entry also matches this exe.' -ForegroundColor Yellow
    Write-Host '  komorebi gives force-manage precedence over ignore, so the rule will NOT take effect' -ForegroundColor Yellow
    Write-Host '  until that entry is removed. Conflicting rule:' -ForegroundColor Yellow
    Write-Host ("    " + ($conflict | ConvertTo-Json -Compress -Depth 4)) -ForegroundColor Yellow
}

Write-Host '[ignore-dashboard] done.' -ForegroundColor Green
exit 0