#!/usr/bin/env node
// docs-check: deterministic checks for a repository's git docs (no dependencies).
//
//   node install/docs-check.mjs [--root <dir>] [file...]
//
// Files are relative to --root (default: the current directory). Without files it checks
// README.md, AGENTS.md, CLAUDE.md and docs/**/*.md under the root (regular files only).
// Rules, one line per finding `docs-check: <file>:<line>: <rule>: <message>`:
//   link   - relative link targets exist inside the root; symlinks are resolved before
//            existence is reported, so an escaping or dangling one is "outside root"
//   anchor - `#anchor` and `file.md#anchor` match a GitHub heading slug of the target
//            (exact, then case-insensitive) or an <a name|id> anchor
//   fence  - backtick and tilde code fences (in list items or quotes too) are closed; a
//            4-space indented code block outside a list is code, not a fence
//   lines  - README.md <= 150, AGENTS.md <= 100, docs/ARCHITECTURE.md <= 300 lines; no
//            line longer than 10000 characters (such a line is not parsed)
// URLs with a scheme (http(s), mailto, kb-page:, ...) and protocol-relative URLs are
// skipped, Allye URLs included. Fenced content and inline code are ignored for links and
// headings. Exit 0 clean, 1 findings, 2 usage or file system error.
import { existsSync, lstatSync, readdirSync, readFileSync, readlinkSync, realpathSync, statSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';

const USAGE = 'usage: node install/docs-check.mjs [--root <dir>] [file...]';
const LIMITS = { 'README.md': 150, 'AGENTS.md': 100, 'docs/ARCHITECTURE.md': 300 };
const DEFAULT_FILES = ['README.md', 'AGENTS.md', 'CLAUDE.md'];
const MAX_LINE = 10000;

class UsageError extends Error {}

const toPosix = (p) => p.split(sep).join('/');
const outside = (rel) => rel === '..' || rel.startsWith(`..${sep}`) || isAbsolute(rel);

function decode(s) {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
}

function parseArgs(argv) {
  let root = '.';
  const files = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--root') {
      if (i + 1 >= argv.length) throw new UsageError('--root needs a directory');
      root = argv[++i];
    } else if (a.startsWith('-')) throw new UsageError(`unknown option ${a}`);
    else files.push(a);
  }
  return { root, files };
}

function walkMarkdown(absDir, out) {
  for (const name of readdirSync(absDir).sort()) {
    const abs = join(absDir, name);
    const st = lstatSync(abs);
    if (st.isDirectory()) walkMarkdown(abs, out);
    else if (st.isFile() && name.endsWith('.md')) out.push(abs);
  }
}

// Removes inline code spans (a backtick run closed by the next run of the same length).
function stripCode(line) {
  const runs = [];
  for (const m of line.matchAll(/`+/g)) runs.push({ start: m.index, len: m[0].length });
  const next = new Array(runs.length).fill(-1);
  const last = new Map();
  for (let i = runs.length - 1; i >= 0; i--) {
    next[i] = last.has(runs[i].len) ? last.get(runs[i].len) : -1;
    last.set(runs[i].len, i);
  }
  let out = '';
  let pos = 0;
  for (let i = 0; i < runs.length; i++) {
    if (runs[i].start < pos || next[i] === -1) continue;
    const close = runs[next[i]];
    out += line.slice(pos, runs[i].start);
    pos = close.start + close.len;
    i = next[i];
  }
  return out + line.slice(pos);
}

// nextOf(code, test)[i]: the first index >= i whose character passes test (n when none).
function nextOf(code, test) {
  const n = code.length;
  const out = new Int32Array(n + 2).fill(n);
  for (let i = n - 1; i >= 0; i--) out[i] = test(code[i]) ? i : out[i + 1];
  return out;
}

// Inline link destinations `](dest)`, `](dest(with)(parens))`, `](<dest with spaces>)`,
// `](dest "title")`. Linear: every lookup uses arrays precomputed in one pass, and a bare
// destination ends at the first whitespace or at the `)` that unbalances its parentheses
// (the next smaller prefix sum of +1 per `(` and -1 per `)`).
function inlineLinks(code) {
  const targets = [];
  if (!code.includes('](')) return targets;
  const n = code.length;
  const isWs = (c) => c === ' ' || c === '\t';
  const nextWs = nextOf(code, isWs);
  const nextNonWs = nextOf(code, (c) => !isWs(c));
  const nextChar = {};
  for (const c of ['>', '"', "'", ')']) nextChar[c] = nextOf(code, (x) => x === c);
  const sum = new Int32Array(n + 1);
  for (let i = 0; i < n; i++) sum[i + 1] = sum[i] + (code[i] === '(' ? 1 : code[i] === ')' ? -1 : 0);
  const nextLower = new Int32Array(n + 1).fill(n + 1);
  const stack = [];
  for (let k = n; k >= 0; k--) {
    while (stack.length > 0 && sum[stack[stack.length - 1]] >= sum[k]) stack.pop();
    if (stack.length > 0) nextLower[k] = stack[stack.length - 1];
    stack.push(k);
  }
  let from = 0;
  for (;;) {
    const at = code.indexOf('](', from);
    if (at === -1) break;
    from = at + 2;
    let p = nextNonWs[at + 2];
    let target;
    if (code[p] === '<') {
      const end = nextChar['>'][p + 1];
      if (end >= n) continue;
      target = code.slice(p + 1, end);
      p = end + 1;
    } else {
      const stop = Math.min(nextWs[p], nextLower[p] - 1);
      if (stop >= n) continue;
      target = code.slice(p, stop);
      p = stop;
    }
    p = nextNonWs[p];
    const q = code[p];
    if (q === '"' || q === "'" || q === '(') {
      const end = nextChar[q === '(' ? ')' : q][p + 1];
      if (end >= n) continue;
      p = nextNonWs[end + 1];
    }
    if (code[p] === ')' && target !== '') {
      targets.push(target);
      from = p + 1;
    }
  }
  return targets;
}

// ATX heading text, or null. Linear: the closing `#` sequence is removed by hand.
function atxHeading(line) {
  const t = line.replace(/[ \t]+$/, '');
  const m = /^ {0,3}(#{1,6})(?=[ \t]|$)/.exec(t);
  if (!m) return null;
  let text = t.slice(m[0].length).trim();
  let j = text.length;
  while (j > 0 && text[j - 1] === '#') j--;
  if (j === 0) text = '';
  else if (j < text.length && (text[j - 1] === ' ' || text[j - 1] === '\t')) text = text.slice(0, j).trim();
  return text;
}

// Leading indentation in columns (a tab advances to the next multiple of 4).
function columns(line) {
  let col = 0;
  for (const c of line) {
    if (c === ' ') col++;
    else if (c === '\t') col += 4 - (col % 4);
    else break;
  }
  return col;
}

// Removes `_` emphasis delimiters that pair up (CommonMark flanking rules, closer matched
// with the innermost opener of the same length); intraword and lone `_` are kept.
function stripUnderscoreEmphasis(t) {
  const word = (c) => c !== '' && /[\p{L}\p{N}]/u.test(c);
  const space = (c) => c === '' || /\s/.test(c);
  const runs = [];
  const stack = [];
  for (const m of t.matchAll(/_+/g)) {
    const start = m.index;
    const end = start + m[0].length;
    const before = start > 0 ? t[start - 1] : '';
    const after = end < t.length ? t[end] : '';
    const run = { start, end, len: end - start, matched: false };
    runs.push(run);
    const top = stack[stack.length - 1];
    if (!space(before) && !word(after) && top && top.len === run.len) {
      top.matched = true;
      run.matched = true;
      stack.pop();
    } else if (!space(after) && !word(before)) stack.push(run);
  }
  let out = '';
  let pos = 0;
  for (const r of runs) {
    if (!r.matched) continue;
    out += t.slice(pos, r.start);
    pos = r.end;
  }
  return out + t.slice(pos);
}

// Line-by-line scan: fences, headings, and links outside fences.
function scan(text) {
  const lines = text.split('\n');
  if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
  const headings = [];
  const anchors = [];
  const links = [];
  const longLines = [];
  let fence = null; // { char, len, line, marker }
  let prev = null; // previous plain paragraph line (for setext headings)
  let prevBlank = true;
  let inList = false;
  let inIndented = false; // inside a 4-space indented code block
  for (let i = 0; i < lines.length; i++) {
    const n = i + 1;
    if (lines[i].length > MAX_LINE) {
      longLines.push(n);
      prev = null;
      prevBlank = false;
      continue;
    }
    const line = lines[i].replace(/\r$/, '').replace(/^(?: {0,3}> ?)+/, '');
    const blank = line.trim() === '';
    const wasBlank = prevBlank;
    prevBlank = blank;
    if (fence) {
      const close = /^\s*(`{3,}|~{3,})\s*$/.exec(line);
      if (close && close[1][0] === fence.char && close[1].length >= fence.len) fence = null;
      continue;
    }
    const indent = columns(line);
    if (inIndented && (blank || indent >= 4)) continue;
    inIndented = false;
    if (!blank && !inList && indent >= 4) {
      // Outside a list, 4+ columns is an indented code block after a blank line, else a
      // paragraph continuation; neither opens a fence.
      if (wasBlank) {
        inIndented = true;
        prev = null;
        continue;
      }
    } else if (!blank) {
      if (/^[ \t]*(?:[-*+]|\d+[.)])(?:[ \t]|$)/.test(line)) inList = true;
      else if (indent < 2) inList = false;
    }
    const open = inList || indent < 4 ? /^\s*(`{3,}|~{3,})(.*)$/.exec(line) : null;
    if (open && !(open[1][0] === '`' && open[2].includes('`'))) {
      fence = { char: open[1][0], len: open[1].length, line: n, marker: open[1] };
      prev = null;
      continue;
    }
    const heading = atxHeading(line);
    if (heading !== null) {
      headings.push(heading);
      prev = null;
    } else if (prev !== null && /^ {0,3}(?:=+|-+)[ \t]*$/.test(line)) {
      headings.push(prev.trim());
      prev = null;
      continue;
    } else if (line.trim() === '' || /^ {0,3}(?:[-*+>|]|\d+[.)])/.test(line)) {
      prev = null;
    } else {
      prev = line;
    }
    if (line.includes('>')) {
      for (const m of line.matchAll(/<a\s[^>]*>/gi)) {
        const attr = /\b(?:name|id)\s*=\s*(?:"([^"]+)"|'([^']+)')/i.exec(m[0]);
        if (attr) anchors.push(attr[1] ?? attr[2]);
      }
    }
    const code = stripCode(line);
    for (const target of inlineLinks(code)) links.push({ target, line: n });
    const def = /^ {0,3}\[[^\]]+\]:[ \t]*(?:<([^>]*)>|(\S+))/.exec(code);
    if (def) links.push({ target: def[1] ?? def[2], line: n });
  }
  return { lineCount: lines.length, headings, anchors, links, longLines, unclosed: fence };
}

// GitHub heading anchors (github-slugger): rendered text, lowercased, punctuation removed,
// spaces to hyphens; a taken slug gets -1, -2, ... until it is free. Computed once per file.
function slugs(doc) {
  if (doc.slugs) return doc.slugs;
  const occurrences = new Map();
  for (const h of doc.headings) {
    const text = stripUnderscoreEmphasis(
      h
        .replace(/!?\[([^[\]]*)\]\([^()]*\)/g, '$1')
        .replace(/<[^<>]*>/g, '')
        .replace(/`/g, ''),
    );
    const base = text
      .toLowerCase()
      .replace(/[^\p{L}\p{M}\p{N}\p{Pc} -]/gu, '')
      .replace(/ /g, '-');
    let slug = base;
    while (occurrences.has(slug)) {
      const count = occurrences.get(base) + 1;
      occurrences.set(base, count);
      slug = `${base}-${count}`;
    }
    occurrences.set(slug, 0);
  }
  const exact = new Set([...occurrences.keys(), ...doc.anchors]);
  doc.slugs = { exact, lower: new Set([...exact].map((x) => x.toLowerCase())) };
  return doc.slugs;
}

// Resolves every symlink of an absolute path, also when the path (or a link target) does
// not exist: { real, exists }. A symlink loop resolves to the filesystem root.
function resolveReal(p, depth = 0) {
  if (depth > 40) return { real: resolve('/'), exists: false };
  try {
    return { real: realpathSync(p), exists: true };
  } catch {
    // fall through: p or one of its components does not resolve
  }
  const parent = dirname(p);
  if (parent === p) return { real: p, exists: false };
  let st = null;
  try {
    st = lstatSync(p);
  } catch {
    st = null;
  }
  if (st && st.isSymbolicLink()) {
    return { real: resolveReal(resolve(dirname(p), readlinkSync(p)), depth + 1).real, exists: false };
  }
  return { real: join(resolveReal(parent, depth + 1).real, basename(p)), exists: false };
}

function main() {
  const { root, files } = parseArgs(process.argv.slice(2));
  const absRoot = resolve(root);
  if (!existsSync(absRoot) || !statSync(absRoot).isDirectory()) throw new UsageError(`root is not a directory: ${root}`);
  const realRoot = realpathSync(absRoot);
  const escapes = (abs) => outside(relative(realRoot, realpathSync(abs)));

  const targets = [];
  if (files.length > 0) {
    for (const f of files) {
      const abs = resolve(absRoot, f);
      if (outside(relative(absRoot, abs))) throw new UsageError(`file outside root: ${f}`);
      if (!existsSync(abs) || !statSync(abs).isFile()) throw new UsageError(`no such file: ${f}`);
      if (escapes(abs)) throw new UsageError(`file outside root: ${f}`);
      targets.push(abs);
    }
  } else {
    for (const f of DEFAULT_FILES) {
      const abs = join(absRoot, f);
      if (existsSync(abs) && lstatSync(abs).isFile()) targets.push(abs);
    }
    const docs = join(absRoot, 'docs');
    if (existsSync(docs) && lstatSync(docs).isDirectory()) walkMarkdown(docs, targets);
  }

  // Keyed by real path: every read goes through the resolved path, never a symlink.
  const cache = new Map();
  const load = (real) => {
    if (!cache.has(real)) cache.set(real, scan(readFileSync(real, 'utf8')));
    return cache.get(real);
  };
  const findings = [];
  for (const abs of targets) {
    const rel = toPosix(relative(absRoot, abs));
    const selfReal = realpathSync(abs);
    const doc = load(selfReal);
    const own = [];
    const report = (line, rule, message) => own.push({ line, text: `docs-check: ${rel}:${line}: ${rule}: ${message}` });
    for (const { target, line } of doc.links) {
      if (/^[a-z][a-z0-9+.-]*:/i.test(target) || target.startsWith('//')) continue;
      const hash = target.indexOf('#');
      const beforeHash = hash === -1 ? target : target.slice(0, hash);
      const anchor = hash === -1 ? '' : decode(target.slice(hash + 1));
      const query = beforeHash.indexOf('?');
      const pathPart = decode(query === -1 ? beforeHash : beforeHash.slice(0, query));
      let dest = abs;
      let real = selfReal;
      if (pathPart !== '') {
        dest = pathPart.startsWith('/') ? join(absRoot, pathPart) : resolve(dirname(abs), pathPart);
        if (outside(relative(absRoot, dest))) {
          report(line, 'link', `target outside root ${target}`);
          continue;
        }
        // Containment before existence: a dangling or escaping symlink is "outside root".
        const r = resolveReal(dest);
        if (outside(relative(realRoot, r.real))) {
          report(line, 'link', `target outside root ${target}`);
          continue;
        }
        if (!r.exists) {
          report(line, 'link', `missing target ${target}`);
          continue;
        }
        real = r.real;
      }
      if (anchor === '' || !dest.endsWith('.md') || !statSync(real).isFile()) continue;
      const known = slugs(load(real));
      if (!known.exact.has(anchor) && !known.lower.has(anchor.toLowerCase())) {
        report(line, 'anchor', `no heading for #${anchor} in ${toPosix(relative(absRoot, dest))}`);
      }
    }
    if (doc.unclosed) report(doc.unclosed.line, 'fence', `unclosed ${doc.unclosed.marker} fence`);
    for (const n of doc.longLines) report(n, 'lines', `line longer than ${MAX_LINE} characters`);
    const limit = LIMITS[rel];
    if (limit !== undefined && doc.lineCount > limit) report(limit + 1, 'lines', `${doc.lineCount} lines, limit ${limit}`);
    own.sort((a, b) => a.line - b.line); // stable: a file's findings in line order
    findings.push(...own.map((f) => f.text));
  }

  if (findings.length > 0) {
    process.stdout.write(`${findings.join('\n')}\n`);
    process.stderr.write(`docs-check: ${findings.length} finding(s)\n`);
    process.exit(1);
  }
  process.stdout.write(`docs-check: ok (${targets.length} files)\n`);
}

try {
  main();
} catch (err) {
  if (err instanceof UsageError) {
    process.stderr.write(`docs-check: ${err.message}\ndocs-check: ${USAGE}\n`);
  } else {
    process.stderr.write(`docs-check: error: ${err.message}\n`);
  }
  process.exit(2);
}
