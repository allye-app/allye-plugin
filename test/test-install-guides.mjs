// Guards the install/update guides in docs/: every download is pinned to a release tag,
// allye-opencode and allye-pi are always installed with an exact version, and nothing
// is piped into an interpreter. Reads files only; offline, no dependencies.
// Scope: docs/install-*.md and docs/update-*.md (README.md is intentionally excluded).
import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const docsDir = join(root, "docs");

const INTERPS = /^(?:sh|bash|zsh|dash|ksh|ash|fish|csh|tcsh|pwsh|node|nodejs|deno|bun|perl|ruby|php|lua|tclsh|python[\d.]*|eval|source|\.)$/i;
const WRAPPERS = /^(?:sudo|doas|env|xargs|command|exec|nohup|time|nice|stdbuf|builtin)$/i;
const base = (t) => t.replace(/^["'`]+|["'`]+$/g, "").split("/").pop();
const INTERP_RE = "(?:sh|bash|zsh|dash|ksh|ash|fish|csh|tcsh|pwsh|node|nodejs|deno|bun|perl|ruby|php|lua|python[\\d.]*|eval|source)";
const FETCH = /\b(?:curl|wget)\b/i;
const TMPDIRS = "(?:/tmp|/var/tmp|/dev/shm)";

// Logical lines: fenced-code aware (``` and ~~~, 4+ fences), a trailing backslash, `|`, `&&` or `||`
// joins the next physical line, and a next line starting with `|` continues the previous command.
function logicalLines(text) {
  const out = [];
  let fence = null; // { ch, len }
  let join = false;
  text.split("\n").forEach((line, i) => {
    const m = line.match(/^\s{0,3}(`{3,}|~{3,})(.*)$/);
    if (m) {
      if (!fence) { fence = { ch: m[1][0], len: m[1].length }; join = false; return; }
      if (m[1][0] === fence.ch && m[1].length >= fence.len && m[2].trim() === "") { fence = null; join = false; return; }
    }
    const inFence = fence !== null;
    const last = out[out.length - 1];
    let raw = line;
    if (last && last.fence === inFence && (join || /^\s*\|(?!\|)/.test(line))) {
      last.text += " " + raw.replace(/^\s+/, "");
    } else {
      out.push({ text: raw, line: i + 1, fence: inFence });
    }
    join = /(?:\\|\|\||&&|\|)\s*$/.test(line);
    if (/\\\s*$/.test(line)) {
      const cur = out[out.length - 1];
      cur.text = cur.text.replace(/\\\s*$/, "");
    }
  });
  // collapse remaining "\ " joins inside merged lines
  for (const l of out) l.text = l.text.replace(/\\\s+(?=\S)/g, " ");
  return out;
}

const VERSION_OK = /^@["']?(?:\d+\.\d+\.\d+|\$\{?VERSION\}?|<[^>]+>|\{[^}]+\})["']?$/;
const TAG_OK = /^[@#]["']?(?:v[0-9X]|\$\{?TAG\b|<)/;

function unpinnedInstall(l) {
  const re = /(?<![\w.-])(?:(?:pi|omp\s+plugin|omp|npm|pnpm|yarn|bun)\s+(?:install|add|i|update|upgrade|up)\b|npx\b|bunx\b|(?:pnpm|yarn)\s+dlx\b|npm\s+exec\b)/gi;
  let m;
  while ((m = re.exec(l))) {
    const rest = l.slice(m.index + m[0].length);
    const span = rest.split(/[|;&`]|\)\s*\)/)[0];
    for (let tok of span.split(/\s+/).filter(Boolean)) {
      tok = tok.replace(/[).,;:]+$/, "");
      const pkg = tok.match(/^["']?(?:npm:)?(allye-(?:pi|opencode))(.*)$/i);
      if (pkg && !/^[\w-]/.test(pkg[2]) && !VERSION_OK.test(pkg[2].replace(/["']$/, (q) => (/^@["']/.test(pkg[2]) ? q : "")))) return true;
      const git = tok.match(/^["']?(?:github:|git\+(?:https?|ssh):\/\/(?:[^/]*@)?github\.com\/|https?:\/\/github\.com\/|git@github\.com:)allye-app\/allye-plugin(?:\.git)?(.*)$/i);
      if (git && !TAG_OK.test(git[1])) return true;
    }
  }
  return false;
}

function pipeToInterpreter(l) {
  if (!FETCH.test(l)) return false;
  // a pipe segment after a fetch whose command is an interpreter (possibly behind sudo/env/xargs...)
  const segs = l.split(/(?<!\|)\|(?!\|)/);
  let seenFetch = FETCH.test(segs[0]);
  for (let i = 1; i < segs.length; i++) {
    if (seenFetch) {
      const toks = segs[i].trim().split(/\s+/).filter(Boolean);
      if (toks.length) {
        const head = base(toks[0]);
        if (INTERPS.test(head)) return true;
        if (WRAPPERS.test(head) && toks.slice(1, 9).some((t) => INTERPS.test(base(t)))) return true;
      }
    }
    if (FETCH.test(segs[i])) seenFetch = true;
  }
  const P = "(?<![\\w.-])(?:[\\w./-]*\\/)?";
  // interpreter reading a process substitution of a fetch: bash <(curl ..), source <(curl ..), bash < <(curl ..)
  if (new RegExp(`${P}${INTERP_RE}\\b[^|;&\\n]*<\\(\\s*(?:sudo\\s+)?(?:curl|wget)\\b`, "i").test(l)) return true;
  if (/(?<![\w.-])\.\s+(?:<\s*)?<\(\s*(?:sudo\s+)?(?:curl|wget)\b/i.test(l)) return true;
  // command substitution: eval "$(curl ..)", sh -c '$(curl ..)', perl -e "`curl ..`", . "$(curl ..)"
  if (new RegExp(`${P}(?:${INTERP_RE})\\b\\s+(?:-\\S+\\s+)*["']?(?:\\$\\(|\`)\\s*(?:sudo\\s+)?(?:curl|wget)\\b`, "i").test(l)) return true;
  if (/(?<![\w.-])\.\s+["']?(?:\$\(|`)\s*(?:curl|wget)\b/i.test(l)) return true;
  // download then run: curl -o x URL && bash x | sh x | ./x
  const outs = [...l.matchAll(/(?:\s-o|\s-O|--output=?|\s>>?)\s*["']?([^\s"'|;&<>]+)/g)].map((m) => m[1]);
  for (const f of outs) {
    const esc = f.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const after = `(?:&&|;|\\|\\|)\\s*(?:(?:sudo|doas|env|command|exec)\\s+(?:-\\S+\\s+)*)*`;
    if (new RegExp(`${after}(?:[\\w./-]*\\/)?${INTERP_RE}(?:\\s+-\\S+)*\\s+["']?${esc}\\b`, "i").test(l)) return true;
    if (new RegExp(`${after}["']?${esc.startsWith("/") || esc.startsWith(".") ? "" : "\\./"}${esc}["']?(?:\\s|$)`).test(l)) return true;
  }
  return false;
}

function branchDownload(l) {
  if (/refs\/heads\/|allye-plugin-main|raw\.githubusercontent/i.test(l)) return true;
  if (/https?:\/\/\S*\/(?:main|master|develop|HEAD)(?:[/.?"'\s]|$)/i.test(l)) return true;
  if (/archive\/(?:main|master|develop|HEAD)\b|(?:tarball|zipball)\/(?:main|master|develop|HEAD)\b|\bheads\/(?:main|master|develop)\b|[?&]ref=(?:main|master|develop|HEAD)\b/i.test(l)) return true;
  if (/(?:--branch|-b)[=\s]+["']?(?!v[0-9X]|\$\{?TAG\b|"\$\{?TAG\b)\S/i.test(l) && /\bgit\s+clone\b|\bgh\s+repo\s+clone\b/i.test(l)) return true;
  if (/(?:--branch|-b)[=\s]+["']?(?:main|master|develop|HEAD)\b/i.test(l)) return true;
  // allowlist: any download or clone of allye-app/allye-plugin must carry a release tag
  if (/allye-app\/allye-plugin/i.test(l) && !/repos\/allye-app\/allye-plugin\/releases\/(?:latest|tags\/)/i.test(l)) {
    const downloads = /\barchive\/|tarball|zipball|codeload|\/raw\/|\/blob\/|\bgit\s+clone\b|\bgh\s+repo\s+clone\b|git\+|\.git\b|\bgit\s+archive\b/i.test(l);
    const pinned = /refs\/tags\/v|(?:archive|tarball|zipball)\/v[0-9]|tags\/v[0-9]|[@#]v[0-9X]|(?:--branch|-b)[=\s]+["']?v[0-9X]/i.test(l);
    if (downloads && !pinned) return true;
  }
  return false;
}

const JQ_LOOK = /==\s*"allye-|\bstartswith\(|\bltrimstr\(|\.\s*==\s*"/;
const RULES = [
  { id: "branch-download", test: branchDownload },
  { id: "unpinned-install", test: unpinnedInstall },
  { id: "unpinned-plugin-entry", fence: true, test: (l) => /["']allye-(?:opencode|pi)["']/i.test(l) && !JQ_LOOK.test(l) },
  { id: "unpinned-git-source", test: (l) => /git:github\.com\/allye-app\/allye-plugin(?!@(?:v[0-9X]|"?\$\{?TAG\b|<))/i.test(l) },
  { id: "pipe-to-interpreter", test: pipeToInterpreter },
  {
    id: "fixed-tmp-download",
    test: (l) =>
      FETCH.test(l) &&
      (new RegExp(`(?:-o|-O|--output|--output-dir|--directory-prefix|-P|>>?)\\s*=?\\s*["']?${TMPDIRS}/`).test(l) ||
        new RegExp(`\\bcd\\s+["']?${TMPDIRS}\\b[^\\n]*\\b(?:curl|wget)\\b`, "i").test(l)),
  },
];

export function scanText(text) {
  const hits = [];
  for (const l of logicalLines(text)) {
    for (const rule of RULES) {
      if (rule.fence && !l.fence) continue;
      if (rule.test(l.text)) hits.push({ line: l.line, rule: rule.id });
    }
  }
  return hits;
}

const errors = [];
const fail = (msg) => errors.push(msg);
const L = (...lines) => lines.join("\n");

// Self-tests: bad text must trip the rule, good text must not.
const BAD = {
  "branch-download": [
    "curl -fsSL https://github.com/allye-app/allye-plugin/archive/refs/heads/main.tar.gz -o x",
    "curl -fsSL https://raw.githubusercontent.com/allye-app/allye-plugin/main/install.sh -o x",
    "cd allye-plugin-main",
    "curl https://github.com/allye-app/allye-plugin/archive/main.tar.gz",
    "curl -L https://api.github.com/repos/allye-app/allye-plugin/tarball/main -o x",
    "curl -L https://api.github.com/repos/allye-app/allye-plugin/zipball/master -o x",
    "curl -L https://codeload.github.com/allye-app/allye-plugin/tar.gz/heads/main -o x",
    "curl -L https://github.com/allye-app/allye-plugin/archive/HEAD.tar.gz -o x",
    "curl -L https://api.github.com/repos/allye-app/allye-plugin/contents/x?ref=main",
    "curl -L https://github.com/allye-app/allye-plugin/archive/2.8.0.tar.gz -o x",
    "git clone https://github.com/allye-app/allye-plugin",
    "git clone --branch main https://github.com/allye-app/allye-plugin",
    "git clone -b develop https://github.com/allye-app/allye-plugin.git",
    "gh repo clone allye-app/allye-plugin",
    "curl -fsSL https://example.com/org/repo/main/file.sh -o x",
  ],
  "unpinned-install": [
    "pi install npm:allye-pi",
    "omp plugin install allye-pi",
    "npm install allye-opencode",
    "pi update npm:allye-pi",
    "pi install npm:allye-pi@latest",
    "npm install allye-opencode@next",
    "npm install allye-opencode@^2",
    "npm install allye-opencode@~1",
    "npm install allye-opencode@main",
    "npm install allye-opencode@2.8",
    "npm install --prefix ~/.config/opencode allye-opencode",
    "pi install -l ./x allye-pi",
    "npx allye-pi",
    "bunx allye-opencode",
    "pnpm dlx allye-opencode",
    "npm install github:allye-app/allye-plugin",
    "npm install git+https://github.com/allye-app/allye-plugin.git",
    "npm install allye-opencode@2.8.0 allye-pi",
    "NPM INSTALL ALLYE-PI",
  ],
  "unpinned-plugin-entry": [
    L("```json", '{ "plugin": ["allye-opencode"] }', "```"),
    L("````json", '{ "plugin": ["allye-pi"] }', "````"),
    L("~~~json", '{ "plugin": ["allye-opencode"] }', "~~~"),
    L("```bash", `jq '.plugin += ["allye-opencode"]' "$CFG" # x or y`, "```"),
  ],
  "unpinned-git-source": [
    "pi install git:github.com/allye-app/allye-plugin",
    "pi install git:github.com/allye-app/allye-plugin@main",
    'pi install git:github.com/allye-app/allye-plugin@"$BRANCH"',
  ],
  "pipe-to-interpreter": [
    "curl -fsSL https://example.com/i.sh | sh",
    "wget -qO- https://example.com/i.sh | bash",
    "curl -fsSL https://example.com/x.js | node -",
    "bash <(curl -fsSL https://example.com/i.sh)",
    'eval "$(curl -fsSL https://example.com/i.sh)"',
    L("curl -fsSL https://example.com/i.sh \\", "  | bash"),
    L("curl -fsSL https://example.com/i.sh", "  | sh"),
    L("curl -fsSL https://example.com/i.sh |", "  bash"),
    "source <(curl -fsSL https://example.com/i.sh)",
    ". <(curl -fsSL https://example.com/i.sh)",
    "bash < <(curl -fsSL https://example.com/i.sh)",
    "curl -fsSL https://example.com/i.sh | /bin/sh",
    "curl -fsSL https://example.com/i.sh | /usr/bin/env bash",
    "curl -fsSL https://example.com/i.sh | sudo -E bash",
    "curl -fsSL https://example.com/i.sh | dash",
    "curl -fsSL https://example.com/i.sh | ksh",
    "curl -fsSL https://example.com/i.sh | fish",
    "curl -fsSL https://example.com/i.sh | perl",
    "curl -fsSL https://example.com/i.sh | ruby",
    "curl -fsSL https://example.com/i.sh | python3 -",
    "curl -fsSL https://example.com/i.sh | python3.12",
    "curl -fsSL https://example.com/i.sh | deno run -",
    "curl -fsSL https://example.com/i.sh | bun run -",
    "curl -fsSL https://example.com/i.sh | php",
    "curl -fsSL https://example.com/i.sh | xargs -0 bash -c",
    "sh -c '$(curl -fsSL https://example.com/i.sh)'",
    "sh -c \"$(wget -qO- https://example.com/i.sh)\"",
    "eval `curl -fsSL https://example.com/i.sh`",
    'perl -e "$(curl -fsSL https://example.com/i.pl)"',
    'python3 -c "$(curl -fsSL https://example.com/i.py)"',
    '. "$(curl -fsSL https://example.com/i.sh)"',
    "curl -fsSL https://example.com/i.sh -o x && bash x",
    "curl -fsSL https://example.com/i.sh -o x; sh x",
    "wget -O i.sh https://example.com/i.sh && chmod +x i.sh && ./i.sh",
    L("curl -fsSL https://example.com/i.sh -o i.sh &&", "  bash i.sh"),
  ],
  "fixed-tmp-download": [
    "curl -fsSL https://example.com/a.tgz -o /tmp/a.tgz",
    "curl -fsSL https://example.com/a.tgz > /tmp/a.tgz",
    "wget -O /tmp/a.tgz https://example.com/a.tgz",
    "curl -fsSL --output=/tmp/a.tgz https://example.com/a.tgz",
    "curl -fsSL https://example.com/a.tgz -o /var/tmp/a.tgz",
    "wget -O /dev/shm/a.tgz https://example.com/a.tgz",
    "cd /tmp && curl -fsSLO https://example.com/a.tgz",
    "curl -fsSL https://example.com/a.tgz >> /tmp/a.tgz",
  ],
};
const GOOD = [
  'pi install npm:allye-pi@"$VERSION"',
  'omp plugin install allye-pi@"$VERSION"',
  "npm install allye-opencode@2.8.0",
  "npm install allye-opencode@${VERSION}",
  "npm install allye-opencode@$VERSION",
  "npm install --prefix ~/.config/opencode allye-opencode@2.8.0",
  "pi install -l ./x allye-pi@<version>",
  "npm install allye-opencode@2.8.0 allye-pi@2.8.0",
  'npm install github:allye-app/allye-plugin#"$TAG"',
  "pi install npm:pi-mcp-adapter",
  "pi remove npm:allye-pi",
  "pi -e ./packages/allye-pi/src/index.ts -p hi",
  "Do not use `pi update`, it would not move a pinned version.",
  "Allye for Pi is the native package `allye-pi`.",
  "confirm `omp plugin install --help` lists `--force`; do not use `omp plugin upgrade`, remove with `omp plugin uninstall allye-pi`.",
  'pi install git:github.com/allye-app/allye-plugin@"$TAG"',
  "pi install git:github.com/allye-app/allye-plugin@v2.8.0",
  "pi install git:github.com/allye-app/allye-plugin@$TAG",
  "remove the git source `git:github.com/allye-app/allye-plugin@<tag>`",
  'curl --proto \'=https\' -fsSL https://github.com/allye-app/allye-plugin/archive/refs/tags/v"$VERSION".tar.gz -o "$ALLYE_TMP/release.tar.gz"',
  "curl -fsSL https://github.com/allye-app/allye-plugin/archive/refs/tags/v2.8.0.tar.gz | tar -xz",
  "git clone --branch v2.8.0 https://github.com/allye-app/allye-plugin",
  "curl -fsSL https://api.github.com/repos/allye-app/allye-plugin/releases/latest | jq -r '.tag_name'",
  "The latest release of `allye-app/allye-plugin` is used.",
  "see src/main/java/App.java for details",
  'curl -fsSL "$URL" | tar -xz -C "$DIR"',
  L("curl -fsSL https://example.com/a.tgz \\", '  -o "$T/a.tgz"', 'tar -xzf "$T/a.tgz"'),
  L("curl -fsSL https://example.com/a.tgz \\", "  | tar -xz"),
  'curl -fsSL https://example.com/a.tgz -o "$T/a.tgz" && tar -xzf "$T/a.tgz" && node check.mjs',
  L("```jq", 'def isa: if type == "string" then (. == "allye-opencode" or startswith("allye-opencode@"))', "```"),
  L("````md", "```bash", "pi install npm:allye-pi@\"$VERSION\"", "```", "````"),
  "| main | the main branch of the user's own project |",
];
for (const [ruleId, samples] of Object.entries(BAD)) {
  for (const sample of samples) {
    if (!scanText(sample).some((h) => h.rule === ruleId)) fail(`self-test: rule ${ruleId} did not flag: ${JSON.stringify(sample)}`);
  }
}
for (const sample of GOOD) {
  const hits = scanText(sample);
  if (hits.length) fail(`self-test: good text flagged (${hits.map((h) => h.rule).join(",")}): ${JSON.stringify(sample)}`);
}
// Fence handling: a 4-backtick fence is not closed by a 3-backtick line; prose after it is not code.
{
  const lines = logicalLines(L("````md", "```", '{"p":["allye-opencode"]}', "````", '"allye-opencode"'));
  if (!lines[0]?.fence || lines[lines.length - 1].fence) fail("self-test: nested fence handling is wrong");
}

// Real guides.
const guides = readdirSync(docsDir).filter((n) => /^(install|update)-.+\.md$/.test(n)).sort();
if (guides.length === 0) fail("docs/ has no install-*.md or update-*.md guides");
const texts = {};
const code = {}; // fenced, non-comment logical lines per guide
for (const g of guides) {
  const text = (texts[g] = readFileSync(join(docsDir, g), "utf8"));
  for (const h of scanText(text)) fail(`docs/${g}:${h.line}: ${h.rule}`);
  code[g] = logicalLines(text).filter((l) => l.fence && !/^\s*#/.test(l.text));
}

// Positive assertions match fenced, non-comment command lines, not prose or comments.
const needCode = (file, re, why) => {
  if (!(file in code)) return fail(`docs/${file}: missing guide`);
  if (!code[file].some((l) => re.test(l.text))) fail(`docs/${file}: no command line matches ${re} (${why})`);
};
needCode("install-codex.md", /\b(?:curl|wget)\b[^\n]*refs\/tags\/v/, "tag archive download");
for (const f of ["install-opencode.md", "update-opencode.md"]) {
  needCode(f, /allye-opencode@[^\n]*(?:\$v\b|\$\{?VERSION|\$pin)|(?:\$v\b|\$\{?VERSION)[^\n]*allye-opencode@/, "pinned plugin");
}
for (const f of ["install-pi.md"]) needCode(f, /\bpi\s+install\b[^\n]*allye-pi@/, "pinned package");
needCode("install-omp.md", /\bomp\s+plugin\s+install\b[^\n]*allye-pi@/, "pinned package");
for (const f of guides) {
  const installs = code[f].some((l) => FETCH.test(l.text) || /\bnpm\s+view\b/.test(l.text) || /\b(?:pi|omp\s+plugin)\s+install\b/.test(l.text));
  if (installs) needCode(f, /=~\s*\^v?\[0-9\]\+\\\.\[0-9\]\+\\\.\[0-9\]\+\$/, "version rule");
}

if (errors.length) {
  console.error(`Install guide checks failed (${errors.length}):`);
  for (const e of errors) console.error(`- ${e}`);
  process.exit(1);
}
console.log(`Install guide checks passed (${guides.length} guides, ${Object.values(BAD).flat().length + GOOD.length} self-test samples).`);
