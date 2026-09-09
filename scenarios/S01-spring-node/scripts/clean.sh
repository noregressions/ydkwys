#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

printf '\n==> Removing Maven build output\n'
rm -rf normalizer/target service/target
rm -f normalizer/dependency-reduced-pom.xml

printf '\n==> Removing frontend build output\n'
rm -rf frontend/node_modules frontend/dist

printf '\n==> Removing trace output\n'
rm -rf trace-output

printf '\nCleaned:\n'
printf '  normalizer/target/\n'
printf '  normalizer/dependency-reduced-pom.xml\n'
printf '  service/target/\n'
printf '  frontend/node_modules/\n'
printf '  frontend/dist/\n'
printf '  trace-output/\n'
printf '\nPreserved:\n'
printf '  frontend/package-lock.json (if present)\n'
