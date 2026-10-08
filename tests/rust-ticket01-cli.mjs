import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
import { mkdir, writeFile, stat } from 'node:fs/promises';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const exe = path.join(repo, 'releases/rust/KomorebiDashboard.exe');
const evidence = path.join(repo, 'test-results/rust-ticket01');
await mkdir(evidence, { recursive: true });
const results = [];
async function run(name, args, expected, verify) {
  const started = performance.now();
  const child = spawn(exe, args, { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '', stderr = '', chunks = [];
  child.stdout.on('data', b => { stdout += b; chunks.push({ ms: performance.now() - started, bytes: b.length }); });
  child.stderr.on('data', b => { stderr += b; });
  const code = await new Promise((resolve, reject) => { child.once('error', reject); child.once('close', resolve); });
  const result = { name, code, durationMs: performance.now() - started, stdout, stderr, chunks };
  results.push(result);
  await writeFile(path.join(evidence, `${name}.json`), JSON.stringify(result, null, 2));
  assert.equal(code, expected, `${name}: ${stderr}`);
  verify(result);
  console.log(`PASS ${name}: exit=${code}, stdout=${Buffer.byteLength(stdout)} bytes, chunks=${chunks.length}`);
}
assert.ok((await stat(exe)).size > 0);
await run('help', ['--help'], 0, r => { assert.match(r.stdout, /Usage:/); assert.match(r.stdout, /status/); assert.match(r.stdout, /demo-stream/); });
await run('unknown', ['not-a-verb'], 2, r => assert.match(r.stderr, /Unknown verb.*[\s\S]*Usage:/));
await run('status-override-refused', ['status', '-Action', 'install'], 2, r => assert.match(r.stderr, /accepts no arguments/));
await run('status', ['status'], 0, r => { assert.ok(r.stdout.length > 100); assert.match(r.stderr, /succeeded.*exit 0/); });
await run('stream', ['demo-stream', '-Lines', '100', '-DelayMs', '10'], 0, r => {
  assert.match(r.stdout, /line 100\/100/);
  assert.match(r.stderr, /stderr checkpoint at line 100/);
  assert.ok(r.chunks.length > 2, 'Streaming must have several observable chunks');
  assert.ok(r.chunks[0].ms < r.durationMs - 300, 'Output must arrive before completion');
});
await run('script-failure', ['demo-stream', '-Lines', '2', '-DelayMs', '0', '-FailWith', '7'], 7, r => assert.match(r.stderr, /FAILED.*exit 7/));
await writeFile(path.join(evidence, 'cli-summary.json'), JSON.stringify(results, null, 2));
console.log(`PASS all ${results.length} CLI cases against the published Windows executable.`);
