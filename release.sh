#!/bin/bash
set -e

# Allye Plugin — Release Script
# Usage: ./release.sh [major|minor|patch]
# Default: patch

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_JSON="$SCRIPT_DIR/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$SCRIPT_DIR/.claude-plugin/marketplace.json"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get current version
CURRENT=$(jq -r '.version' "$PLUGIN_JSON")
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

# Determine bump type
BUMP="${1:-patch}"
case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  *) echo "Usage: ./release.sh [major|minor|patch]"; exit 1 ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

echo -e "${BLUE}→${NC} Bumping version: $CURRENT → $NEW_VERSION ($BUMP)"

# Update plugin.json
jq --arg v "$NEW_VERSION" '.version = $v' "$PLUGIN_JSON" > /tmp/plugin.json.tmp
mv /tmp/plugin.json.tmp "$PLUGIN_JSON"

# Update marketplace.json (both metadata and plugin entry)
jq --arg v "$NEW_VERSION" '
  .metadata.version = $v |
  .plugins[0].version = $v
' "$MARKETPLACE_JSON" > /tmp/marketplace.json.tmp
mv /tmp/marketplace.json.tmp "$MARKETPLACE_JSON"

# Sync SKILL.md files (using-allye is the source of truth)
if [ -f "$SCRIPT_DIR/skills/using-allye/SKILL.md" ]; then
  cp "$SCRIPT_DIR/skills/using-allye/SKILL.md" "$SCRIPT_DIR/skills/bootstrap/using-allye.md"
fi

# Commit and tag
git add -A
git commit -m "Release v$NEW_VERSION

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"

git tag "v$NEW_VERSION"
git push && git push --tags

echo ""
echo -e "${GREEN}✓${NC} Released v$NEW_VERSION"
echo ""
echo "Users can update with: /plugin update allye"
