#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DEFAULT="$(cd "$ROOT/../.." 2>/dev/null && pwd || true)"
S05="${S05:-${REPO_DEFAULT}/scenarios/S05-node-prepack}"

if [[ ! -d "$S05" ]]; then
  echo "Unable to find S05." >&2
  echo "Expected: $S05" >&2
  echo "Set S05=/path/to/scenarios/S05-node-prepack and retry." >&2
  exit 1
fi

BASE="$ROOT/results/s05/baseline"
AUDIT="$ROOT/results/s05/npm-audit"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

for cmd in node npm tar grep find; do
  need "$cmd"
done

mkdir -p "$BASE" "$AUDIT"
