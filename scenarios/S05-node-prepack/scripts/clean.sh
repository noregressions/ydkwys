#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/stop.sh >/dev/null 2>&1 || true
rm -rf \
  node_modules \
  package-lock.json \
  npm-repo \
  trace-output \
  packages/trace-route-package/dist
rm -f .runtime.pid .runtime.log
echo "S05 clean."
echo
echo "Removed generated/installed state; kept application and package source."
