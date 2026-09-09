#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

TGZ="$S05/npm-repo/trace-route-package-1.0.0.tgz"
OUT="$RESULTS/s05"
mkdir -p "$OUT"

if [[ ! -f "$TGZ" ]]; then
  echo "S05 tarball not found: $TGZ" >&2
  echo "Build it first: (cd $S05 && ./scripts/build.sh)" >&2
  exit 1
fi

echo "Scanning the PUBLISHED S05 tarball (the bytes a consumer receives):"
echo "  $TGZ"
echo

# What GuardDog is actually allowed to read: list the tarball contents first.
tar -tzf "$TGZ" | tee "$OUT/tarball-files.txt"
echo

guarddog npm scan "$TGZ" $NO_SANDBOX | tee "$OUT/scan.txt"
