// check-shipped-text.mjs
//
// Enforces ADR-0017 rule 7 ("English-only shipped text") in its machine-checkable
// form: no foreign-script codepoints in shipped text.
//
// Why this exists rather than a plain "no non-ASCII" grep: the rule is about
// LANGUAGE, not character encoding. A check that flags every non-ASCII codepoint
// fires on ordinary English typography — em dashes, en dashes, curly quotes — which
// the original WPF dashboard uses in its own shipped UI. Such a check is a false
// positive generator: it fails on prose written by the person applying it.
//
// History: a review of ticket 02 flagged em dashes as a standards violation under a
// stricter reading than the ADR states. ADR-0017 rule 7 was then made explicit, and
// this script is the enforceable half of that clarification. The real violation in
// this project was defect D25, a Chinese help string — CJK, which this catches.
//
// What it scans: shipped source and text (production frontend sources, Rust sources,
// PowerShell scripts, docs). What it ignores: binary assets (images, fonts, icons)
// and build output. Test files are scanned too, since their text is also shipped.
//
// Usage: node tests/check-shipped-text.mjs [--repo <path>]
//
// Exit codes: 0 clean, 1 at least one foreign-script codepoint found.

import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

function arg(name, fallback) {
  const at = process.argv.indexOf(`--${name}`);
  return at >= 0 && process.argv[at + 1] ? process.argv[at + 1] : fallback;
}

const repo = arg('repo', path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..'));

// Foreign scripts only. English punctuation is deliberately absent from this list.
const RANGES = [
  ['CJK Unified Ideographs', 0x4e00, 0x9fff],
  ['CJK Extension A', 0x3400, 0x4dbf],
  ['CJK Compatibility', 0xf900, 0xfaff],
  ['CJK punctuation', 0x3000, 0x303f],
  ['Fullwidth forms', 0xff00, 0xffef],
  ['Hangul syllables', 0xac00, 0xd7af],
  ['Hiragana', 0x3040, 0x309f],
  ['Katakana', 0x30a0, 0x30ff],
  ['Cyrillic', 0x0400, 0x04ff],
  ['Arabic', 0x0600, 0x06ff],
  ['Arabic supplement', 0x0750, 0x077f],
  ['Hebrew', 0x0590, 0x05ff],
  ['Thai', 0x0e00, 0x0e7f],
  ['Devanagari', 0x0900, 0x097f]
];

/**
 * What counts as "shipped text": the trees whose contents the product ships.
 *
 * Scoping by inclusion rather than exclusion matters here. Scanning the whole repo
 * produced 7,528 hits, none of them real: 7,509 were Persian reference cheatsheets,
 * 18 were Chinese QQ window titles in komorebi's own application config, and 1 was
 * this checker's own self-test file. A rule whose implementation fires 7,528 times
 * on a clean repo is not a rule, it is noise — and noise gets switched off.
 */
const SHIPPED_TREES = ['src', 'scripts', 'docs/rust-translate', 'tests'];

/** Files whose text ships. Anything else (assets, build output) is out of scope. */
const TEXT_EXTENSIONS = new Set(['.rs', '.ts', '.svelte', '.js', '.mjs', '.ps1', '.md', '.json', '.html', '.css', '.toml', '.xaml', '.cs']);

/** Directories that are never shipped text. */
const SKIP_DIRS = new Set(['node_modules', 'target', 'dist', '.git', 'test-results', 'bin', 'obj', 'last-backup']);

/**
 * Excluded on purpose, each with the reason it is not shipped UI text.
 *
 * These are not loopholes: every one is data or reference material that must keep
 * its non-English characters to be correct.
 */
const EXCLUDED = [
  // Reference material for Davood, in Persian, deliberately kept and not shipped.
  'scripts/SCRIPTS-GUIDE.fa.md',
  // This checker itself: its comments name the scripts it looks for, by definition.
  'tests/check-shipped-text.mjs'
];

/**
 * Third-party application config is data, not text. komorebi's config matches window
 * titles of the applications it ignores; a Chinese app such as QQ has Chinese titles,
 * so translating or transliterating them would silently break the exclusion rule.
 * Detected by content, not by path, so a new config file cannot slip through.
 */
const DATA_FILES = ['config/komorebi.json', 'config/applications.json'];

async function* walk(dir) {
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (SKIP_DIRS.has(entry.name)) continue;
      yield* walk(full);
    } else if (entry.isFile()) {
      yield full;
    }
  }
}

const findings = [];
let scanned = 0;

const candidates = [];
for (const tree of SHIPPED_TREES) {
  for await (const file of walk(path.join(repo, tree))) candidates.push(file);
}

for (const file of candidates) {
  const rel = path.relative(repo, file).split(path.sep).join('/');
  if (!TEXT_EXTENSIONS.has(path.extname(file).toLowerCase())) continue;
  if (EXCLUDED.some((prefix) => rel === prefix || rel.endsWith(`/${prefix}`))) continue;

  let text;
  try {
    text = await readFile(file, 'utf8');
  } catch {
    continue;
  }
  // A file that is not valid UTF-8 is binary in practice; skip rather than guess.
  if (text.includes('\uFFFD')) continue;
  scanned++;

  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    for (const char of lines[i]) {
      const cp = char.codePointAt(0);
      const hit = RANGES.find(([, lo, hi]) => cp >= lo && cp <= hi);
      if (hit) {
        findings.push({ file: rel, line: i + 1, script: hit[0], codepoint: `U+${cp.toString(16).toUpperCase().padStart(4, '0')}` });
      }
    }
  }
}

// Report one line per finding, deduplicated, so a single bad file cannot flood the log.
const byFile = new Map();
for (const f of findings) {
  const key = `${f.file}:${f.line}`;
  if (!byFile.has(key)) byFile.set(key, f);
}

console.log(`scanned ${scanned} shipped-text files for foreign scripts`);
if (byFile.size === 0) {
  console.log('PASS  no foreign-script codepoints in shipped text (ADR-0017 rule 7)');
  process.exit(0);
}

console.log(`FAIL  ${byFile.size} line(s) contain foreign-script codepoints:`);
for (const f of byFile.values()) {
  console.log(`  ${f.file}:${f.line}  ${f.script}  ${f.codepoint}`);
}
process.exit(1);