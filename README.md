# komorebi-1click

A **portable, offline-first, one-click installer** that reproduces a complete
**Komorebi + WHKD + YASB + AutoHotkey** tiling-window-manager environment on any
**Windows 10/11 x64** machine — plus an Admin Dashboard (GUI + CLI twin) for
day-2 management.

> **Status:** early. This repository currently ships the **payload and provenance
> foundation** (ticket 01). The installer logic, configuration generation and the
> Dashboard are tracked as tickets and land in later commits.

---

## What gets installed

Five components, all pinned to exact versions and **committed to this repo**, so
the install needs no network connection:

| Component | Version | Payload | License |
|---|---|---|---|
| [Komorebi](https://github.com/LGUG2Z/komorebi) | 0.1.41 | `binaries/komorebi-0.1.41-x86_64.msi` | [Komorebi License](licenses/LICENSE-komorebi.md) |
| [WHKD](https://github.com/LGUG2Z/whkd) | 0.2.10 | `binaries/whkd-0.2.10-x86_64.msi` | [Komorebi License](licenses/LICENSE-whkd.md) |
| [YASB](https://github.com/amnweb/yasb) | 2.0.7 | `binaries/yasb-2.0.7-x64.msi` | [MIT](licenses/LICENSE-yasb.txt) |
| [AutoHotkey](https://github.com/AutoHotkey/AutoHotkey) v1 | 1.1.30.00 | `binaries/AutoHotkey.1.1.30.00_setup.exe` | [GPLv2](licenses/AutoHotkey-GPLv2.txt) |
| [AutoHotkey](https://github.com/AutoHotkey/AutoHotkey) v2 | 2.0.12 | `binaries/AutoHotkey_2.0.12_setup.exe` | [GPLv2](licenses/AutoHotkey-GPLv2.txt) |

Everything installs into the vendor-default `C:\Program Files\…` locations and
x64 is required (ARM64 is refused with a clear message, never silently
mis-installed).

## Offline by default

The whole point of this repository is that **nothing is downloaded during
install**. Every binary needed is committed here. To prove that the committed
bytes are the official ones, each payload is pinned to its **official release URL
and SHA256**:

```
binaries/payloads.sha256.txt   # SHA256 per payload — sha256sum -c format
binaries/payloads.sha256.json  # URL, SHA256, vendor, version, license, notes
```

Verify them yourself, offline:

```powershell
Get-FileHash .\binaries\*.msi, .\binaries\*.exe -Algorithm SHA256
# compare against .\binaries\payloads.sha256.txt
```

Or from a WSL/bash checkout at the repo root:

```bash
sha256sum -c binaries/payloads.sha256.txt
```

## Installing

```powershell
.\Install.ps1
```

The installer:

1. **Verifies every payload's SHA256** against `binaries/payloads.sha256.json`
   before touching the system. A corrupted or replaced payload is named and the
   install stops — nothing is ever installed from an unverified file.
2. Installs the three MSIs silently with `msiexec /quiet` into the vendor-default
   `C:\Program Files\…` locations, and installs AutoHotkey v1 and v2 with their
   own silent switches (`/S` and `/silent`).
3. **Detects state before each step** and skips anything already installed at the
   expected version, so running it twice reaches exactly the same end state.
4. **Refuses ARM64** with a clear message instead of mis-installing.
5. Requires elevation, and says why.
6. **Generates the full configuration** from portable templates: `whkdrc` and
   `applications.json` are copied with the source machine's paths rewritten to the
   target user, `komorebi.json` gets one 9-workspace monitor block per detected
   display plus `display_index_preferences` generated from the live hardware, and
   `komorebi-resize.json` is created empty (it is pure runtime state). The YASB
   config's sensor-script path is made repo-relative. Then **`komorebic check`
   validates the result before success is declared.**

When a step fails it prints three things and stops: the failing step, the
underlying cause, and the concrete action to fix it — so a failed install is
recoverable without outside help. Completed steps are never repeated.

## Repository layout

```
binaries/     the five installers (MSI + setup EXE) + provenance records
licenses/     verbatim license text for every redistributed binary
config/       portable configuration templates:
                komorebi.json  minus monitors / display_index_preferences /
                               app_specific_configuration_path (generated at install)
                whkdrc         all hotkey bindings (source paths rewritten at install)
                applications.json  app-specific rules, verbatim
                config.yaml    YASB bar/widget config (sensor path rewritten at install)
scripts/      installer library + sensor script used by the YASB temperature widgets;
              management scripts land here in tickets 06 and 08
releases/     published Dashboard builds (distributed, not committed)
Install.ps1   the installer entry point
```

## Redistribution and licensing

The MSIs and setup executables here are **unmodified, verbatim copies of the
official release artifacts** — this project never patches or re-signs them, which
is what keeps the SHA256 pins meaningful. Each one carries the license text of its
project alongside it.

Two things worth stating plainly:

- **AutoHotkey is GPLv2**, not MIT. Its full license text is committed at
  [`licenses/AutoHotkey-GPLv2.txt`](licenses/AutoHotkey-GPLv2.txt).
- Komorebi and WHKD are distributed under the **Komorebi License v2.0.0**, which
  permits redistributing the source but is restrictive about redistributing the
  software itself. This project's posture is therefore to make provenance
  **explicit and verifiable** — official URL + SHA256 + license text per payload —
  so it is unambiguously a convenience packaging of the official artifacts, not a
  modified build and not a claim of ownership.

## Contributing

This repository is the **publish** tree. Research, specs, tickets and ADRs live in
a separate development directory and are not pushed.
