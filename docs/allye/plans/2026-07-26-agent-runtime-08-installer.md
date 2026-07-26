# Unified Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One installer that detects which agents are present and installs Allye into each by the path that agent actually uses — MCP for those that fetch it, skills on disk for those that read it. Hermes becomes the sixth supported agent, which is the only way to prove the adapter shape is real.

**Architecture:** Three verbs — `install`, `uninstall`, `status` — over a table of per-agent adapters held as data. Format writers stay as code, because writing TOML genuinely differs from writing JSON. A version marker inside each installed file makes `status` a read rather than a registry, copied from Herdr's working implementation.

**Tech Stack:** Bash, `jq`, `curl`. **No new runtime dependency** — the installer's whole appeal is that it runs on a fresh machine.

## Global Constraints

- **Conventional Commits are enforced in CI.** Valid types: `feat`, `fix`, `docs`, `refactor`, `chore`.
- **Never add a `Co-Authored-By` trailer.**
- **Tool names, action names, and parameter names are an API contract.** Never rename one.
- **Attribution comments stay.** Twenty-two exist across `skills/` and `agents/`; this plan removes none.
- **No new dependency.** Bash, `curl`, `jq` only. Not Python, not Node.
- **Never overwrite a config you did not write.** Every write to a user's agent config is additive and idempotent — read, merge, write. A user's own MCP servers, plugins, and settings survive untouched.
- **Do not push. Do not merge to `main`.**

<HARD-GATE>
**Every verification step runs against a sandboxed `HOME`, never the real one.**

```bash
export ALLYE_TEST_HOME=/tmp/allye-install-test
rm -rf "$ALLYE_TEST_HOME" && mkdir -p "$ALLYE_TEST_HOME"
HOME="$ALLYE_TEST_HOME" ./install.sh status
```

You are a Claude Code session. `~/.claude.json` and `~/.claude/settings.json` are **your own configuration** — corrupting one ends this session and every future one on this machine, and the damage is not visible until the next start. `~/.hermes/config.yaml` holds a live agent the human is using right now, with API keys in it.

Detection uses `command -v`, which is unaffected by `HOME`, so agents are still detected under the sandbox and the writers are exercised for real. There is no fidelity lost — only the blast radius.

**Never run an install verb without `HOME` overridden.** If a step in this plan appears to ask you to, it is the plan that is wrong: stop and report it.
</HARD-GATE>

## Prerequisites

Plans 01–07 complete and merged.

```bash
wc -l install.sh                          # 419 — the file being replaced
ls -d skills/*/ | wc -l                   # 17
jq '.skills|length' seed/seed-skills.json # 16
ls manifests/                             # claude codex cursor gemini opencode
```

Read **§19 of the spec** before Task 1.

## Facts verified against live installs — do not re-derive these

**Herdr's version-marker pattern**, the mechanism that makes `status` work, from `~/.hermes/plugins/herdr-agent-state/__init__.py` line 4:

```python
# HERDR_INTEGRATION_VERSION=3
```

**Hermes plugin shape** — a directory under `~/.hermes/plugins/<name>/` holding `plugin.yaml` (`name`, `version`, `description`) and `__init__.py` exporting `register(ctx)`. Hooks are registered as `ctx.register_hook("on_session_start", fn)`. Enabling requires the plugin name in `plugins.enabled` in `~/.hermes/config.yaml`.

**Hermes skill shape** — `~/.hermes/skills/<category>/<name>/SKILL.md`, frontmatter carrying `name`, `description`, `version`, optional `platforms` and `metadata.hermes.tags`.

**Hermes MCP config** — a `mcp_servers.<name>` block in `~/.hermes/config.yaml` with `url`, `auth: oauth`, `enabled: true`. OAuth requires an interactive TTY; `hermes mcp add` from a non-interactive shell refuses correctly rather than hanging.

**The five existing agents' paths** are already encoded in `install.sh` — read them out of it rather than looking them up again.

---

### Task 1: Define the adapter table

**Files:**
- Create: `install/adapters.json`

**Interfaces:**
- Consumes: nothing.
- Produces: the adapter schema every later task reads. Field names are the contract — Tasks 2–5 use them literally.

- [x] **Step 1: Write the table**

Create `install/adapters.json`. One object per agent; the six existing agents' paths come from reading `install.sh`, not from memory.

```json
{
  "version": 1,
  "agents": [
    {
      "id": "claude",
      "label": "Claude Code",
      "detect": { "command": "claude" },
      "mcp": { "path": "~/.claude.json", "format": "json", "key": "mcpServers.allye" },
      "skills": { "source": "mcp" },
      "bootstrap": { "kind": "hook", "path": "~/.claude/settings.json", "format": "json" }
    },
    {
      "id": "hermes",
      "label": "Hermes Agent",
      "detect": { "command": "hermes" },
      "mcp": { "path": "~/.hermes/config.yaml", "format": "yaml-block", "key": "mcp_servers.allye", "interactive_auth": true },
      "skills": { "source": "disk", "path": "~/.hermes/skills/allye", "export_format": "claude", "layout": "category-dir" },
      "bootstrap": { "kind": "plugin", "path": "~/.hermes/plugins/allye-bootstrap", "enable_key": "plugins.enabled" }
    }
  ]
}
```

Fill the remaining four — `cursor`, `opencode`, `codex`, `gemini` — from `install.sh`'s existing blocks. Each keeps `"skills": {"source": "mcp"}`; only Hermes reads from disk today.

Field meanings, which Tasks 2–5 depend on:

| Field | Meaning |
|---|---|
| `detect.command` | Agent is present if this is on `PATH`. Some agents also warrant a directory check — add `detect.dir` where `install.sh` already does one. |
| `mcp.format` | Selects the writer: `json`, `toml`, `yaml-block`. |
| `mcp.interactive_auth` | The agent's OAuth needs a TTY. `install` reports this rather than attempting it. |
| `skills.source` | `mcp` — the agent fetches them; seed to the API. `disk` — write files to `skills.path`. |
| `bootstrap.kind` | `hook`, `plugin`, or absent. |

- [x] **Step 2: Verify**

```bash
jq -e '.agents | length == 6' install/adapters.json
jq -r '.agents[].id' install/adapters.json | sort | tr '\n' ' '
jq -e '[.agents[] | select(.skills.source == "disk")] | length == 1' install/adapters.json
jq -e '[.agents[] | select(has("detect") and has("mcp") and has("skills"))] | length == 6' install/adapters.json
```
Expected: six agents — `claude codex cursor gemini hermes opencode`; exactly one reading skills from disk; every entry carrying the three required keys.

- [x] **Step 3: Commit**

```bash
git add install/adapters.json
git commit -m "feat(install): describe every supported agent as data

One entry per agent: how to detect it, where its MCP config lives and in
what format, whether it fetches skills or reads them from disk, and how
it bootstraps. Adding a seventh agent becomes an entry plus, at most,
reusing an existing format writer."
```

---

### Task 2: Build the three verbs

**Files:**
- Create: `install/lib.sh`
- Modify: `install.sh`

**Interfaces:**
- Consumes: Task 1's schema.
- Produces: `allye_install <id>`, `allye_uninstall <id>`, `allye_status`, and the writers Task 3 and Task 4 call.

- [x] **Step 1: Write the shared library**

`install/lib.sh` holds detection, the version marker, the format writers, and the three verbs. Structure it so `install.sh` becomes argument parsing plus a dispatch.

**The version marker** — the mechanism the whole `status` verb rests on:

```bash
ALLYE_INSTALLER_VERSION=1

# Every file this installer writes carries its version on a comment line, in
# whatever comment syntax the file uses. `status` reads it back rather than
# keeping a registry, so a file edited or removed by hand reports honestly.
allye_marker() {  # $1 = comment prefix
  printf '%s ALLYE_INSTALLER_VERSION=%s\n' "$1" "$ALLYE_INSTALLER_VERSION"
}

allye_installed_version() {  # $1 = path → prints version, or nothing
  [ -f "$1" ] || return 1
  grep -o 'ALLYE_INSTALLER_VERSION=[0-9]\+' "$1" 2>/dev/null | head -1 | cut -d= -f2
}
```

**The format writers.** Three functions, each additive and idempotent:

```bash
write_mcp_json()       # jq merge into an object key; creates the file if absent
write_mcp_toml()       # append a [block] only when the key is absent
write_mcp_yaml_block() # append a top-level block only when the key is absent
```

<HARD-GATE>
Every writer reads the existing file, merges, and writes back. **Never truncate a user's config.** They hold the user's own MCP servers, plugins, model settings, and API keys — clobbering one to add ours would be the single worst thing this installer could do, and it would happen silently.

Running `install` twice must produce exactly the same file as running it once. Assert that in Step 3.
</HARD-GATE>

**The verbs:**

- `allye_status` — for each adapter: detected or not; if detected, the installed version read from its marker, compared against `ALLYE_INSTALLER_VERSION`. Prints `current (vN)`, `outdated (vN)`, `not installed`, or `not detected`, plus the path. One line per agent, aligned.
- `allye_install [id]` — with no id, every detected agent. With an id, that one, and it says so plainly if that agent is not detected rather than installing into nothing.
- `allye_uninstall <id>` — removes only what this installer wrote, identified by the marker. **Never removes a config file**; it removes the key or block it added.

- [x] **Step 2: Rewrite `install.sh` as a dispatcher**

Keep Steps 1–3 (PAT, validation, seeding) as they are — they work. Replace Step 4's five per-agent blocks with:

```bash
source "$SCRIPT_DIR/install/lib.sh"

case "${1:-install}" in
  install)   allye_install "${2:-}" ;;
  uninstall) allye_uninstall "${2:?agent id required}" ;;
  status)    allye_status ;;
  *) echo "usage: ./install.sh [install [<agent>] | uninstall <agent> | status]" >&2; exit 2 ;;
esac
```

Bare `./install.sh` still installs everything detected — the existing behaviour and the one most people will run.

- [x] **Step 3: Verify idempotency, which is the property most likely to break**

```bash
export ALLYE_TEST_HOME=/tmp/allye-install-test
rm -rf "$ALLYE_TEST_HOME" && mkdir -p "$ALLYE_TEST_HOME"
bash -n install.sh install/lib.sh && echo "syntax ok"
HOME="$ALLYE_TEST_HOME" ./install.sh status
HOME="$ALLYE_TEST_HOME" ./install.sh install claude >/dev/null
cp "$ALLYE_TEST_HOME/.claude.json" /tmp/allye-idem-2.json
HOME="$ALLYE_TEST_HOME" ./install.sh install claude >/dev/null
cp "$ALLYE_TEST_HOME/.claude.json" /tmp/allye-idem-3.json
diff /tmp/allye-idem-2.json /tmp/allye-idem-3.json && echo "IDEMPOTENT" || echo "NOT IDEMPOTENT — fix before continuing"
jq -e . "$ALLYE_TEST_HOME/.claude.json" >/dev/null && echo "still valid JSON"
```
Expected: syntax clean; `status` prints one line per agent; the second and third installs produce byte-identical files; the config parses.

Also assert the writer **merges rather than truncates**, which the idempotency check alone would not catch — an installer that overwrites with only its own key is perfectly idempotent and perfectly destructive:

```bash
echo '{"mcpServers":{"userOwn":{"url":"http://example.invalid"}}}' > "$ALLYE_TEST_HOME/.claude.json"
HOME="$ALLYE_TEST_HOME" ./install.sh install claude >/dev/null
jq -e '.mcpServers.userOwn and .mcpServers.allye' "$ALLYE_TEST_HOME/.claude.json" && echo "MERGED — user key survived"
```

- [x] **Step 4: Commit**

```bash
git add install/lib.sh install.sh
git commit -m "feat(install): three verbs over the adapter table

install, uninstall, and status replace five copied per-agent blocks. The
version marker lives inside each written file, so status is a read rather
than a registry — a file edited by hand reports honestly.

Every writer merges rather than truncates. These files hold the user's own
MCP servers and API keys; clobbering one to add ours would fail silently
and be unrecoverable."
```

---

### Task 3: Write skills to disk for agents that read them there

**Files:**
- Modify: `install/lib.sh`

**Interfaces:**
- Consumes: `skills.source == "disk"` and `skills.path` from the adapter.
- Produces: `install_skills_to_disk <agent-id>`, called by `allye_install`.

- [x] **Step 1: Add the function**

For an adapter with `skills.source == "disk"`, export each seeded skill in `skills.export_format` and write it to `<skills.path>/<name>/SKILL.md`.

Source of truth is `seed/seed-skills.json` — the same list seeded to the API, so an agent reading from disk gets exactly what the others fetch. Each skill's `source_file` gives the local path; the export format matters only if the target agent needs different frontmatter (see Step 2).

<HARD-GATE>
A skill goes to **either** the API **or** disk for a given agent, never both. Two copies that can drift is the duplication failure mode, and a stale on-disk copy silently shadowing a fresh seeded one is the worst version of it — the agent reads confidently from the wrong file.

The adapter's `skills.source` is what decides. Do not "helpfully" do both.
</HARD-GATE>

Every written `SKILL.md` carries the version marker as an HTML comment after the frontmatter, so `status` and `uninstall` can identify what this installer put there.

- [x] **Step 2: Confirm the format actually transfers**

Hermes reads `SKILL.md` with YAML frontmatter following the agentskills.io standard; the adapter says `export_format: "claude"` on the expectation that it transfers unchanged. **Verify rather than assume**: install one skill, then read it back.

```bash
HOME="$ALLYE_TEST_HOME" ./install.sh install hermes
ls "$ALLYE_TEST_HOME/.hermes/skills/allye/"
head -12 "$ALLYE_TEST_HOME/.hermes/skills/allye/using-allye/SKILL.md"
```

Expected: our four frontmatter keys present and parseable. If Hermes requires anything ours lacks, add it in the writer and record what was needed in your report — that is a finding worth having, and it is the argument for a `hermes` export format upstream in `allye-mcp`.

- [x] **Step 3: Verify**

```bash
jq -r '.skills[].slug' seed/seed-skills.json | sort > /tmp/seeded.txt
ls "$ALLYE_TEST_HOME/.hermes/skills/allye/" | sort > /tmp/ondisk.txt
diff /tmp/seeded.txt /tmp/ondisk.txt && echo "disk matches the seed exactly"
grep -c 'ALLYE_INSTALLER_VERSION' "$ALLYE_TEST_HOME/.hermes/skills/allye/using-allye/SKILL.md"
```
Expected: the sixteen seeded skills present on disk, no more and no fewer; the marker present.

- [x] **Step 4: Commit**

```bash
git add install/lib.sh
git commit -m "feat(install): write skills to disk for agents that read them there

An agent that fetches skills over MCP gets them seeded to the API; one
that reads a directory gets files. Never both for the same agent — a
stale on-disk copy shadowing a fresh seeded one fails silently, and the
agent reads confidently from the wrong file."
```

---

### Task 4: Add Hermes as the sixth agent

Three artifacts: the MCP block, the skills (Task 3 handles those), and a bootstrap plugin so `using-allye` reaches the session.

**Files:**
- Create: `manifests/hermes/plugin.yaml`
- Create: `manifests/hermes/__init__.py`
- Modify: `install/lib.sh`

- [x] **Step 1: Write the bootstrap plugin**

`manifests/hermes/plugin.yaml`:

```yaml
name: allye-bootstrap
version: "1.0"
description: Inject the Allye methodology bootstrap at session start
```

`manifests/hermes/__init__.py` — the version marker on line 4, mirroring the pattern Herdr's own plugin uses:

```python
"""Allye bootstrap for Hermes Agent."""
# installed by the Allye plugin installer
# edit the source at manifests/hermes/, not this copy — reinstalling overwrites it
# ALLYE_INSTALLER_VERSION=1

from __future__ import annotations

import os
from pathlib import Path

_SKILL = Path.home() / ".hermes" / "skills" / "allye" / "using-allye" / "SKILL.md"


def _bootstrap(ctx, *_args, **_kwargs):
    """Inject the Allye bootstrap skill once, at session start.

    Reads from disk rather than over MCP: Hermes may not have completed MCP
    discovery when this fires, and a bootstrap that sometimes arrives is worse
    than one that always does.
    """
    try:
        if not _SKILL.is_file():
            return
        ctx.inject_message(_SKILL.read_text(encoding="utf-8"), role="user")
    except Exception:
        # A failed bootstrap must never break the session. The agent works
        # without the methodology; it does not work if startup raises.
        pass


def register(ctx):
    ctx.register_hook("on_session_start", _bootstrap)
```

- [x] **Step 2: Install it from the adapter**

Extend the `bootstrap.kind == "plugin"` path: copy `manifests/hermes/` to `bootstrap.path`, then add the plugin name to `plugins.enabled` in `~/.hermes/config.yaml` — **appending to the list, not replacing it.** The user already has `herdr-agent-state` there and it must survive.

- [x] **Step 3: Handle interactive OAuth honestly**

`mcp.interactive_auth` is true for Hermes: its OAuth needs a TTY, and a non-interactive `hermes mcp add` correctly refuses. Write the config block, then **tell the user what to run**:

```
  ⚠ Hermes MCP needs an interactive login. Run this in a terminal:
      hermes mcp add allye --url <url> --auth oauth
```

Do not attempt it, and do not report success. A silent half-install is worse than a clear instruction.

- [x] **Step 4: Verify**

Seed the sandbox with a config that already has a plugin, so the append is genuinely tested:

```bash
mkdir -p "$ALLYE_TEST_HOME/.hermes"
printf 'plugins:\n  enabled:\n    - herdr-agent-state\n' > "$ALLYE_TEST_HOME/.hermes/config.yaml"
HOME="$ALLYE_TEST_HOME" ./install.sh install hermes
ls "$ALLYE_TEST_HOME/.hermes/plugins/allye-bootstrap/"
grep -c 'ALLYE_INSTALLER_VERSION=1' "$ALLYE_TEST_HOME/.hermes/plugins/allye-bootstrap/__init__.py"
python3 -c "import ast; ast.parse(open('$ALLYE_TEST_HOME/.hermes/plugins/allye-bootstrap/__init__.py').read()); print('valid python')"
grep -A4 'plugins:' "$ALLYE_TEST_HOME/.hermes/config.yaml"
HOME="$ALLYE_TEST_HOME" ./install.sh status
```
Expected: the plugin directory present with both files; the marker on line 4; the Python parses; `plugins.enabled` contains **both** `herdr-agent-state` and `allye-bootstrap` — the pre-existing entry surviving is the point of this test; `status` reports hermes as `current (v1)`.

- [x] **Step 5: Commit**

```bash
git add manifests/hermes/ install/lib.sh
git commit -m "feat(install): support Hermes Agent as the sixth agent

MCP block, skills written to its directory, and a Python plugin whose
on_session_start hook injects the bootstrap. The hook reads the skill from
disk rather than over MCP, because discovery may not have completed when
it fires and a bootstrap that sometimes arrives is worse than one that
always does.

Hermes OAuth needs a TTY, so the installer writes the config and prints
the command rather than attempting it. A silent half-install is worse than
a clear instruction."
```

---

### Task 5: Fold the scattered pieces together and document

**Files:**
- Modify: `README.md`, `CLAUDE.md`
- Create: `docs/install-hermes.md`, `docs/update-hermes.md`

- [ ] **Step 1: Document the three verbs**

`README.md`'s Installation section gains the unified path as the primary route, with the per-agent marketplace and paste-into-agent instructions kept for people who prefer them.

```bash
./install.sh          # every detected agent
./install.sh status   # what is installed, and at which version
./install.sh install hermes
./install.sh uninstall hermes
```

- [ ] **Step 2: Add the Hermes guides**

`docs/install-hermes.md` and `docs/update-hermes.md`, matching the existing four in shape. Both must state the interactive-OAuth step plainly — it is the one part that cannot be automated.

- [ ] **Step 3: Update the architecture section**

`CLAUDE.md`'s "Two parallel distribution mechanisms" section describes `install.sh` as configuring "MCP connections, the Claude Code hook/env, and the OpenCode plugin array". That is now wrong in three ways: six agents not five, skills-to-disk is new, and the three verbs replace the flat run. Rewrite it, and describe `install/adapters.json` as the place a seventh agent is added.

- [ ] **Step 4: Verify**

```bash
grep -c 'install.sh status' README.md
ls docs/install-hermes.md docs/update-hermes.md
grep -c 'adapters.json' CLAUDE.md
grep -on 'six agents\|6 agents\|five agents\|5 agents' README.md CLAUDE.md
```
Expected: the verbs documented; both guides present; `adapters.json` named in the architecture; and **no surviving mention of five agents** — that count is now wrong everywhere it appears.

- [ ] **Step 5: Commit**

```bash
git add README.md CLAUDE.md docs/install-hermes.md docs/update-hermes.md
git commit -m "docs: the unified installer and Hermes as the sixth agent

Documents install, uninstall and status as the primary route, adds the
Hermes guides, and corrects the architecture section — six agents, skills
written to disk for those that read them there, and adapters.json as the
place a seventh is added."
```

---

## What this plan deliberately does not do

- **No new runtime dependency.** Bash, `curl`, `jq`. The installer's value is running on a machine where nothing is set up yet, and requiring Python or Node to install a plugin would trade that away for tidier code.
- **No attempt at Hermes's interactive OAuth.** It needs a TTY and correctly refuses without one. The installer prepares everything else and prints one command.
- **No fix for `hermes -z` missing MCP tools.** `_should_background_mcp_startup()` excludes one-shot mode; that is upstream's to fix and is recorded in §19. The gateway path — which is the one that matters for using Hermes remotely — works.
- **No `hermes` export format in `allye-mcp`.** Task 3 Step 2 tests whether `claude` transfers. If it does not, that finding is the argument for adding one, in that repository.
- **No migration of existing installs.** A machine already configured by the old `install.sh` keeps working; running the new one is additive and idempotent.
