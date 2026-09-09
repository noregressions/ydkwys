#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf node_modules package-lock.json npm-repo trace-output packages/trace-route-package/dist
mkdir -p npm-repo trace-output

echo "== Pack trace-route-package =="
(
  cd packages/trace-route-package
  npm pack \
    --foreground-scripts \
    --pack-destination ../../npm-repo \
    2>&1 | tee ../../trace-output/npm-pack.log
)

echo
echo "== Install application dependencies from the packed tarball =="
npm install \
  --ignore-scripts \
  --no-audit \
  --no-fund \
  2>&1 | tee trace-output/npm-install.log

echo
echo "== Installed dependency tree =="
npm ls --all
