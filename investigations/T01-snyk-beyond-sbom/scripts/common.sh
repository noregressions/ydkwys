#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

resolve_s04() {
  if [[ -n "${S04_DIR:-}" ]]; then
    (cd "$S04_DIR" 2>/dev/null && pwd) || return 1
    return
  fi

  local candidates=(
    "$ROOT/../../scenarios/S04-maven-plugin-hidden-content"
    "$ROOT/../S04-maven-plugin-hidden-content"
    "$ROOT/../../S04-maven-plugin-hidden-content"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate/pom.xml" ]]; then
      (cd "$candidate" && pwd)
      return
    fi
  done

  return 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    return 1
  fi
}

capture_command() {
  local label="$1"
  local outfile="$2"
  shift 2

  echo
  echo "== $label =="
  printf 'Command:'
  printf ' %q' "$@"
  printf '\n'

  set +e
  "$@" >"$outfile" 2>&1
  local rc=$?
  set -e

  printf '%s\n' "$rc" >"${outfile}.exit"
  cat "$outfile"
  echo
  echo "Exit code: $rc"

  return 0
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
    if [[ -f "$candidate/pom.xml" ]]; then
      (cd "$candidate" && pwd)
      return
    fi
  done

  return 1
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
    if [[ -f "$candidate/pom.xml" && -f "$candidate/frontend/package.json" ]]; then
      (cd "$candidate" && pwd)
      return
    fi
  done

  return 1
}


resolve_s03() {
  if [[ -n "${S03_DIR:-}" ]]; then
    (cd "$S03_DIR" 2>/dev/null && pwd) || return 1
    return
  fi

  local candidates=(
    "$ROOT/../../scenarios/S03-python-pep517"
    "$ROOT/../S03-python-pep517"
    "$ROOT/../../S03-python-pep517"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate/requirements.txt" && -f "$candidate/scripts/build.sh" ]]; then
      (cd "$candidate" && pwd)
      return
    fi
  done

  return 1
}


resolve_s05() {
  if [[ -n "${S05_DIR:-}" ]]; then
    (cd "$S05_DIR" 2>/dev/null && pwd) || return 1
    return
  fi
  local candidates=(
    "$ROOT/../../scenarios/S05-node-prepack"
    "$ROOT/../S05-node-prepack"
    "$ROOT/../../S05-node-prepack"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate/package.json" && -f "$candidate/packages/trace-route-package/package.json" ]]; then
      (cd "$candidate" && pwd)
      return
    fi
  done
  return 1
}
