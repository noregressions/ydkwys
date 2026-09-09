#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

VAR="$S05/malicious-variant"
OUT="$RESULTS/malicious"
mkdir -p "$OUT"

if [[ ! -d "$VAR" ]]; then
  echo "S05 malicious variant not found: $VAR" >&2
  exit 1
fi

echo "Building the malicious variants (pack only — never installed):"
( cd "$VAR" && ./scripts/build-variants.sh >/dev/null )
A="$VAR/out/CASE-A-generator-payload.tgz"
B="$VAR/out/CASE-B-generated-payload.tgz"

echo
echo "== Case A — published tarball (payload was in the un-shipped generator) =="
guarddog npm scan "$A" $NO_SANDBOX | tee "$OUT/A-tarball.txt"

echo
echo "== Case A — SOURCE (the generator is present here) =="
guarddog npm scan "$VAR/case-a-generator-payload" $NO_SANDBOX | tee "$OUT/A-source.txt"

echo
echo "== Case B — published tarball (payload rode into the shipped dist) =="
guarddog npm scan "$B" $NO_SANDBOX | tee "$OUT/B-tarball.txt"
