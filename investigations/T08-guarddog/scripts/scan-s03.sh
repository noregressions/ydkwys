#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

SDIST="$S03/python-repo/tracehook_demo-1.0.0.tar.gz"
OUT="$RESULTS/s03"
mkdir -p "$OUT"

if [[ ! -f "$SDIST" ]]; then
  echo "S03 sdist not found: $SDIST" >&2
  echo "Build it first: (cd $S03 && ./scripts/build.sh)" >&2
  exit 1
fi

echo "Scanning the S03 source distribution (which DOES carry its build backend):"
echo "  $SDIST"
echo

tar -tzf "$SDIST" | tee "$OUT/sdist-files.txt"
echo

guarddog pypi scan "$SDIST" $NO_SANDBOX | tee "$OUT/scan.txt"
guarddog pypi scan "$SDIST" $NO_SANDBOX --output-format=json > "$OUT/scan.json"
