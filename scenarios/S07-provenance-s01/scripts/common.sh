#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DEFAULT="$(cd "$ROOT/../.." 2>/dev/null && pwd || true)"
S01="${S01:-${REPO_DEFAULT}/scenarios/S01-spring-node}"

WORK="$ROOT/work"          # a throwaway copy of S01 we are allowed to modify
SRC="$WORK/s01"
RESULTS="$ROOT/results"
IMG="localhost:5000/checkout-service"
REG="${REG:-localhost:5000}"

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Required command not found: $1" >&2; exit 1; }
}

ensure_registry() {
  # A local registry gives cosign somewhere to store signatures/attestations,
  # and gives the image a real content digest to key everything on.
  if ! curl -sf "http://$REG/v2/" >/dev/null 2>&1; then
    echo "Starting a throwaway local registry at $REG ..."
    docker rm -f s07-registry >/dev/null 2>&1 || true
    docker run -d -p 5000:5000 --name s07-registry registry:2 >/dev/null
    sleep 3
  fi
}

copy_s01() {
  [[ -d "$S01" ]] || { echo "S01 not found: $S01" >&2; exit 1; }
  rm -rf "$WORK"; mkdir -p "$WORK"
  # copy source only; skip build output and any existing git
  ( cd "$S01" && tar --exclude=node_modules --exclude=target --exclude=dist \
      --exclude=.git --exclude=trace-output --exclude='.DS_Store' -cf - . ) \
    | ( mkdir -p "$SRC" && cd "$SRC" && tar -xf - )
}

for c in docker mvn java; do need "$c"; done
mkdir -p "$RESULTS"
