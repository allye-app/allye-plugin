// Static checks of the CI workflows (release hardening) and the LICENSE packaging.
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (p) => readFileSync(join(root, p), 'utf8');

// Parser assumptions (kept deliberately simple): jobs are indented by exactly two
// spaces under a top-level `jobs:`, job keys (needs, permissions, outputs) by four,
// and `needs` is a single line (`needs: x` or `needs: [x, y]`). Reformatting the
// workflows outside these rules makes this test fail loudly rather than pass silently.

// Split the text under the top-level `jobs:` key into { name: bodyText }.
function parseJobs(text) {
  const lines = text.split('\n');
  const start = lines.findIndex((l) => /^jobs:\s*$/.test(l));
  const jobs = {};
  if (start < 0) return jobs;
  let cur = null;
  for (const l of lines.slice(start + 1)) {
    if (/^\S/.test(l)) break;
    const m = /^  ([A-Za-z0-9_-]+):\s*$/.exec(l);
    if (m) { cur = m[1]; jobs[cur] = []; continue; }
    if (cur) jobs[cur].push(l);
  }
  return Object.fromEntries(Object.entries(jobs).map(([k, v]) => [k, v.join('\n')]));
}

function needsOf(body) {
  const m = /^ {4}needs:\s*(.+)$/m.exec(body);
  if (!m) return [];
  return m[1].replace(/[\[\]]/g, '').split(',').map((x) => x.trim()).filter(Boolean);
}

function checkRelease(text) {
  const errs = [];
  const bad = (c, msg) => { if (!c) errs.push(msg); };
  const jobs = parseJobs(text);
  const names = Object.keys(jobs);
  const publish = names.filter((n) => n.startsWith('publish-'));
  const build = names.filter((n) => n.startsWith('build-'));
  bad(/^permissions:\s*\n\s+contents:\s*read/m.test(text), 'top-level permissions contents: read');
  bad(!/^ {2}(contents|id-token):\s*write/m.test(text), 'no top-level write permissions');
  bad(!/npm@latest/.test(text), 'no npm@latest');
  bad(!/pull_request_target/.test(text), 'no pull_request_target');
  bad(!/secrets:\s*inherit/.test(text), 'no secrets: inherit');
  bad(jobs.release && JSON.stringify(needsOf(jobs.release)) === '["test"]', 'release needs exactly test');
  bad(publish.length >= 2 && build.length >= 1, 'publish-* and build-* jobs exist');
  for (const n of [...publish, ...build]) bad(needsOf(jobs[n]).includes('release'), `${n} needs release`);
  for (const [n, b] of Object.entries(jobs)) {
    const idw = /id-token:\s*write/.test(b);
    const cw = /contents:\s*write/.test(b);
    bad(!idw || n.startsWith('publish-'), `id-token: write only in publish-* (${n})`);
    bad(!cw || n === 'release', `contents: write only in release (${n})`);
    if (idw) {
      bad(!/\b(bun|npm ci|npm install(?! -g npm@)|yarn|pnpm)\b/.test(b.replace(/npm install -g npm@\d+\.\d+\.\d+/g, '')) &&
        !/setup-bun/.test(b) && !/run build/.test(b), `no build/install step in id-token job (${n})`);
      bad(/npm install -g npm@\d+\.\d+\.\d+/.test(b), `pinned npm in ${n}`);
      for (const m of b.matchAll(/npm publish[^\n]*/g)) bad(/--ignore-scripts/.test(m[0]), `npm publish uses --ignore-scripts in ${n}`);
    }
  }
  for (const n of publish) {
    for (const co of b_checkouts(jobs[n])) {
      bad(/persist-credentials:\s*false/.test(co), `${n} checkout persist-credentials: false`);
      bad(/ref:\s*\$\{\{\s*needs\.release\.outputs\.sha\s*\}\}/.test(co), `${n} checkout uses release sha`);
    }
  }
  for (const n of build) {
    for (const co of b_checkouts(jobs[n])) {
      bad(/persist-credentials:\s*false/.test(co), `${n} checkout persist-credentials: false`);
      bad(/needs\.release\.outputs\.sha/.test(co), `${n} checkout uses release sha`);
    }
  }
  const GUARD = "if: github.event_name == 'push' && github.ref == 'refs/heads/main'";
  for (const n of ['build-opencode', 'publish-opencode', 'publish-pi']) {
    bad(jobs[n] && jobs[n].includes(GUARD), `main push guard on ${n}`);
  }
  bad(!/write-all/.test(text), 'no write-all');
  bad(/^ {4}uses:\s*\.\/\.github\/workflows\/test\.yml\s*$/m.test(jobs.test || '') && /contents:\s*read/.test(jobs.test || ''), 'test job calls test.yml with contents: read');
  const relCo = b_checkouts(jobs.release || '');
  bad(relCo.length > 0 && relCo.every((c) => /persist-credentials:\s*false/.test(c)), 'release checkout persist-credentials: false');
  const up = /upload-artifact@[^\n]*\n(?:[^\n]*\n)*?\s+name:\s*(\S+)/.exec(text);
  const down = /download-artifact@[^\n]*\n(?:[^\n]*\n)*?\s+name:\s*(\S+)/.exec(text);
  bad(up && down && up[1] === down[1], 'upload and download artifact names match');
  bad(/retention-days:\s*\d+/.test(jobs['build-opencode'] || ''), 'artifact retention-days set');
  const po = jobs['publish-opencode'] || '';
  bad(/jq -r '\.name' package\.json\)" = "allye-opencode"/.test(po) && /\.repository\.url[^\n]*allye-app\/allye-plugin/.test(po), 'publish-opencode asserts package name and repository');
  bad(/^concurrency:\s*\n\s+group:\s*release\s*\n\s+cancel-in-progress:\s*false\s*$/m.test(text), 'concurrency group release, cancel-in-progress false');
  bad(/outputs:\s*\n\s+sha:/.test(jobs.release || ''), 'release exposes sha output');
  const inst = /npm install -g (semantic-release.*)$/m.exec(text);
  bad(inst && inst[1].trim().split(/\s+/).every((p) => /@\d+\.\d+\.\d+$/.test(p)), 'semantic-release installs are pinned');
  for (const m of text.matchAll(/^\s*-?\s*uses:\s*(\S+)/gm)) {
    if (m[1].startsWith('./')) continue;
    bad(/@[0-9a-f]{40}$/.test(m[1]), `uses pinned to SHA: ${m[1]}`);
  }
  return errs;
}

function b_checkouts(body) {
  return [...body.matchAll(/uses:\s*actions\/checkout@[^\n]*\n((?:\s{8,}.*\n?)*)/g)].map((m) => m[0]);
}

function checkTest(text) {
  const errs = [];
  const bad = (c, msg) => { if (!c) errs.push(msg); };
  bad(/^ *pull_request:/m.test(text), 'pull_request');
  bad(/workflow_call/.test(text), 'workflow_call');
  bad(!/pull_request_target/.test(text), 'no pull_request_target');
  bad(/^permissions:\s*\n\s+contents:\s*read/m.test(text), 'contents: read');
  bad(/persist-credentials:\s*false/.test(text), 'persist-credentials: false');
  for (const m of text.matchAll(/^\s*-?\s*uses:\s*(\S+)/gm)) bad(/@[0-9a-f]{40}$/.test(m[1]), `pinned: ${m[1]}`);
  return errs;
}

let failed = 0;
const report = (name, errs) => {
  if (errs.length) { failed++; console.error(`FAIL ${name}: ${errs.join('; ')}`); } else console.log(`ok ${name}`);
};

const release = read('.github/workflows/auto-release.yml');
const testYml = read('.github/workflows/test.yml');
report('auto-release.yml', checkRelease(release));
report('test.yml', checkTest(testYml));

// Self-check: mutated copies must fail, so the checks are not vacuous.
const mutations = [
  ['npm@latest', release.replace('npm@11.19.0', 'npm@latest')],
  ['unpinned uses', release.replace(/(actions\/checkout)@[0-9a-f]{40} # v4/, '$1@v4')],
  ['id-token in build', release.replace(/(build-opencode:[\s\S]*?permissions:\n\s+contents: read)/, '$1\n      id-token: write')],
  ['top-level write', release.replace(/^permissions:\n  contents: read/m, 'permissions:\n  contents: write')],
  ['release needs more', release.replace(/(  release:\n    needs: )test/, '$1[test, build-opencode]')],
  ['unpinned semantic-release', release.replace('semantic-release@25.0.9', 'semantic-release')],
  ['publish runs scripts', release.replace(' --ignore-scripts', '')],
  ['no main guard', release.replace(/(build-opencode:[\s\S]*?)if: github\.event_name == 'push' && github\.ref == 'refs\/heads\/main'/, '$1if: true')],
  ['write-all', release.replace('id-token: write # npm', 'write-all # npm')],
  ['test job perms', release.replace(/(  test:\n    permissions:\n      contents: )read/, '$1write')],
  ['release persist creds', release.replace(/(  release:[\s\S]*?persist-credentials: )false/, '$1true')],
  ['artifact name mismatch', release.replace(/name: allye-opencode-package\n          path: allye-opencode-package/, 'name: other\n          path: allye-opencode-package')],
  ['no retention', release.replace('retention-days: 1', '')],
  ['no identity check', release.replace('= "allye-opencode"', '= "x"')],
  ['concurrency cancels', release.replace('cancel-in-progress: false', 'cancel-in-progress: true')],
  ['ref main', release.replace('${{ needs.release.outputs.sha }}', 'main')],
];
for (const [n, t] of mutations) {
  if (t === release) { failed++; console.error(`FAIL self-check ${n}: mutation did not apply`); continue; }
  if (checkRelease(t).length === 0) { failed++; console.error(`FAIL self-check ${n}: mutated sample passed`); }
  else console.log(`ok self-check ${n}`);
}
if (checkTest(testYml.replace('persist-credentials: false', '')).length === 0) { failed++; console.error('FAIL self-check test.yml'); }
else console.log('ok self-check test.yml');

report('LICENSE', /^MIT License/.test(read('LICENSE')) ? [] : ['root LICENSE must start with "MIT License"']);
try {
  const out = execFileSync('npm', ['pack', '--dry-run', '--json', '--ignore-scripts', './packages/allye-opencode'], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  const files = JSON.parse(out)[0].files.map((f) => f.path);
  report('npm pack lists LICENSE', files.includes('LICENSE') ? [] : ['LICENSE missing from pack']);
} catch (e) {
  report('npm pack lists LICENSE', [`npm pack failed: ${e.message}`]);
}

process.exit(failed ? 1 : 0);
