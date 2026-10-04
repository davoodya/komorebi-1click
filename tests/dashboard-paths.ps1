#Requires -Version 5.1
<#
.SYNOPSIS
    Shared path resolution for the Dashboard test suites.

.DESCRIPTION
    WHY THIS FILE EXISTS

    Ticket 13 added <RuntimeIdentifier>win-x64</RuntimeIdentifier> to the
    Dashboard csproj. That is required for publish, but it has a side effect
    on plain `dotnet build`: the output moves from

        bin\Release\net8.0-windows\KomorebiDashboard.exe
    to
        bin\Release\net8.0-windows\win-x64\KomorebiDashboard.exe

    Three suites (ticket11, ticket12-theme-elevation, ticket12-runtime) had
    that first path hardcoded, so adding the RID broke all three with a bare
    "EXE produced" FAIL — a failure in the tests, not in the app.

    Rather than hardcoding the new path (which would break again the moment a
    second RID is added for win-x86, which ADR-0015 defers to v2), each suite
    calls Resolve-DashboardExe and gets whichever layout is actually on disk.
    One place to fix when the layout changes again.
#>

function Resolve-DashboardExe {
    <#
      .SYNOPSIS
        Find the built KomorebiDashboard.exe, with or without a RID subfolder.

      .PARAMETER Src
        The src\KomorebiDashboard directory. Defaults to this repo's checkout.

      .OUTPUTS
        The full path to the EXE, or $null when it has not been built.
    #>
    [CmdletBinding()]
    param(
        [string] $Src = 'H:\Repo\komorebi-1click\src\KomorebiDashboard'
    )

    $binRoot = Join-Path $Src 'bin\Release'
    if (-not (Test-Path $binRoot)) { return $null }

    # Wildcard, not a fixed path: covers both bin\Release\net8.0-windows\ and
    # bin\Release\net8.0-windows\win-x64\ without either being assumed.
    $found = @(Get-ChildItem $binRoot -Recurse -Filter 'KomorebiDashboard.exe' `
                            -File -EA SilentlyContinue)

    if ($found.Count -eq 0) { return $null }

    # If both layouts exist (a stale one plus a fresh one), prefer the
    # non-RID one: it is what `dotnet build` without a RID produces, and it is
    # the faster-starting framework-dependent build for a local smoke test.
    $plain = $found | Where-Object { $_.Directory.Name -eq 'net8.0-windows' }
    if ($plain) { return $plain[0].FullName }

    return ($found | Sort-Object LastWriteTime -Descending)[0].FullName
}
