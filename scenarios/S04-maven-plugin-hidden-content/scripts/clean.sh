#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/stop.sh >/dev/null 2>&1 || true

rm -rf \
  target \
  trace-output \
  tooling/payload/target \
  tooling/plugin/target

rm -f .runtime.pid .runtime.log

echo "S04 clean."
echo
echo "Kept the scenario-local Maven repository:"
echo "  .maven-repo/"
echo
echo "Remove it too if you want a cold Maven dependency-resolution run:"
echo "  rm -rf .maven-repo"
