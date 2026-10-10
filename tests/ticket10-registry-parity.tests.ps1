#Requires -Version 5.1
<#
    Ticket 10 (deep-audit addition, session 10) — WPF/Rust registry parity.

    WHY THIS EXISTS
      ADR-0013's guarantee is that the GUI and the CLI can never drift, because
      both are generated from ONE verb registry. The Rust side
      (src-tauri/src/registry.rs) says so in its header: every row was moved
      from the C# table by a parser, "not typed by hand, because a hand-copied
      row is where a silent divergence starts". That parser is not in this
      repository, so the transfer is no longer reproducible — the only thing
      protecting the guarantee today is that nobody has touched one side since.

      This suite closes that hole mechanically: it parses BOTH tables field by
      field and requires them to agree on every load-bearing field (verb,
      script, arguments, requires_admin, help, tab, label, is_read_only,
      fixed_arguments, render_in_gui, hint, action_label, numeric_only), plus
      the verb SET against ADR-0013 on both sides.

    PATHS ARE PARAMETERS SO THE CHECK CAN BE RED-TESTED
      -CSharpPath / -RustPath let a caller point the suite at copies; a drifted
      copy must FAIL. The session-10 audit ran exactly that (one renamed label
      in the Rust copy) before trusting a green result.

    Exit 0 = both tables agree on every field and both match ADR-0013.
#>
[CmdletBinding()]
param(
    [string] $CSharpPath,
    [string] $RustPath
)

$ErrorActionPreference = 'Stop'
$script:passed = 0
$script:failed = 0

function Assert([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) {
        Write-Host "  PASS  $Name" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "        $Detail" -ForegroundColor DarkRed }
        $script:failed++
    }
}

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Src         = Join-Path $ProjectRoot 'src\KomorebiDashboard'
$CsPath  = if ($CSharpPath) { $CSharpPath } else { Join-Path $Src 'Services\VerbRegistry.cs' }
$RsPath  = if ($RustPath)   { $RustPath }   else { Join-Path $ProjectRoot 'src\KomorebiDashboardRust\src-tauri\src\registry.rs' }

# The ADR-0013 verb set, transcribed (same list tests/ticket10-dashboard-shell.tests.ps1 uses).
$AdrVerbs = @(
    'kill-all','kill-komorebi','kill-whkd','kill-yasb',
    'start-all','start-komorebi','start-whkd','start-yasb',
    'restart-all','restart-komorebi','restart-whkd','restart-yasb',
    'startup','export','import','set-transparency',
    'status','recover-monitors','display-diag','reset-workspaces','repair-whkdrc',
    'uninstall','cleanup',
    'ahk'
) | Sort-Object -Unique

Write-Host ''
Write-Host '=== Ticket 10 registry parity (WPF C# vs Rust) ===' -ForegroundColor Cyan
Assert 'the C# registry is present' (Test-Path -LiteralPath $CsPath)
Assert 'the Rust registry is present' (Test-Path -LiteralPath $RsPath)
if (-not (Test-Path -LiteralPath $CsPath) -or -not (Test-Path -LiteralPath $RsPath)) { exit 1 }

# --- parse the C# table -----------------------------------------------------
# Only the real call shape matches: new("verb", "script.ps1", "args", bool,
# "help", Tabs.Tab, "label", [Named: value, ...]). A sample in a doc comment
# written in this shape WOULD register — the same caution the C# file itself
# documents.
$csRows = @{}
$csRaw = Get-Content -LiteralPath $CsPath -Raw
$csRe = [regex]::new('new\(\s*"(?<verb>[a-z0-9-]+)"\s*,\s*"(?<script>[\w.-]+)"\s*,\s*"(?<args>[^"]*)"\s*,\s*(?<admin>true|false)\s*,\s*"(?<help>[^"]*)"\s*,\s*Tabs\.(?<tab>\w+)\s*,\s*"(?<label>[^"]*)"(?<tail>[^)]*)\)')
foreach ($m in $csRe.Matches($csRaw)) {
    $tail = $m.Groups['tail'].Value
    $named = @{}
    foreach ($nm in [regex]::Matches($tail, '(?<key>\w+)\s*:\s*(?<val>"[^"]*"|true|false)')) {
        $v = $nm.Groups['val'].Value
        if ($v.StartsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
        $named[$nm.Groups['key'].Value] = $v
    }
    $csRows[$m.Groups['verb'].Value] = [pscustomobject]@{
        Verb = $m.Groups['verb'].Value
        Script = $m.Groups['script'].Value
        Arguments = $m.Groups['args'].Value
        RequiresAdmin = [bool]::Parse($m.Groups['admin'].Value)
        Help = $m.Groups['help'].Value
        Tab = $m.Groups['tab'].Value
        Label = $m.Groups['label'].Value
        IsReadOnly = if ($named.ContainsKey('IsReadOnly')) { [bool]::Parse($named['IsReadOnly']) } else { $false }
        FixedArguments = if ($named.ContainsKey('FixedArguments')) { $named['FixedArguments'] } else { '' }
        RenderInGui = if ($named.ContainsKey('RenderInGui')) { [bool]::Parse($named['RenderInGui']) } else { $true }
        Hint = if ($named.ContainsKey('Hint')) { $named['Hint'] } else { '' }
        ActionLabel = if ($named.ContainsKey('ActionLabel')) { $named['ActionLabel'] } else { '' }
        NumericOnly = if ($named.ContainsKey('NumericOnly')) { [bool]::Parse($named['NumericOnly']) } else { $false }
    }
}

# --- parse the Rust table ---------------------------------------------------
$rsRows = @{}
$rsRaw = Get-Content -LiteralPath $RsPath -Raw
$rsRe = [regex]::new('Verb\s*\{\s*verb:\s*"(?<verb>[a-z0-9-]+)"\s*,\s*script:\s*"(?<script>[\w.-]+)"\s*,\s*arguments:\s*"(?<args>[^"]*)"\s*,\s*requires_admin:\s*(?<admin>true|false)\s*,\s*help:\s*"(?<help>[^"]*)"\s*,\s*tab:\s*"(?<tab>\w+)"\s*,\s*label:\s*"(?<label>[^"]*)"\s*,\s*is_read_only:\s*(?<ro>true|false)\s*,\s*fixed_arguments:\s*&\[(?<fixed>[^\]]*)\]\s*,\s*render_in_gui:\s*(?<gui>true|false)\s*,\s*hint:\s*"(?<hint>[^"]*)"\s*,\s*action_label:\s*"(?<action>[^"]*)"\s*,\s*numeric_only:\s*(?<num>true|false)')
$rsFixedCount = 0
foreach ($m in $rsRe.Matches($rsRaw)) {
    $fixed = @()
    foreach ($fm in [regex]::Matches($m.Groups['fixed'].Value, '"([^"]*)"')) { $fixed += $fm.Groups[1].Value }
    if ($fixed.Count -gt 0) { $rsFixedCount++ }
    $rsRows[$m.Groups['verb'].Value] = [pscustomobject]@{
        Verb = $m.Groups['verb'].Value
        Script = $m.Groups['script'].Value
        Arguments = $m.Groups['args'].Value
        RequiresAdmin = [bool]::Parse($m.Groups['admin'].Value)
        Help = $m.Groups['help'].Value
        Tab = $m.Groups['tab'].Value
        Label = $m.Groups['label'].Value
        IsReadOnly = [bool]::Parse($m.Groups['ro'].Value)
        FixedArguments = ($fixed -join ' ')
        RenderInGui = [bool]::Parse($m.Groups['gui'].Value)
        Hint = $m.Groups['hint'].Value
        ActionLabel = $m.Groups['action'].Value
        NumericOnly = [bool]::Parse($m.Groups['num'].Value)
    }
}

Write-Host ''
Write-Host "-- both tables parsed --" -ForegroundColor Cyan
Assert "the C# table parsed into rows" ($csRows.Count -ge 30) "parsed $($csRows.Count) rows"
Assert "the Rust table parsed into rows" ($rsRows.Count -ge 30) "parsed $($rsRows.Count) rows"

# The Rust file declares its own length (static VERBS: [Verb; 35]); a mismatch
# there means the array was extended without touching the type's size — the
# compile would fail, so this is a belt-and-braces check of the parse, not of
# the compiler.
$declared = [regex]::Match($rsRaw, 'static VERBS: \[Verb;\s*(\d+)\]').Groups[1].Value
if ($declared) { Assert "the Rust array length matches the parsed rows ($declared)" ([int]$declared -eq $rsRows.Count) "declared $declared, parsed $($rsRows.Count)" }

# --- verb sets ----------------------------------------------------------------
Write-Host ''
Write-Host "-- verb sets --" -ForegroundColor Cyan
$onlyCs = @($csRows.Keys | Where-Object { -not $rsRows.ContainsKey($_) } | Sort-Object)
$onlyRs = @($rsRows.Keys | Where-Object { -not $csRows.ContainsKey($_) } | Sort-Object)

$csMissingAdr = @($AdrVerbs | Where-Object { -not $csRows.ContainsKey($_) } | Sort-Object)
$rsMissingAdr = @($AdrVerbs | Where-Object { -not $rsRows.ContainsKey($_) } | Sort-Object)
Assert 'the C# table covers ADR-0013' ($csMissingAdr.Count -eq 0) "missing: $($csMissingAdr -join ', ')"
Assert 'the Rust table covers ADR-0013' ($rsMissingAdr.Count -eq 0) "missing: $($rsMissingAdr -join ', ')"

# --- sanctioned divergence (roadmap Q4: Rust ships ALONGSIDE the WPF EXE) ------
# The Rust table is the actively developed one (tickets 05/06/07 added verbs
# and UI copy there); the C# table is the legacy shell shipping alongside. So
# Rust may legitimately carry rows the WPF table does not — but each one must
# be REVIEWED and named here, because an unnamed divergence is exactly the
# silent drift ADR-0013 exists to prevent. C#-only rows are never allowed: the
# legacy table must never be ahead of its replacement.
$ReviewedRustOnly = @(
    # verb                since        why
    'ignore-dashboard'   # ticket 03 (d64ec0c): the WPF table predates the feature
) | Sort-Object
$ReviewedRustFieldOnly = @(
    # verb.field          since        why
    'export.Hint', 'export.ActionLabel',            # ticket 07 (5f8bf04): directory-selector UX copy
    'import.Hint', 'import.ActionLabel',            # ticket 07 (5f8bf04): directory-selector UX copy
    'demo-stream.Hint', 'demo-stream.ActionLabel'   # ticket 07 (5f8bf04): argument-box copy
) | Sort-Object
$newRsOnly = @($onlyRs | Where-Object { $ReviewedRustOnly -notcontains $_ } | Sort-Object)
Assert 'every Rust-only verb is a reviewed, documented divergence' ($newRsOnly.Count -eq 0) `
       "unreviewed Rust-only verbs: $($newRsOnly -join ', ')"
Assert 'no verb lives only in the legacy C# table' ($onlyCs.Count -eq 0) "C#-only: $($onlyCs -join ', ')"
Assert 'the two tables agree on the shared verb count' ($csRows.Count -eq ($rsRows.Count - $ReviewedRustOnly.Count)) `
       "C# $($csRows.Count) vs Rust $($rsRows.Count) minus $($ReviewedRustOnly.Count) reviewed Rust-only verb(s)"

# --- field-by-field equality --------------------------------------------------
Write-Host ''
Write-Host "-- every load-bearing field, both sides --" -ForegroundColor Cyan
$diffs = @()
$reviewedDiffs = @()
foreach ($verb in ($csRows.Keys | Sort-Object)) {
    if (-not $rsRows.ContainsKey($verb)) { continue }
    $a = $csRows[$verb]; $b = $rsRows[$verb]
    foreach ($field in 'Script','Arguments','RequiresAdmin','Help','Tab','Label','IsReadOnly','FixedArguments','RenderInGui','Hint','ActionLabel','NumericOnly') {
        if ($a.$field -cne $b.$field) {
            $line = ("{0}.{1}: C#='{2}' Rust='{3}'" -f $verb, $field, $a.$field, $b.$field)
            if (("{0}.{1}" -f $verb, $field) -in $ReviewedRustFieldOnly) { $reviewedDiffs += $line } else { $diffs += $line }
        }
    }
}
Assert 'every field of every shared verb matches across the two registries' ($diffs.Count -eq 0) `
       (($diffs | Select-Object -First 12) -join '; ')
if ($diffs.Count -gt 0) {
    Write-Host "        ($($diffs.Count) unreviewed field difference(s); first 12 shown)" -ForegroundColor DarkRed
}
if ($reviewedDiffs.Count -gt 0) {
    Write-Host "        ($($reviewedDiffs.Count) reviewed field difference(s), documented above: $($reviewedDiffs -join ' | '))" -ForegroundColor DarkGray
}

# --- the counts the documents publish ------------------------------------------
Write-Host ''
Write-Host "-- documented counts --" -ForegroundColor Cyan
Write-Host "        verbs: $($rsRows.Count) | with fixed arguments: $rsFixedCount | tabs: $(( $rsRows.Values | ForEach-Object { $_.Tab } | Sort-Object -Unique) -join ', ')" -ForegroundColor DarkGray

Write-Host ''
Write-Host ("TICKET10 REGISTRY PARITY: {0} assertions, {1} failed" -f ($script:passed + $script:failed), $script:failed) -ForegroundColor $(if ($script:failed -eq 0) { 'Green' } else { 'Red' })
exit $(if ($script:failed -eq 0) { 0 } else { 1 })
