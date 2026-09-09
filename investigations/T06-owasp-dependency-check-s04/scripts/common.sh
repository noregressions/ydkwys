#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Dependency-Check 13.0.0 has a known regression when no NVD API key is
# supplied: the empty configured key is passed to the NVD client and rejected.
# Use 12.2.2 by default for keyless workshop runs. If the caller explicitly
# sets DC_VERSION, respect it.
if [[ -n "${DC_VERSION:-}" ]]; then
  DC_VERSION="$DC_VERSION"
elif [[ -n "${NVD_API_KEY:-}" ]]; then
  DC_VERSION="13.0.0"
else
  DC_VERSION="12.2.2"
fi

DC_DATA_DIR="${DC_DATA_DIR:-$HOME/.cache/kcdc-dependency-check/$DC_VERSION}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "$1 is required" >&2
    exit 1
  }
}

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
    if [[ -f "$candidate/pom.xml" && -f "$candidate/scripts/build.sh" ]]; then
      (cd "$candidate" && pwd)
      return
    fi
  done

  return 1
}

nvd_args() {
  if [[ -n "${NVD_API_KEY:-}" ]]; then
    printf '%s\n' "-DnvdApiKeyEnvironmentVariable=NVD_API_KEY"
  fi
}

report_path() {
  local dir="$1"
  printf '%s/dependency-check-report.json\n' "$dir"
}

normalise_report() {
  local report="$1"
  local prefix="$2"

  if [[ ! -f "$report" ]]; then
    echo "Report not found: $report" >&2
    return 1
  fi

  jq -r '
    .dependencies[]?
    | [
        (.fileName // ""),
        (.filePath // ""),
        ((.packages // []) | map(.id) | join(",")),
        ((.vulnerabilities // []) | length | tostring)
      ]
    | @tsv
  ' "$report" | sort -u >"${prefix}.dependencies.tsv"

  jq -r '
    .dependencies[]?
    | . as $dep
    | (.vulnerabilities // [])[]
    | [
        ($dep.fileName // ""),
        (.name // ""),
        (.severity // ""),
        ((.cvssv3.baseScore // .cvssv2.score // "") | tostring)
      ]
    | @tsv
  ' "$report" | sort -u >"${prefix}.vulnerabilities.tsv"

  jq -r '
    .dependencies[]?
    | select(
        ((.fileName // "") | test("trace-injector|trace-route-payload|maven-plugin-hidden-content"; "i"))
        or (((.packages // []) | map(.id) | join(" ")) | test("trace-injector|trace-route-payload|maven-plugin-hidden-content"; "i"))
      )
    | [
        (.fileName // ""),
        ((.packages // []) | map(.id) | join(",")),
        ((.vulnerabilities // []) | length | tostring)
      ]
    | @tsv
  ' "$report" | sort -u >"${prefix}.tracers.tsv"

  jq -r '.dependencies | length' "$report" >"${prefix}.dependency-count.txt"

  jq -r '
    [.dependencies[]? | (.vulnerabilities // []) | length]
    | add // 0
  ' "$report" >"${prefix}.vulnerability-count.txt"
}
