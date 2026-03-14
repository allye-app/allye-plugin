#!/bin/bash
set -e

# Fenix Agent Plugin — Installer
# 1. Prompts for Fenix PAT
# 2. Validates PAT against Fenix API
# 3. Seeds skills into Fenix DB
# 4. Detects installed AI agents and configures manifests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEED_FILE="$SCRIPT_DIR/seed/seed-skills.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║     Fenix Agent Plugin Installer     ║${NC}"
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

# ─── Step 1: Get Fenix API URL and PAT ────────────────────────────────────────

print_header

echo "This installer will:"
echo "  1. Connect to your Fenix instance"
echo "  2. Seed workflow skills into your team's database"
echo "  3. Configure your AI coding agents to use the plugin"
echo ""

# API URL
if [ -n "$FENIX_API_URL" ]; then
  print_step "Using FENIX_API_URL from environment: $FENIX_API_URL"
  API_URL="$FENIX_API_URL"
else
  read -rp "Fenix API URL (e.g., https://api.fenix.dev): " API_URL
  # Remove trailing slash
  API_URL="${API_URL%/}"
fi

if [ -z "$API_URL" ]; then
  print_error "API URL is required."
  exit 1
fi

# PAT
if [ -n "$FENIX_PAT" ]; then
  print_step "Using FENIX_PAT from environment"
  PAT="$FENIX_PAT"
else
  echo ""
  echo "Generate a Personal Access Token (PAT) in Fenix:"
  echo "  Settings → API → Generate Token"
  echo ""
  read -rsp "Fenix PAT: " PAT
  echo ""
fi

if [ -z "$PAT" ]; then
  print_error "PAT is required."
  exit 1
fi

# ─── Step 2: Validate PAT ─────────────────────────────────────────────────────

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

# ─── Step 3: Seed Skills ──────────────────────────────────────────────────────

echo ""
print_step "Seeding skills into Fenix..."

if [ ! -f "$SEED_FILE" ]; then
  print_error "Seed file not found: $SEED_FILE"
  exit 1
fi

SKILL_COUNT=$(jq '.skills | length' "$SEED_FILE")
SEEDED=0
UPDATED=0
FAILED=0

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

# ─── Step 4: Detect and Configure Agents ──────────────────────────────────────

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
    --arg api_url "$API_URL" \
    --arg pat "$PAT" \
    '.hooks.SessionStart = [
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
    ] | .env = (.env // {}) | .env.FENIX_API_URL = $api_url | .env.FENIX_PAT = $pat')

  echo "$SETTINGS" | jq '.' > "$CLAUDE_SETTINGS"
  print_success "Claude Code configured (SessionStart hook + env vars)"
  AGENTS_CONFIGURED=$((AGENTS_CONFIGURED + 1))
else
  print_warning "Claude Code not found — skipping"
fi

# Cursor
if command -v cursor &>/dev/null || [ -d "$HOME/.cursor" ]; then
  print_success "Cursor detected"

  # Copy .cursorrules if manifest exists
  CURSOR_RULES="$SCRIPT_DIR/manifests/cursor/.cursorrules"
  if [ -f "$CURSOR_RULES" ]; then
    print_step "Cursor manifest available but not yet implemented (Fase 3)"
  else
    print_warning "Cursor manifest not yet created — run install again after Fase 3"
  fi
fi

# OpenCode
if command -v opencode &>/dev/null; then
  print_success "OpenCode detected"
  OPENCODE_CONFIG="$SCRIPT_DIR/manifests/opencode/opencode.json"
  if [ -f "$OPENCODE_CONFIG" ]; then
    print_step "OpenCode manifest available but not yet implemented (Fase 3)"
  else
    print_warning "OpenCode manifest not yet created — run install again after Fase 3"
  fi
fi

# Codex
if command -v codex &>/dev/null; then
  print_success "Codex detected"
  print_warning "Codex manifest not yet created — run install again after Fase 3"
fi

# Gemini CLI
if command -v gemini &>/dev/null; then
  print_success "Gemini CLI detected"
  print_warning "Gemini manifest not yet created — run install again after Fase 3"
fi

# ─── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       Installation complete!         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo "  Skills seeded: $((SEEDED + UPDATED))/$SKILL_COUNT"
echo "  Agents configured: $AGENTS_CONFIGURED"
echo ""

if [ "$AGENTS_CONFIGURED" -gt 0 ]; then
  echo "Start a new session in your AI agent to use the Fenix plugin."
else
  echo "No supported agents were detected."
  echo "Install Claude Code, OpenCode, Cursor, Codex, or Gemini CLI and run this again."
fi
echo ""
