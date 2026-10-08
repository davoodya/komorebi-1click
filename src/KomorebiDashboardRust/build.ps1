param([switch]$SkipRestore)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Push-Location $PSScriptRoot
try {
    # Phase 1: reproducible restore. Dependencies are pinned and lockfiles committed.
    if (-not $SkipRestore) {
        npm.cmd ci
        if ($LASTEXITCODE -ne 0) { throw 'Frontend restore failed.' }
        cargo fetch --locked --manifest-path src-tauri/Cargo.toml
        if ($LASTEXITCODE -ne 0) { throw 'Rust restore failed.' }
    }
    # Phase 2: static checks.
    npm.cmd run check
    if ($LASTEXITCODE -ne 0) { throw 'Frontend checks failed.' }
    cargo fmt --manifest-path src-tauri/Cargo.toml --check
    if ($LASTEXITCODE -ne 0) { throw 'Rust formatting check failed.' }
    # Phase 3: safe behavior tests. No state-changing management verb is run.
    npm.cmd test
    if ($LASTEXITCODE -ne 0) { throw 'Frontend tests failed.' }
    cargo test --locked --no-default-features --manifest-path src-tauri/Cargo.toml
    if ($LASTEXITCODE -ne 0) { throw 'Core behavior tests failed.' }
    # Phase 4: Windows release build and promotion; runtime verification is separate.
    $env:DASHBOARD_GIT_SHA = (git -C $repo rev-parse --short HEAD).Trim()
    cargo tauri build --no-bundle -- --locked
    if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed.' }
    $destination = Join-Path $repo 'releases/rust'
    New-Item -ItemType Directory -Force $destination | Out-Null
    $source = Join-Path $PSScriptRoot 'src-tauri/target/release/KomorebiDashboard.exe'
    Copy-Item -LiteralPath $source -Destination (Join-Path $destination 'KomorebiDashboard.exe')
    # Ticket 01 requires exactly one executable here with no companion files, so
    # assert it rather than trust directory hygiene: a stray file left by an
    # earlier build, an editor or a hand copy must fail the build, not ship.
    $expected = 'KomorebiDashboard.exe', '.gitkeep'
    $stray = @(Get-ChildItem -LiteralPath $destination -Force |
        Where-Object { $expected -notcontains $_.Name })
    if ($stray.Count -gt 0) {
        throw ("releases/rust must hold only KomorebiDashboard.exe; found: " +
            (($stray | ForEach-Object Name) -join ', '))
    }
    Get-Item (Join-Path $destination 'KomorebiDashboard.exe') | Select-Object FullName, Length
    Get-FileHash (Join-Path $destination 'KomorebiDashboard.exe') -Algorithm SHA256
} finally { Pop-Location }
