# Local build checklist — the four phases

Ticket 01 requires that "the four phases of the local build checklist pass from a clean checkout".
This file is that checklist, and `src/KomorebiDashboardRust/build.ps1` is its executable form: the
four phases below are the four blocks in that script, in order. Run it, do not emulate it.

```
pwsh -File H:\Repo\komorebi-1click\src\KomorebiDashboardRust\build.ps1
pwsh -File ...\build.ps1 -SkipRestore     # phases 2-4 only, for a fast re-run
```

| Phase | Command it runs | What passing proves |
|---|---|---|
| 1 — Reproducible restore | `npm ci` then `cargo fetch --locked` | The frontend and Rust dependency sets resolve from the committed `package-lock.json` and `Cargo.lock` alone. A floating or unpinned dependency fails here, not in a user's build. |
| 2 — Static checks | `npm run check` (svelte-check) then `cargo fmt --check` | Zero type errors and zero diagnostics across every `.svelte` and `.ts` file, and Rust formatting is canonical. This is the phase that catches the class of fault which, in the WPF build, escaped the compiler and only appeared at first render (defect D21). |
| 3 — Safe behaviour tests | `npm test` (vitest) then `cargo test --locked --no-default-features` | The frontend's pure rules (argument splitting, console batching and cap, run-verdict wording, the token contract, the literal-colour ban) and the backend's registry/runner contract hold. No state-changing management verb is executed by either suite. |
| 4 — Windows release build and promotion | `cargo tauri build --no-bundle -- --locked`, then copy the executable to `releases\rust\` | The MSVC link step succeeds, the frontend bundle is embedded, and exactly one executable lands in `releases\rust\KomorebiDashboard.exe`. Runtime verification is a separate step and is never inferred from a successful build. |

## After the build

Runtime verification is deliberately not part of the four phases, because a build that links is not a
program that works:

| Evidence | Entry point |
|---|---|
| CLI twin: `--help`, unknown verb, refused override, `status`, streaming, script exit code | `tests\rust-ticket01-cli.mjs` (Windows `node`) |
| Rendered window: header, tab, both rows, READ-ONLY badge, a real button click streaming to completion | `tests\rust-ticket01-ui.ps1` (Windows PowerShell, UI Automation) |

Both write JSON evidence under `test-results\rust-ticket01\`.

## Clean-checkout caveat

Phase 1 is what makes the clean-checkout claim meaningful. The working tree is not a clean checkout:
`config/komorebi.json`, `scripts/safe-restart.ps1` and two staged handoff deletions pre-date this
work and are deliberately preserved. A clean-checkout run of phases 1-4 requires those to be committed
or stashed first; until then the honest statement is "the four phases pass in this working tree".
