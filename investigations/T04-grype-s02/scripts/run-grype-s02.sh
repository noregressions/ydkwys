#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in grype jq sort diff; do
  require_command "$cmd"
done

BASE="$ROOT/results/s02/baseline"
OUT="$ROOT/results/s02/grype"
mkdir -p "$OUT"

[[ -f "$BASE/image-name.txt" ]] || {
  echo "Run ./scripts/baseline-s02.sh first." >&2
  exit 1
}

IMAGE="$(cat "$BASE/image-name.txt")"

echo "Image: $IMAGE"

grype version | tee "$OUT/grype-version.txt"

echo
echo "== Grype database status =="
capture "$OUT/grype-db-status.txt" grype db status

scan_json() {
  local label="$1"
  local target="$2"

  echo
  echo "== $label =="

  set +e
  grype "$target" -o json >"$OUT/$label.json" 2>"$OUT/$label.log"
  local rc=$?
  set -e
  printf '%s\n' "$rc" >"$OUT/$label.exit"

  cat "$OUT/$label.log"

  if [[ -s "$OUT/$label.json" ]]; then
    jq -r '
      .matches[]?
      | [
          (.artifact.name // ""),
          (.artifact.version // ""),
          (.vulnerability.id // ""),
          (.vulnerability.severity // ""),
          ((.vulnerability.fix.versions // []) | join(",")),
          (.vulnerability.fix.state // "")
        ]
      | @tsv
    ' "$OUT/$label.json" \
      | sort -u \
      | tee "$OUT/$label.matches.tsv"

    jq -r '
      .matches[]?
      | select(
          (.artifact.name // "" | test("commons-lang3|lodash-es|payara|jakarta"; "i"))
          or (.artifact.purl // "" | test("commons-lang3|lodash-es|payara|jakarta"; "i"))
        )
      | [
          (.artifact.name // ""),
          (.artifact.version // ""),
          (.artifact.purl // ""),
          (.vulnerability.id // ""),
          (.vulnerability.severity // ""),
          ((.vulnerability.fix.versions // []) | join(","))
        ]
      | @tsv
    ' "$OUT/$label.json" \
      | sort -u \
      | tee "$OUT/$label.tracer-matches.tsv"
  fi
}

scan_table() {
  local label="$1"
  local target="$2"

  echo
  echo "== $label table / catalog summary =="
  capture "$OUT/$label.table.txt" grype "$target"
}

DIRECT="docker:$IMAGE"
SYFT_SBOM="sbom:$BASE/image.syft.json"
CDX_SBOM="sbom:$BASE/image.cdx.json"

scan_table "direct-image" "$DIRECT"
scan_json  "direct-image" "$DIRECT"

scan_table "syft-json" "$SYFT_SBOM"
scan_json  "syft-json" "$SYFT_SBOM"

scan_table "cyclonedx" "$CDX_SBOM"
scan_json  "cyclonedx" "$CDX_SBOM"

echo
echo "== PURL controls =="

COMMONS_PURL='pkg:maven/org.apache.commons/commons-lang3@3.18.0'
LODASH_PURL='pkg:maven/org.mvnpm/lodash-es@4.17.21'

scan_json "purl-commons-lang3" "$COMMONS_PURL"
scan_json "purl-lodash-es" "$LODASH_PURL"

echo
echo "== Exact match-set diffs =="

set +e
diff -u "$OUT/direct-image.matches.tsv" "$OUT/syft-json.matches.tsv" \
  | tee "$OUT/diff-direct-vs-syft-json.txt"
printf '%s\n' "${PIPESTATUS[0]}" >"$OUT/diff-direct-vs-syft-json.exit"

diff -u "$OUT/direct-image.matches.tsv" "$OUT/cyclonedx.matches.tsv" \
  | tee "$OUT/diff-direct-vs-cyclonedx.txt"
printf '%s\n' "${PIPESTATUS[0]}" >"$OUT/diff-direct-vs-cyclonedx.exit"

diff -u "$OUT/syft-json.matches.tsv" "$OUT/cyclonedx.matches.tsv" \
  | tee "$OUT/diff-syft-json-vs-cyclonedx.txt"
printf '%s\n' "${PIPESTATUS[0]}" >"$OUT/diff-syft-json-vs-cyclonedx.exit"
set -e

echo
echo "T04 Grype probes captured."
echo "Run:"
echo "  ./scripts/compare-s02.sh"
