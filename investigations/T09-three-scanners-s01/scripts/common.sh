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
    if [[ -f "$candidate/pom.xml" && -f "$candidate/scripts/build.sh" ]]; then
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

# --- T09 additions -----------------------------------------------------------

# The tracked components this investigation follows through S01.
TRACER_RE='jackson-databind|commons-codec|normalizer|lodash'

# OSV-Scanner changed its CLI between v1 (flags) and v2 (subcommands). Probe
# once and record which form this machine has, so the captured results say
# what was actually run.
# NB: --help exits non-zero on some v2 builds, so probe the version string,
# not the subcommand.
osv_mode() {
  local major
  major=$(osv-scanner --version 2>/dev/null | head -1 \
            | sed -nE 's/.*version:[[:space:]]*([0-9]+).*/\1/p')
  if [[ "${major:-0}" -ge 2 ]]; then echo "v2"; else echo "v1"; fi
}

# Scan a directory or a single manifest with whichever OSV-Scanner syntax is
# present. A single file has to go through --lockfile; a directory is a
# positional argument. v2 renamed --output to --output-file.
osv_scan_source() {
  local target="$1" outfile="$2"
  set +e
  if [[ "$(osv_mode)" == "v2" ]]; then
    # --all-packages matters: without it osv-scanner reports only packages
    # that HAVE findings, which would make the identity half of the matrix
    # read as a capability gap when it is nothing of the kind.
    if [[ -f "$target" ]]; then
      osv-scanner scan source --lockfile "$target" --all-packages \
        --format json --output-file "$outfile"
    else
      osv-scanner scan source --recursive --all-packages \
        --format json --output-file "$outfile" "$target"
    fi
  else
    if [[ -f "$target" ]]; then
      osv-scanner --lockfile "$target" --format json --output "$outfile"
    else
      osv-scanner --recursive --format json --output "$outfile" "$target"
    fi
  fi
  local rc=$?
  set -e
  printf '%s\n' "$rc" >"${outfile}.exit"
  # osv-scanner exits non-zero when it FINDS vulnerabilities. That is a
  # result, not an error; the caller reads the JSON either way.
  return 0
}

osv_scan_image() {
  local image="$1" outfile="$2"
  set +e
  if [[ "$(osv_mode)" == "v2" ]]; then
    osv-scanner scan image --all-packages \
      --format json --output-file "$outfile" "$image"
  else
    echo "osv-scanner v1 on this machine has no image scanner" >"$outfile"
    false
  fi
  local rc=$?
  set -e
  printf '%s\n' "$rc" >"${outfile}.exit"
  return 0
}
