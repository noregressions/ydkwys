#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

rm -rf "$BASE"
mkdir -p "$BASE"

echo "S05:    $S05"
echo "Output: $BASE"
echo

node --version | tee "$BASE/node-version.txt"
npm --version | tee "$BASE/npm-version.txt"
npm config get registry | tee "$BASE/npm-registry.txt"

cd "$S05"

echo
echo "== Start S05 clean =="
./scripts/clean.sh

echo
echo "== Pre-pack package source =="
find packages/trace-route-package -maxdepth 3 -type f -print | sort \
  | tee "$BASE/source-files-before-pack.txt"

cp package.json "$BASE/application-package.json"
cp packages/trace-route-package/package.json "$BASE/source-package.json"
cp packages/trace-route-package/scripts/generate-dist.js "$BASE/generate-dist.js"
cp packages/trace-route-package/build-input/route.json "$BASE/route-input.json"

echo
echo "== Build / npm pack / install =="
./scripts/build.sh 2>&1 | tee "$BASE/build.log"

cp package-lock.json "$BASE/application-package-lock.json"

echo
echo "== Installed dependency model =="
npm ls --all 2>&1 | tee "$BASE/npm-ls.txt"

TARBALL="npm-repo/trace-route-package-1.0.0.tgz"
printf '%s\n' "$S05/$TARBALL" > "$BASE/tarball-path.txt"

echo
echo "== Packed artefact =="
tar -tzf "$TARBALL" | tee "$BASE/tarball-files.txt"

rm -rf "$BASE/unpacked-package"
mkdir -p "$BASE/unpacked-package"
tar -xzf "$TARBALL" -C "$BASE/unpacked-package" --strip-components=1

find "$BASE/unpacked-package" -maxdepth 3 -type f -print | sort \
  | tee "$BASE/unpacked-package-files.txt"

echo
echo "== Installed package =="
find node_modules/trace-route-package -maxdepth 3 -type f -print | sort \
  | tee "$BASE/installed-package-files.txt"

cp node_modules/trace-route-package/package.json "$BASE/installed-package.json"
cp node_modules/trace-route-package/dist/prepack-evidence.json \
  "$BASE/installed-prepack-evidence.json"

echo
echo "== Lifecycle evidence retained by S05 =="
grep -E 'prepack|generate-dist|npm-prepack-generated|hidden/prepack-info' \
  "$BASE/build.log" \
  "$BASE/source-package.json" \
  "$BASE/generate-dist.js" \
  "$BASE/installed-prepack-evidence.json" \
  || true

echo
echo "T07 / S05 baseline captured."
