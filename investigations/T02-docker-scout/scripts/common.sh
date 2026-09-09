#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "$1 is required" >&2
    exit 1
  }
}

resolve_s01() {
  if [[ -n "${S01_DIR:-}" ]]; then
    (cd "$S01_DIR" 2>/dev/null && pwd) || return 1
    return
  fi

  local candidates=(
    "$ROOT/../../scenarios/S01-spring-node"
    "$ROOT/../S01-spring-node"
    "$ROOT/../../S01-spring-node"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate/Dockerfile" && -f "$candidate/scripts/image-trace.sh" ]]; then
      (cd "$candidate" && pwd)
      return
    fi
  done

  return 1
}

resolve_s02() {
  if [[ -n "${S02_DIR:-}" ]]; then
    (cd "$S02_DIR" 2>/dev/null && pwd) || return 1
    return
  fi

  local candidates=(
    "$ROOT/../../scenarios/S02-payara-mvnpm"
    "$ROOT/../S02-payara-mvnpm"
    "$ROOT/../../S02-payara-mvnpm"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate/Dockerfile" && -f "$candidate/scripts/image-trace.sh" ]]; then
      (cd "$candidate" && pwd)
      return
    fi
  done

  return 1
}

capture() {
  local outfile="$1"
  shift
  set +e
  "$@" 2>&1 | tee "$outfile"
  local rc=${PIPESTATUS[0]}
  set -e
  printf '%s\n' "$rc" >"${outfile}.exit"
  return 0
}
