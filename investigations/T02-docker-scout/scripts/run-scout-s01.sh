#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in docker grep tee; do
  require_command "$cmd"
done

BASE="$ROOT/results/s01/baseline"
OUT="$ROOT/results/s01/scout"
mkdir -p "$OUT"

[[ -f "$BASE/image-name.txt" ]] || {
  echo "Run ./scripts/baseline-s01.sh first." >&2
  exit 1
}

IMAGE="$(cat "$BASE/image-name.txt")"
TARGET="local://$IMAGE"

echo "Target: $TARGET"

capture "$OUT/quickview.txt" \
  docker scout quickview "$TARGET"

capture "$OUT/sbom-list.txt" \
  docker scout sbom --format list "$TARGET"

grep -Ei \
  'jackson-databind|commons-codec|normalizer|lodash' \
  "$OUT/sbom-list.txt" \
  | tee "$OUT/tracer-packages.txt" || true

capture "$OUT/tracer-cves.txt" \
  docker scout cves \
    --only-package 'jackson-databind,commons-codec,normalizer,lodash' \
    "$TARGET"

capture "$OUT/recommendations.txt" \
  docker scout recommendations "$TARGET"

echo
echo "S01 Docker Scout probes captured."
echo "Run:"
echo "  ./scripts/compare-s01.sh"
