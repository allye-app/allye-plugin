#!/bin/bash
# Allye — Claude Code SessionStart hook.
# Injects the shared bootstrap (bootstrap/allye.md) as additionalContext so the
# agent knows the Allye MCP and the Bridge skill are available, plus a repo
# block (git remote, unverified .allye/project.json claim, project_resolve
# instruction) when the session's cwd is a git repository.
# Offline and side-effect free: the only external commands are `git config`
# (local repo config only) and `jq`. Any failure degrades to bootstrap only.
set -euo pipefail
export LC_ALL=C  # byte semantics for every pattern and length check below

SELF_DIR=.
case "${BASH_SOURCE[0]}" in */*) SELF_DIR="${BASH_SOURCE[0]%/*}" ;; esac
PLUGIN_ROOT="$(cd "$SELF_DIR/.." && pwd)"
BOOTSTRAP="$PLUGIN_ROOT/bootstrap/allye.md"

if [ -f "$BOOTSTRAP" ] && [ -r "$BOOTSTRAP" ]; then
  BOOT=$(<"$BOOTSTRAP")
else
  BOOT="Allye bootstrap file is missing at $BOOTSTRAP; reinstall the plugin with /plugin update allye."
fi

# Pure-bash JSON string escaper, used when jq is unavailable or fails.
json_escape() {
  local s=$1 i c u
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  for i in {1..31}; do
    printf -v c "\\$(printf '%03o' "$i")"
    printf -v u '\\u%04x' "$i"
    s=${s//"$c"/$u}
  done
  printf '%s' "$s"
}

# Emit the hook output for the given context; falls back to the bootstrap
# alone, escaped in bash, if jq is missing or fails.
emit() {
  local ctx=$1 out
  if [ -n "$HAVE_JQ" ] && out=$(jq -n --arg ctx "$ctx" '{
      hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: $ctx }
    }' 2>/dev/null); then
    printf '%s\n' "$out"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$(json_escape "$BOOT")"
  fi
  exit 0
}

HAVE_JQ=""
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# Hook input, read with a builtin (no external command); EOF ends the read.
INPUT=""
IFS= read -r -d '' INPUT 2>/dev/null || true
[ -n "$HAVE_JQ" ] || emit "$BOOT"
command -v git >/dev/null 2>&1 || emit "$BOOT"

# Hook input cwd only; never fall back to $PWD.
CWD=$(printf '%s' "$INPUT" | jq -j '.cwd | strings' 2>/dev/null) || emit "$BOOT"
[ -n "$CWD" ] && [ -d "$CWD" ] || emit "$BOOT"

# Read only the repository's local config; ignore inherited repo overrides.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
export GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0

# remote.origin.url, else the first remote.*.url. Exit 1 = key absent (still a
# repo); anything else (not a repo, unreadable config) = bootstrap only.
# A value with an embedded newline prints raw and is dropped below.
REMOTE=""
rc=0
REMOTE=$(git -C "$CWD" config --local --get remote.origin.url 2>/dev/null) || rc=$?
if [ "$rc" -eq 1 ]; then
  rc=0
  KEY=$(git -C "$CWD" config --local --name-only --get-regexp '^remote\..*\.url$' 2>/dev/null) || rc=$?
  KEY=${KEY%%$'\n'*}
  if [ "$rc" -eq 0 ] && [ -n "$KEY" ]; then
    REMOTE=$(git -C "$CWD" config --local --get "$KEY" 2>/dev/null) || rc=$?
  elif [ "$rc" -eq 1 ]; then
    rc=0; REMOTE=""
  fi
fi
[ "$rc" -eq 0 ] || emit "$BOOT"

# Allowlist (ASCII URL characters, no backtick or whitespace); otherwise the
# remote is dropped and never echoed.
URL_CHARS="^[A-Za-z0-9._~:/?#@!\$&'()*+,;=%-]+\$"
[[ "$REMOTE" =~ $URL_CHARS ]] || REMOTE=""
# Strip credentials: query and fragment, userinfo of scheme URLs, and scp
# userinfo that carries a password (a ':' before its last '@').
REMOTE=${REMOTE%%[?#]*}
if [ -n "$REMOTE" ]; then
  if [[ "$REMOTE" =~ ^([A-Za-z][A-Za-z0-9+.-]*://)([^/]*@)(.*)$ ]]; then
    REMOTE="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"
  elif [[ "$REMOTE" != *://* ]]; then
    HEAD=${REMOTE%%/*}
    if [[ "$HEAD" == *@* ]]; then
      USERINFO=${HEAD%@*}
      [[ "$USERINFO" != *:* ]] || REMOTE=${REMOTE#"$USERINFO@"}
    fi
  fi
fi

# Link file: validated by jq; raw values are never echoed.
CLAIM=""
WARNINGS=()
LINK_DIR="$CWD/.allye"
LINK="$LINK_DIR/project.json"
if [ -e "$LINK" ] || [ -L "$LINK" ] || [ -L "$LINK_DIR" ]; then
  LINK_OUT=""
  LINK_BUF=""
  # Regular file, no symlink, at most 4096 bytes and no NUL (bash read only:
  # a NUL ends the read early, 4097 bytes means oversized).
  if [ ! -L "$LINK_DIR" ] && [ ! -L "$LINK" ] && [ -f "$LINK" ] && [ -r "$LINK" ]; then
    if IFS= read -r -d '' -n 4097 LINK_BUF < "$LINK" 2>/dev/null; then
      LINK_BUF=""   # stopped at a NUL or at 4097 bytes: invalid
    elif [ "${#LINK_BUF}" -gt 4096 ]; then
      LINK_BUF=""
    fi
  fi
  if [ -n "$LINK_BUF" ]; then
    LINK_OUT=$(printf '%s' "$LINK_BUF" | jq -r -s '
      if length != 1 or (.[0] | type) != "object" then "invalid"
      else .[0] as $o
        | ($o.project) as $p | ($o.app) as $a
        | if ($p | type) == "string" and ($p | test("\\A[A-Z][A-Z0-9]{1,9}\\z"))
             and ($a == null or (($a | type) == "string" and ($a | test("\\A[A-Za-z0-9._-]{1,120}\\z"))))
          then "ok\t\($p)\t\($a // "")\t\(if ($o | keys - ["project", "app"] | length) > 0 then "extra" else "" end)"
          else "invalid" end
      end' 2>/dev/null) || LINK_OUT=""
  fi
  if [[ "$LINK_OUT" =~ ^ok$'\t'([A-Z][A-Z0-9]{1,9})$'\t'([A-Za-z0-9._-]{0,120})$'\t'(extra)?$ ]]; then
    CLAIM="this repo claims project ${BASH_REMATCH[1]}"
    [ -z "${BASH_REMATCH[2]}" ] || CLAIM+=" / app ${BASH_REMATCH[2]}"
    CLAIM+=" (from .allye/project.json, unverified)"
    [ -z "${BASH_REMATCH[3]}" ] || WARNINGS+=("warning: .allye/project.json has unknown keys; they were ignored.")
  else
    WARNINGS+=("warning: .allye/project.json is invalid (unparseable, or a missing or invalid project/app); it was ignored.")
  fi
fi

[ -n "$REMOTE" ] || [ -n "$CLAIM" ] || [ "${#WARNINGS[@]}" -gt 0 ] || emit "$BOOT"

BLOCK=$'\n\n## This repository\n'
[ -z "$REMOTE" ] || BLOCK+="- git remote: $REMOTE"$'\n'
[ -z "$CLAIM" ] || BLOCK+="- $CLAIM"$'\n'
for w in "${WARNINGS[@]+"${WARNINGS[@]}"}"; do BLOCK+="- $w"$'\n'; done
if [ -n "$REMOTE" ]; then
  BLOCK+="- Before the first project-scoped call, run \`projects.project_resolve repository_url=$REMOTE\` to identify this repo's Allye project. Use a link claim only if it agrees with the resolution; otherwise ask once, showing both, before proceeding."
elif [ -n "$CLAIM" ]; then
  BLOCK+="- No git remote is configured, so the claim cannot be verified: confirm it once before the first project-scoped call."
else
  BLOCK+="- No git remote is configured: ask which Allye project this repo belongs to when one is needed."
fi

emit "$BOOT$BLOCK"
