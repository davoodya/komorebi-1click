# komorebi-1click Rust Translate — Environment & Build Strategy

**Probed:** 2026-10-08, by real command execution (not documentation).
Everything below was verified on this machine. Re-probe before relying on it after a toolchain change.

---

## 1. The two directories (do not mix)

| Directory | Purpose | Pushed to GitHub |
|---|---|---|
| `~/projects/komorebi-1click/` (WSL) | Dev: audit, specs, tickets, scratch issue tracker | ❌ never |
| `/mnt/h/Repo/komorebi-1click/` = `H:\Repo\komorebi-1click` | **Publish**: everything that ships | ✅ yes |

This translation's planning documents live in the **publish** side:
`H:\Repo\komorebi-1click\docs\rust-translate\`.

---

## 2. Guard bypass (WSL → Windows), applied

The WSL isolation guard blocks `/mnt/*`, `/init`, `/run/WSL/*` unless `ALLOW_WINDOWS=1`.
**Davood granted explicit permission for this project to bypass the guard on `/mnt/h` and `/mnt/*`.**

Mechanism — `~/.hermes/scripts/mnt-guard.sh`, sourced from `~/.bashrc`:

```bash
hermes_guard_check() {
    if [ "$ALLOW_WINDOWS" = "1" ]; then return 0; fi   # ← the bypass
    case "$1" in /mnt|/mnt/*|/init|/run/WSL/*) return 1 ;; *) return 0 ;; esac
}
```

**Verified working:**

```bash
export ALLOW_WINDOWS=1
ALLOW_WINDOWS=1 bash -c 'cd /mnt/h/Repo/komorebi-1click/docs/rust-translate && pwd'
# → /mnt/h/Repo/komorebi-1click/docs/rust-translate   BYPASS_OK
touch /mnt/h/Repo/komorebi-1click/docs/rust-translate/.write-test   # → WRITE_OK
```

Notes:

- Export it **per command** (`ALLOW_WINDOWS=1 <cmd>`) or once per session; the guard reads the env
  var live, so no file edit is needed and nothing persistent is changed.
- The guard's PATH strip runs once per session (`HERMES_GUARD_PATH_CLEANED` sentinel) and removes
  every `/mnt/*` PATH entry, so bare `cmd.exe` / `powershell.exe` do **not** resolve. Use
  `win-exec.sh` (below) instead of re-adding Windows PATH.
- The **behavioral** layer (SOUL §9, agent file tools) is separate from this shell guard. With the
  user's explicit grant, both are cleared for this project.

---

## 3. Running Windows executables from WSL

`binfmt_misc/WSLInterop` is **not registered** on this box, so a bare `.exe` fails with
`Exec format error`. Route through `/init`, which is the handler the binfmt entry would invoke:

```bash
# ~/.hermes/scripts/win-exec.sh  — usage
win-exec.sh pwsh '<inline PS script>'     # PowerShell 7
win-exec.sh powershell '<inline PS script>'  # Windows PowerShell 5.1
win-exec.sh cmd '<cmdline>'
win-exec.sh /mnt/c/path/to/prog.exe [args...]
```

**Pitfalls that already cost debugging time** (from `wsl-isolation` skill):

1. A `\\wsl.localhost\...` cwd is UNC → `CMD.EXE` silently falls back to `C:\Windows` and relative
   paths resolve somewhere unexpected. **Pass absolute Windows paths, or `Set-Location` first.**
2. Execution policy blocks `-File` on `\\wsl.localhost\...` → pass inline `-Command`, or copy the
   script to a Windows temp dir first.
3. A bare `&` in a `terminal` command string is treated as backgrounding → put PowerShell in a file
   and run `bash file.sh`.
4. PowerShell's `& exe 2>&1` capture can report 0 lines for a binary that wrote kilobytes → redirect
   to a file and read the file.

---

## 4. Toolchain inventory (probed)

### 4.1 WSL (Kali) side

| Tool | Version | Path |
|---|---|---|
| `cargo` | 1.95.0 (f2d3ce0bd) | `/usr/bin/cargo` |
| `rustc` | 1.95.0 (59807616e) | `/usr/bin/rustc` |
| `node` | v26.7.0 | — |
| `npm` | 11.19.0 | — |
| `pnpm` | **not installed** | — |
| `cargo tauri` | **installed ✓ `tauri-cli 2.12.1`** (2026-10-08, both Windows and WSL) | — |

### 4.2 Windows side (the build actually happens here)

| Tool | Version / value | Path |
|---|---|---|
| `cargo` | 1.95.0, **MSVC** toolchain | `C:\Program Files\Rust stable MSVC 1.95\bin\cargo.exe` |
| `rustup` | present | `C:\Users\DavoodYa\.cargo\bin\rustup.exe` |
| rustup installed targets | **`x86_64-pc-windows-msvc`** ✓ | — |
| `node` | v24.21.0 | `C:\nvm4w\nodejs\node.exe` |
| `npm` | 11.19.0 | `C:\nvm4w\nodejs\npm.cmd` |
| Visual Studio | **18 Enterprise** (provides `link.exe` for the MSVC target) | `C:\Program Files\Microsoft Visual Studio\18\Enterprise` |
| `vswhere.exe` | present | `C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe` |
| **WebView2 runtime** | **154.0.4258.62** ✓ (Tauri's hard requirement) | HKLM EdgeUpdate client key |
| `tauri-cli` | **installed ✓** — `tauri-cli 2.12.1` on both Windows and WSL (`cargo tauri --version`) | none |
| `msbuild` | not on PATH (not needed — `cargo build` drives it via `link.exe`) | — |
| Global npm packages | `9router`, `corepack`, `npm` | — |

> **UNC cwd warning observed live:** running `npm ls -g` printed
> `'\\wsl.localhost\kali-linux\home\davoodya' ... UNC paths are not supported. Defaulting to Windows
> directory.` — always `Set-Location` to a Windows absolute path first.

---

## 5. Build strategy (consequence of §4)

**Build host ruling (Davood, 2026-10-08): develop on Windows, not WSL** — WSL2/WSLg imposes
constraints that the Windows toolchain does not have, and `tauri-cli 2.12.1` is already installed
on both sides. WSL remains useful for driving the build and for the platform-independent tests.

The Tauri app is a **Windows desktop app**. It needs MSVC `link.exe`, the Windows SDK and WebView2,
so the build must run **on Windows**, not inside WSL:

```
WSL (planning, git, file edits via /mnt/h)
        │  ALLOW_WINDOWS=1
        ▼
win-exec.sh pwsh / cmd   ──►   cargo.exe build --release   (MSVC, x86_64-pc-windows-msvc)
        │                      npm/pnpm run tauri build
        ▼
H:\Repo\komorebi-1click\releases\rust\     ← artefact lands here (dir already exists, empty)
```

Two viable driving styles — **decision needed, see Open Question Q4**:

- **A. `cargo tauri build` from Windows**, driven by `win-exec.sh`. One command, produces the
  installer + portable exe. `tauri-cli` 2.12.1 is already installed on Windows — this prerequisite is met.
- **A'. `npx @tauri-apps/cli build`**, avoids a global install but downloads on first use.

WSL-side `cargo` (1.95, non-MSVC) is useful for `cargo check`/`cargo test` of pure-Rust logic
(registry, settings, argument splitting) but **cannot** link the Tauri/Windows crates. Treat WSL
`cargo test` as a fast inner loop for platform-independent modules only, and Windows as the
authoritative build.

---

## 6. Prerequisites to install before implementation starts

| # | What | Where | Why |
|---|---|---|---|
| 1 | ~~`tauri-cli`~~ — **DONE 2026-10-08**, 2.12.1 on both sides; prefer the Windows one | Windows | was the only hard blocker |
| 2 | Frontend package manager (npm is present; pnpm is not) | Windows | Decide per Open Question Q2 |
| 3 | Rust `windows-sys` / `windows` crate availability offline | both | Project is offline-first; check crates.io reachability from this network |

---

## 7. Non-negotiable environment facts (carried from `knowledges.md`)

- Host: Windows 11 Pro `10.0.26200.0`, user `DavoodYa` is **NOT** in Administrators → silent
  elevation (`runas`) fails without consent; the only approved High-integrity path is the
  pre-configured Scheduled Tasks (`Komorebi`, `KomorebiWatchdog`, `RunLevel=Highest`).
- PowerShell: prefer `pwsh.exe` (7.x), fall back to `powershell.exe` (5.1). All scripts support both.
- 3 monitors: D1 1920×1080 100 %, D2 1920×1080 100 %, D3 1080×1920 portrait **125 %**.
- Everything user-facing ships in **English** (ADR-0014 / language rule).
- The Dashboard must never launch `whkd.exe` directly (pairing trap T2) and must never rewrite the
  `.shell` header of `whkdrc` (trap T1).
