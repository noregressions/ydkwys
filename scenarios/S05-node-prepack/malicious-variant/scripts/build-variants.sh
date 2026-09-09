#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Packs both malicious cases into out/ under distinct names. Nothing is
# installed and nothing is published. The payload is a harmless stand-in: an
# async, fire-and-forget curl to a reserved *.invalid host that can never
# resolve, so even the prepack execution in case A reaches nothing.

OUT="out"
rm -rf "$OUT"
mkdir -p "$OUT"

pack() {
  local dir="$1" name="$2"
  echo "== pack $dir =="
  ( cd "$dir" && npm pack --pack-destination "$OLDPWD/$OUT" >/dev/null )
  mv "$OUT/trace-route-package-1.0.0.tgz" "$OUT/$name"
  echo "   -> $OUT/$name"
}

pack case-a-generator-payload CASE-A-generator-payload.tgz
pack case-b-generated-payload CASE-B-generated-payload.tgz

echo
echo "Case A shipped dist (benign — payload was in the un-shipped generator):"
tar -xzf "$OUT/CASE-A-generator-payload.tgz" -O package/dist/index.js
echo
echo "Case B shipped dist (carries the payload):"
tar -xzf "$OUT/CASE-B-generated-payload.tgz" -O package/dist/index.js
