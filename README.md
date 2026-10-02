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

The installer core lands with ticket 02. Until then `Install.ps1` exits with a
clear "not implemented yet" message rather than pretending to succeed.

## Repository layout

```
binaries/     the five installers (MSI + setup EXE) + provenance records
licenses/     verbatim license text for every redistributed binary
config/       shipped configuration templates (ticket 03)
scripts/      management scripts: start/stop/restart, backup, cleanup (tickets 06, 08)
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
