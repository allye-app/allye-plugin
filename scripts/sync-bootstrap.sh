#!/bin/bash
# Copies the shared bootstrap (bootstrap/allye.md) to every harness file that
# must ship it as a standalone copy. Run after editing bootstrap/allye.md;
# test/test-bootstrap.sh fails while a copy is stale.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cp "$ROOT/bootstrap/allye.md" "$ROOT/manifests/codex/AGENTS.md"
echo "synced manifests/codex/AGENTS.md"
