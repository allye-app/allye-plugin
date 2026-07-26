#!/bin/bash
set -e

# Allye Agent Plugin — Installer
# 1. Optionally prompts for an Allye PAT (used ONLY for skill seeding)
# 2. Validates PAT and seeds skills into Allye DB (skipped if no PAT)
# 3. Detects installed AI agents and configures OAuth-based MCP + manifests
#
# MCP authentication is OAuth 2.1 on every platform: the MCP endpoint
# (https://mcp.allye.app/mcp) is OAuth-gated, and each agent opens a browser
# for login on first tool use. No PAT is written into any MCP config.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEED_FILE="$SCRIPT_DIR/seed/seed-skills.json"

MCP_URL="https://mcp.allye.app/mcp"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║     Allye Agent Plugin Installer     ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
  echo ""
}

print_step() {
  echo -e "${BLUE}→${NC} $1"
}

print_success() {
  echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}!${NC} $1"
}

print_error() {
  echo -e "${RED}✗${NC} $1"
}

# ─── Step 0: Resolve the verb ─────────────────────────────────────────────────
# `status` and `uninstall` need no PAT and no seeding, and both are meant to be
# script-callable.  Steps 1-3 below prompt on stdin, so running them for every
# verb makes `./install.sh status` abort under closed stdin — exactly the CI and
# scripting case a status verb exists for.  Resolve the verb first and skip
# straight to dispatch for the two that read nothing.
ALLYE_VERB="${1:-install}"

case "$ALLYE_VERB" in
  install|uninstall|status) ;;
  *) echo "usage: ./install.sh [install [<agent>] | uninstall <agent> | status]" >&2; exit 2 ;;
esac

# ─── Step 1: Get Allye PAT (optional — skill seeding only) ────────────────────

API_URL="https://api.allye.app"

if [ "$ALLYE_VERB" = "install" ]; then
  # Steps 1-3 prompt on stdin and only serve `install`.  `status` and
  # `uninstall` skip them entirely so both stay script-callable.
  print_header

  echo "This installer will:"
  echo "  1. Configure your AI coding agents to use the Allye MCP server"
  echo "     (OAuth — your browser opens for login on first tool use)"
  echo "  2. Optionally seed workflow skills into your team's database"
  echo "     (this step — and only this step — needs a Personal Access Token)"
  echo ""

  # PAT — used exclusively for the skill-seeding API calls below.
  # MCP access does NOT use a PAT; it authenticates via OAuth in the agent.
  if [ -n "$ALLYE_PAT" ]; then
    print_step "Using ALLYE_PAT from environment (for skill seeding)"
    PAT="$ALLYE_PAT"
  else
    echo ""
    echo "A PAT is only needed to seed workflow skills into Allye Cloud."
    echo "Generate one in Allye: Settings → API → Generate Token"
    echo ""
    # Under `set -e`, `read` returns non-zero on EOF, which aborts the whole
  # script — so a non-interactive run (CI, a pipeline, `</dev/null`) died here
  # before reaching any verb.  Prompt only when there is a terminal to prompt.
  if [ -t 0 ]; then
    read -rsp "Allye PAT (press Enter to skip skill seeding): " PAT || PAT=""
  else
    PAT=""
    echo "  (non-interactive: skipping skill seeding)"
  fi
    echo ""
  fi

  if [ -z "$PAT" ]; then
    print_warning "No PAT provided — skill seeding will be skipped."
  fi

  # ─── Step 2: Validate PAT (only if provided) ──────────────────────────────────

  if [ -n "$PAT" ]; then
    print_step "Validating credentials..."

    PROFILE_RESPONSE=$(curl -s --max-time 10 -w "\n%{http_code}" \
      -H "Authorization: Bearer $PAT" \
      "$API_URL/api/auth/profile" 2>/dev/null) || {
      print_error "Could not connect to $API_URL"
      exit 1
    }

    HTTP_CODE=$(echo "$PROFILE_RESPONSE" | tail -1)
    PROFILE_BODY=$(echo "$PROFILE_RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" != "200" ]; then
      print_error "Authentication failed (HTTP $HTTP_CODE). Check your PAT."
      exit 1
    fi

    USER_NAME=$(echo "$PROFILE_BODY" | jq -r '.name // .email // "Unknown"')
    TENANT_NAME=$(echo "$PROFILE_BODY" | jq -r '.tenant.name // "Unknown"')
    print_success "Authenticated as $USER_NAME ($TENANT_NAME)"
  fi

  # ─── Step 3: Seed Skills (only if PAT provided) ───────────────────────────────

  SKILL_COUNT=0
  SEEDED=0
  UPDATED=0
  FAILED=0

  if [ -n "$PAT" ]; then
    echo ""
    print_step "Seeding skills into Allye..."

    if [ ! -f "$SEED_FILE" ]; then
      print_error "Seed file not found: $SEED_FILE"
      exit 1
    fi

    SKILL_COUNT=$(jq '.skills | length' "$SEED_FILE")

    for i in $(seq 0 $((SKILL_COUNT - 1))); do
      SKILL=$(jq ".skills[$i]" "$SEED_FILE")
      SKILL_NAME=$(echo "$SKILL" | jq -r '.name')
      SKILL_SLUG=$(echo "$SKILL" | jq -r '.slug')
      SKILL_DESC=$(echo "$SKILL" | jq -r '.description')
      SKILL_CAT=$(echo "$SKILL" | jq -r '.category')
      SOURCE_FILE=$(echo "$SKILL" | jq -r '.source_file')

      # Read content from source file
      CONTENT_FILE="$SCRIPT_DIR/$SOURCE_FILE"
      if [ ! -f "$CONTENT_FILE" ]; then
        print_warning "Skipping $SKILL_NAME — source file not found: $SOURCE_FILE"
        FAILED=$((FAILED + 1))
        continue
      fi

      SKILL_CONTENT=$(cat "$CONTENT_FILE")

      # Check if skill already exists
      EXISTING=$(curl -s --max-time 10 \
        -H "Authorization: Bearer $PAT" \
        "$API_URL/api/skills?slug=$SKILL_SLUG" 2>/dev/null)

      EXISTING_ID=$(echo "$EXISTING" | jq -r '.data[0].id // empty' 2>/dev/null)

      if [ -n "$EXISTING_ID" ]; then
        # Update existing skill
        RESPONSE=$(curl -s --max-time 10 -w "\n%{http_code}" \
          -X PATCH \
          -H "Authorization: Bearer $PAT" \
          -H "Content-Type: application/json" \
          -d "$(jq -n \
            --arg name "$SKILL_NAME" \
            --arg desc "$SKILL_DESC" \
            --arg content "$SKILL_CONTENT" \
            --arg cat "$SKILL_CAT" \
            '{name: $name, description: $desc, content: $content, category: $cat}')" \
          "$API_URL/api/skills/$EXISTING_ID" 2>/dev/null)

        RC=$(echo "$RESPONSE" | tail -1)
        if [ "$RC" = "200" ] || [ "$RC" = "204" ]; then
          print_success "$SKILL_NAME (updated)"
          UPDATED=$((UPDATED + 1))
        else
          print_warning "$SKILL_NAME (update failed — HTTP $RC)"
          FAILED=$((FAILED + 1))
        fi
      else
        # Create new skill
        RESPONSE=$(curl -s --max-time 10 -w "\n%{http_code}" \
          -X POST \
          -H "Authorization: Bearer $PAT" \
          -H "Content-Type: application/json" \
          -d "$(jq -n \
            --arg name "$SKILL_NAME" \
            --arg slug "$SKILL_SLUG" \
            --arg desc "$SKILL_DESC" \
            --arg content "$SKILL_CONTENT" \
            --arg cat "$SKILL_CAT" \
            '{name: $name, slug: $slug, description: $desc, content: $content, category: $cat}')" \
          "$API_URL/api/skills" 2>/dev/null)

        RC=$(echo "$RESPONSE" | tail -1)
        if [ "$RC" = "200" ] || [ "$RC" = "201" ]; then
          print_success "$SKILL_NAME (created)"
          SEEDED=$((SEEDED + 1))
        else
          print_warning "$SKILL_NAME (create failed — HTTP $RC)"
          FAILED=$((FAILED + 1))
        fi
      fi
    done

    echo ""
    echo "  Skills: $SEEDED created, $UPDATED updated, $FAILED failed"
  else
    echo ""
    print_warning "Skill seeding skipped (no PAT). Re-run with ALLYE_PAT set to seed skills."
  fi

fi

# ─── Step 4: install / uninstall / status ─────────────────────────────────────

source "$SCRIPT_DIR/install/lib.sh"

echo ""

case "${1:-install}" in
  install)   allye_install "${2:-}" ;;
  uninstall) allye_uninstall "${2:?agent id required}" ;;
  status)    allye_status ;;
  *) echo "usage: ./install.sh [install [<agent>] | uninstall <agent> | status]" >&2; exit 2 ;;
esac

# ─── Done ──────────────────────────────────────────────────────────────────────

if [ "${1:-install}" = "install" ]; then
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║       Installation complete!         ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
  echo ""
  if [ -n "$PAT" ]; then
    echo "  Skills seeded: $((SEEDED + UPDATED))/$SKILL_COUNT"
  else
    echo "  Skills seeded: skipped (no PAT)"
  fi
  echo ""
  echo "Start a new session in your AI agent to use the Allye plugin."
  echo "On first Allye tool use, your browser will open for OAuth login."
  echo ""
fi
