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

# ─── Step 1: Get Allye PAT (optional — skill seeding only) ────────────────────

API_URL="https://api.allye.app"

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
  read -rsp "Allye PAT (press Enter to skip skill seeding): " PAT
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

# ─── Step 4: Detect and Configure Agents (OAuth-based MCP) ────────────────────

echo ""
print_step "Detecting installed AI agents..."

AGENTS_CONFIGURED=0

# Claude Code
if command -v claude &>/dev/null; then
  print_success "Claude Code detected"

  CLAUDE_SETTINGS_DIR="$HOME/.claude"
  CLAUDE_SETTINGS="$CLAUDE_SETTINGS_DIR/settings.json"

  mkdir -p "$CLAUDE_SETTINGS_DIR"

  # Read existing settings or create empty object
  if [ -f "$CLAUDE_SETTINGS" ]; then
    SETTINGS=$(cat "$CLAUDE_SETTINGS")
  else
    SETTINGS='{}'
  fi

  # Add SessionStart hook
  HOOK_CMD="\"$SCRIPT_DIR/manifests/claude/hooks/session-start.sh\""

  SETTINGS=$(echo "$SETTINGS" | jq \
    --arg cmd "$HOOK_CMD" \
    '
    .hooks.SessionStart = (.hooks.SessionStart // []) |
    if (.hooks.SessionStart | any(.hooks[]?.command == $cmd)) then
      .
    else
      .hooks.SessionStart += [
        {
          "matcher": "startup|resume",
          "hooks": [
            {
              "type": "command",
              "command": $cmd,
              "timeout": 15
            }
          ]
        }
      ]
    end
    ')

  # ALLYE_PAT in settings env is used only by the session-start hook's
  # skill-fetch API call — never for MCP auth (that's OAuth).
  if [ -n "$PAT" ]; then
    SETTINGS=$(echo "$SETTINGS" | jq \
      --arg pat "$PAT" \
      '.env = (.env // {}) | .env.ALLYE_PAT = $pat')
  fi

  echo "$SETTINGS" | jq '.' > "$CLAUDE_SETTINGS"
  print_success "Claude Code hook configured"

  # Add Allye MCP server to ~/.claude.json (OAuth — no PAT headers)
  CLAUDE_JSON="$HOME/.claude.json"
  if [ -f "$CLAUDE_JSON" ]; then
    CLAUDE_CFG=$(cat "$CLAUDE_JSON")
  else
    CLAUDE_CFG='{}'
  fi

  CLAUDE_CFG=$(echo "$CLAUDE_CFG" | jq \
    --arg url "$MCP_URL" \
    '.mcpServers["allye-mcp"] = {
      "type": "http",
      "url": $url
    }')

  echo "$CLAUDE_CFG" | jq '.' > "$CLAUDE_JSON"
  print_success "Allye MCP server configured (OAuth — browser login on first use)"
  AGENTS_CONFIGURED=$((AGENTS_CONFIGURED + 1))
else
  print_warning "Claude Code not found — skipping"
fi

# Cursor
if command -v cursor &>/dev/null || [ -d "$HOME/.cursor" ]; then
  print_success "Cursor detected"

  # Configure MCP server (OAuth — no PAT headers)
  CURSOR_MCP_DIR="$HOME/.cursor"
  CURSOR_MCP="$CURSOR_MCP_DIR/mcp.json"
  mkdir -p "$CURSOR_MCP_DIR"

  if [ -f "$CURSOR_MCP" ]; then
    CURSOR_CFG=$(cat "$CURSOR_MCP")
  else
    CURSOR_CFG='{}'
  fi

  CURSOR_CFG=$(echo "$CURSOR_CFG" | jq \
    --arg url "$MCP_URL" \
    '.mcpServers["allye-mcp"] = {
      "url": $url
    }')

  echo "$CURSOR_CFG" | jq '.' > "$CURSOR_MCP"
  print_success "Cursor MCP server configured (OAuth — browser login on first use)"
  AGENTS_CONFIGURED=$((AGENTS_CONFIGURED + 1))
fi

# OpenCode
if command -v opencode &>/dev/null; then
  print_success "OpenCode detected"

  # Configure MCP server in global config (OAuth — no PAT headers)
  OPENCODE_DIR="$HOME/.config/opencode"
  OPENCODE_CFG_FILE="$OPENCODE_DIR/opencode.json"
  mkdir -p "$OPENCODE_DIR"

  if [ -f "$OPENCODE_CFG_FILE" ]; then
    OC_CFG=$(cat "$OPENCODE_CFG_FILE")
  else
    OC_CFG='{"$schema": "https://opencode.ai/config.json"}'
  fi

  OC_CFG=$(echo "$OC_CFG" | jq \
    --arg url "$MCP_URL" \
    '.mcp["allye-mcp"] = {
      "type": "remote",
      "url": $url,
      "enabled": true
    }')

  # Add allye-opencode plugin to plugin array
  OC_CFG=$(echo "$OC_CFG" | jq '
    .plugin = (.plugin // []) |
    if (.plugin | index("allye-opencode")) then . else .plugin += ["allye-opencode"] end
  ')

  echo "$OC_CFG" | jq '.' > "$OPENCODE_CFG_FILE"
  print_success "OpenCode MCP server + plugin configured (OAuth — browser login on first use)"
  AGENTS_CONFIGURED=$((AGENTS_CONFIGURED + 1))
fi

# Codex
if command -v codex &>/dev/null; then
  print_success "Codex detected"

  # Configure MCP server in config.toml (OAuth — no PAT headers)
  CODEX_DIR="$HOME/.codex"
  CODEX_CFG="$CODEX_DIR/config.toml"
  mkdir -p "$CODEX_DIR"

  if [ -f "$CODEX_CFG" ] && grep -q "allye-mcp" "$CODEX_CFG" 2>/dev/null; then
    # Migrate existing entry to OAuth: strip legacy PAT headers and old endpoint
    sed -i '/http_headers.*Authorization.*Bearer/d' "$CODEX_CFG"
    sed -i '/bearer_token_env_var/d' "$CODEX_CFG"
    sed -i "s|mcp.allye.app/jsonrpc|mcp.allye.app/mcp|g" "$CODEX_CFG"
    print_success "Codex MCP server updated (migrated to OAuth)"
  else
    cat >> "$CODEX_CFG" << TOML

[mcp_servers.allye-mcp]
url = "$MCP_URL"
enabled = true
TOML
    print_success "Codex MCP server configured (OAuth — browser login on first use)"
  fi
  AGENTS_CONFIGURED=$((AGENTS_CONFIGURED + 1))
fi

# Gemini CLI
if command -v gemini &>/dev/null; then
  print_success "Gemini CLI detected"

  # Configure MCP server in global settings (OAuth — no PAT headers)
  GEMINI_DIR="$HOME/.gemini"
  GEMINI_SETTINGS="$GEMINI_DIR/settings.json"
  mkdir -p "$GEMINI_DIR"

  if [ -f "$GEMINI_SETTINGS" ]; then
    GEMINI_CFG=$(cat "$GEMINI_SETTINGS")
  else
    GEMINI_CFG='{}'
  fi

  GEMINI_CFG=$(echo "$GEMINI_CFG" | jq \
    --arg url "$MCP_URL" \
    '.mcpServers["allye-mcp"] = {
      "httpUrl": $url
    }')

  echo "$GEMINI_CFG" | jq '.' > "$GEMINI_SETTINGS"
  print_success "Gemini CLI MCP server configured (OAuth — browser login on first use)"
  AGENTS_CONFIGURED=$((AGENTS_CONFIGURED + 1))
fi

# ─── Done ──────────────────────────────────────────────────────────────────────

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
echo "  Agents configured: $AGENTS_CONFIGURED"
echo ""

if [ "$AGENTS_CONFIGURED" -gt 0 ]; then
  echo "Start a new session in your AI agent to use the Allye plugin."
  echo "On first Allye tool use, your browser will open for OAuth login."
else
  echo "No supported agents were detected."
  echo "Install Claude Code, OpenCode, Cursor, Codex, or Gemini CLI and run this again."
fi
echo ""
