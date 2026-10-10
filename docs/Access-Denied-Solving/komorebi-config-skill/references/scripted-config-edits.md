# Editing komorebi.json from a script

Recipe for a script that adds a rule to a config file the user already owns. The
file is deeply nested, has optional arrays, and is watched by komorebi itself.

## PowerShell round-trip that does not corrupt the file

```powershell
function Read-Json($path) {
    # Depth 32, NOT the default 2. komorebi.json nests monitor and workspace
    # objects well past depth 2, and ConvertTo-Json / ConvertFrom-Json silently
    # replace everything deeper with its type name ("System.Object[]"), so
    # omitting this destroys monitors/workspaces on write-back with no error.
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 32
}

function Write-Json($obj, $path) {
    # UTF8 without BOM. komorebi's serde loader rejects a BOM.
    $json = $obj | ConvertTo-Json -Depth 32
    [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
}
```

## Optional arrays: create, never assume

An absent `ignore_rules` / `manage_rules` key is valid input — the schema makes
them optional, and a real config may omit either. A script that does
`$cfg.ignore_rules += $rule` on a missing key fails with
"The property 'ignore_rules' cannot be found on this object". Create it:

```powershell
if (-not $cfg.PSObject.Properties['ignore_rules']) {
    $cfg | Add-Member -NotePropertyName ignore_rules -NotePropertyValue @() -Force
}
$cfg.ignore_rules = @($cfg.ignore_rules) + $newRule
```

## Idempotency, checked on the rule and not the array

Match on the rule's payload (`Exe`), not on count or position, so a second run is
a clean no-op and reports that rather than duplicating:

```powershell
$exists = @($cfg.ignore_rules) | Where-Object {
    $_.Exe -and $_.Exe.ToLower() -eq $exeName.ToLower()
}
if ($exists) { return 'already-present' }
```

## The conflict check that makes the rule actually work

An ignore rule is skipped when a matching manage rule exists (see SKILL.md's
rule-evaluation model). The script must refuse to claim success in that case —
warn that a `manage_rules` entry for the same `Exe` will override it. Report this
BEFORE writing, so the user learns the rule cannot take effect rather than
discovering it after a restart.

## Validity gate before and after

JSON parsing is not validation. To prove the round-trip preserved structure: parse
the original and the edited copy in an independent JSON parser (Python is fine)
and diff the trees semantically, ignoring the added rule. A `ConvertTo-Json` depth
mistake surfaces as a mass of `System.Object[]` strings in that diff — which is
the test worth running, because `komorebic check` and exit code 0 both pass on a
corrupted file.

## After writing

komorebi's file watcher applies the edit within seconds
(`StaticConfig::preload` → `ReloadStaticConfiguration`). Do not also call
`reload-configuration` (a no-op on JSON-only setups) and do not restart just to
apply a rule. Confirm with `komorebic global-state` — the OUTPUT key is
`ignore_identifiers`, not `ignore_rules`.

Give the script a `-NoReload` / dry-run switch and point it at a copy first: the
edit path is easy to test on a throwaway file, and writing to the live config is
what needs the user's consent.

## Reporting

Exit codes are not evidence. Print the resulting rule count and the rule itself,
so the transcript shows what the file now contains.
