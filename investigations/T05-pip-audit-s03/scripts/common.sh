#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "$1 is required" >&2
    exit 1
  }
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

capture_allow_fail() {
  local outfile="$1"
  shift
  set +e
  "$@" >"$outfile" 2>&1
  local rc=$?
  set -e
  printf '%s\n' "$rc" >"${outfile}.exit"
  cat "$outfile"
}
