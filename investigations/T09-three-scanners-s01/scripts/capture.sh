#!/usr/bin/env bash
#
# T09 one-shot capture: baseline, all three scanners, then the comparison.
# Stops at the first stage that fails, so a partial tree is never mistaken
# for a finished one.
set -euo pipefail

source "$(dirname "$0")/common.sh"

echo "=============================================================="
echo " T09 capture — checking instruments before doing any work"
echo "=============================================================="
missing=0
for t in mvn npm jar docker jq; do
  if command -v "$t" >/dev/null 2>&1; then
    printf '  required  %-14s ok\n' "$t"
  else
    printf '  required  %-14s MISSING\n' "$t"; missing=1
  fi
done
for t in grype trivy osv-scanner; do
  if command -v "$t" >/dev/null 2>&1; then
    printf '  scanner   %-14s ok\n' "$t"
  else
    printf '  scanner   %-14s missing (will be skipped)\n' "$t"
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo
  echo "ERROR: Docker is not running. The container-image boundary needs it." >&2
  missing=1
fi

present=0
for t in grype trivy osv-scanner; do command -v "$t" >/dev/null 2>&1 && present=$((present+1)); done
if [[ $present -lt 2 ]]; then
  echo
  echo "ERROR: $present of 3 scanners present. T09 needs at least two to compare." >&2
  echo "  brew install grype trivy osv-scanner" >&2
  missing=1
fi

[[ $missing -eq 0 ]] || exit 1

echo
echo "=============================================================="
echo " 1/3  baseline"
echo "=============================================================="
"$ROOT/scripts/baseline-s01.sh"

echo
echo "=============================================================="
echo " 2/3  scanners"
echo "=============================================================="
"$ROOT/scripts/run-scanners-s01.sh"

echo
echo "=============================================================="
echo " 3/3  comparison"
echo "=============================================================="
"$ROOT/scripts/compare-s01.sh"

echo
echo "Done. Paste into LESSON.md from:"
echo "  $ROOT/results/s01/compare/matrix.txt        the four sections"
echo "  $ROOT/results/s01/baseline/instruments.txt  the versions block"
echo
echo "Then: ./scripts/proof-check.sh"
