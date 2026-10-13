#!/bin/bash
# Shared helpers for install/docs-gate/NN-*.sh. Sourced by each check (never run by the
# runner: its glob matches only NN-*.sh), so every check stays runnable alone.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAME="$(basename "${BASH_SOURCE[1]:-docs-gate}" .sh)"
errors=0

fail() { echo "$NAME: $*" >&2; errors=$((errors + 1)); }

# has_line <file> <exact line>: the file contains the line exactly (full-line equality).
has_line() { grep -Fxq -- "$2" "$ROOT/$1" || fail "$1: missing exact line: $2"; }

# count_line <file> <exact line> <n>: the exact line appears exactly n times.
count_line() {
  local n
  n=$(grep -Fxc -- "$2" "$ROOT/$1" || true)
  [ "$n" -eq "$3" ] || fail "$1: expected $3 occurrence(s) of: $2 (found $n)"
}

# section_body <file> <heading>: the non-empty lines after the exact heading line, up to
# the next heading or code fence.
section_body() {
  awk -v h="$2" '$0 == h {on=1; next} on && (/^#/ || /^```/) {exit} on && NF' "$ROOT/$1"
}

# deny <file> <extended regex>: no line of the file matches (case-insensitive).
deny() {
  local hit
  hit=$(grep -Ein -- "$2" "$ROOT/$1" || true)
  [ -z "$hit" ] || fail "$1: forbidden text /$2/: $hit"
}

finish() {
  if [ "$errors" -ne 0 ]; then
    echo "$NAME: $errors failure(s)" >&2
    exit 1
  fi
  echo "$NAME: ok"
  exit 0
}
