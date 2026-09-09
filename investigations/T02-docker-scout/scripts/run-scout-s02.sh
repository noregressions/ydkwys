#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in docker grep tee; do
  require_command "$cmd"
done

BASE="$ROOT/results/s02/baseline"
OUT="$ROOT/results/s02/scout"
mkdir -p "$OUT"

[[ -f "$BASE/image-name.txt" ]] || {
  echo "Run ./scripts/baseline-s02.sh first." >&2
  exit 1
}

IMAGE="$(cat "$BASE/image-name.txt")"
TARGET="local://$IMAGE"

echo "Target: $TARGET"

capture "$OUT/quickview.txt" \
  docker scout quickview "$TARGET"

capture "$OUT/sbom-list.txt" \
  docker scout sbom --format list "$TARGET"

{
  grep -E '^[[:space:]]*commons-lang3[[:space:]]+\|' "$OUT/sbom-list.txt" || true
  grep -E '^[[:space:]]*lodash-es[[:space:]]+\|' "$OUT/sbom-list.txt" || true
  grep -E '^[[:space:]]*jakarta\.(servlet-api|ws\.rs-api|enterprise\.cdi-api|persistence-api|transaction-api)[[:space:]]+\|' "$OUT/sbom-list.txt" || true
  grep -E '^[[:space:]]*(payara-api|glassfish|appserver-domain-web|payara-micro-service)[[:space:]]+\|' "$OUT/sbom-list.txt" || true
} | tee "$OUT/tracer-packages.txt" 

capture "$OUT/tracer-cves.txt" \
  docker scout cves \
    --only-package 'commons-lang3,lodash-es,payara,jakarta' \
    "$TARGET"

capture "$OUT/recommendations.txt" \
  docker scout recommendations "$TARGET"

echo
echo "S02 Docker Scout probes captured."
echo "Run:"
echo "  ./scripts/compare-s02.sh"
