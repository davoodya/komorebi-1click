// rust-ticket02-exe-driver.mjs
//
// Drives the shipped release executable as a CLI and reports what it actually
// did, for tests/rust-ticket02-probe.ps1.
//
// Why a Node driver instead of calling the binary from PowerShell: the release
// binary is a windows-subsystem application (it must never flash a console for
// the GUI). Measured on the real artifact, `& $exe demo-stream -Lines 5` from
// PowerShell returned exit 0 with ZERO bytes of output, because PowerShell has no
// way to pipe a windows-subsystem child's stdio. `child_process.spawn` gives the
// process real pipes, so the output is genuinely observed rather than assumed
// missing. Ticket 01's CLI suite already relies on this; this driver keeps that
// one technique in one place.
//
// Usage: node tests/rust-ticket02-exe-driver.mjs --exe <path> --evidence <dir>
//
// Prints one JSON object: { runs: { <name>: {...} } }.

import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

function arg(name, fallback) {
  const at = process.argv.indexOf(`--${name}`);
  return at >= 0 && process.argv[at + 1] ? process.argv[at + 1] : fallback;
}

const exe = arg('exe', path.resolve('releases/rust/KomorebiDashboard.exe'));
const evidence = arg('evidence', path.resolve('test-results/rust-ticket02'));
await mkdir(evidence, { recursive: true });

/** Runs the binary once and returns everything observed about the run. */
function run(name, args, timeoutMs = 60_000) {
  return new Promise((resolve) => {
    const started = performance.now();
    const child = spawn(exe, args, { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    let chunks = 0;
    child.stdout.on('data', (b) => {
      stdout += b;
      chunks++;
    });
    child.stderr.on('data', (b) => {
      stderr += b;
    });

    const timer = setTimeout(() => child.kill(), timeoutMs);
    child.once('error', (error) => {
      clearTimeout(timer);
      resolve({ name, exit_code: -1, error: String(error), elapsed_ms: 0, stdout_bytes: 0, stderr_bytes: 0, chunks: 0, lines_seen: 0, summary: '' });
    });
    child.once('close', async (code) => {
      clearTimeout(timer);
      // The verdict line the binary prints on stderr, for a readable summary.
      const verdict = (stderr.match(/(TIMED OUT|FAILED|CANCELLED|succeeded)[^\r\n]*/) || [''])[0].trim();
      const linesSeen = (stdout.match(/\[demo-stream\] line \d+\/\d+/g) || []).length;
      const fixturePidsAfter = await countFixtureProcesses();
      const result = {
        name,
        exit_code: code,
        elapsed_ms: Math.round(performance.now() - started),
        stdout_bytes: Buffer.byteLength(stdout),
        stderr_bytes: Buffer.byteLength(stderr),
        chunks,
        lines_seen: linesSeen,
        stdout_complete: /line 5\/5/.test(stdout),
        stderr_complete: /failing on purpose with code 9/.test(stderr),
        summary: verdict,
        fixture_pids_after: fixturePidsAfter
      };
      // Keep the raw text so a failing assertion can be diagnosed from evidence.
      await writeFile(path.join(evidence, `exe-${name}.txt`), `--- stdout ---\n${stdout}\n--- stderr ---\n${stderr}\n`);
      resolve(result);
    });
  });
}

/** Pids of PowerShell processes running our fixture, matched on the command line. */
function countFixtureProcesses() {
  return new Promise((resolve) => {
    const ps = spawn(
      'powershell.exe',
      [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "(Get-CimInstance Win32_Process -Filter \"Name='powershell.exe' or Name='pwsh.exe'\" | Where-Object { $_.CommandLine -like '*demo-stream.ps1*' }).Count"
      ],
      { windowsHide: true }
    );
    let out = '';
    ps.stdout.on('data', (b) => (out += b));
    ps.once('close', () => resolve(Number.parseInt(out.trim(), 10) || 0));
    ps.once('error', () => resolve(0));
  });
}

const runs = {};
// A hung run: 200 lines at 100 ms is 20 s of work against a 3 s budget. The
// fixture documents that the caller owns the budget, which is what is under test.
runs.timeout = await run('timeout', ['demo-stream', '-Lines', '200', '-DelayMs', '100', '-TimeoutSeconds', '3'], 40_000);
// A chatty run: 1000 lines must arrive bounded and complete.
runs.batching = await run('batching', ['demo-stream', '-Lines', '1000', '-DelayMs', '0', '-StdErrEvery', '0'], 90_000);
// A failing run: the script's own code, with both streams complete.
runs.failure = await run('failure', ['demo-stream', '-Lines', '5', '-DelayMs', '0', '-FailWith', '9']);
// An invalid request: rejected before anything is launched.
runs.unknown_verb = await run('unknown_verb', ['not-a-verb']);
// A read-only verb: the baseline that everything else is compared against.
runs.status = await run('status', ['status']);

// A short settle so a slow reap is not counted as a survivor.
await new Promise((r) => setTimeout(r, 1500));
runs.__leftover_fixture_pids = await countFixtureProcesses();

console.log(JSON.stringify({ exe, runs }, null, 2));