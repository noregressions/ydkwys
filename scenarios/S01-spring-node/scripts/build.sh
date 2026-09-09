#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

printf '\n==> Frontend dependencies\n'
cd frontend
if [[ -f package-lock.json ]]; then
  npm ci
else
  echo "No package-lock.json yet: running npm install once to create it."
  npm install
fi

printf '\n==> Frontend bundle\n'
npm run build

printf '\n==> Maven build\n'
cd "$ROOT"
mvn clean package

printf '\nBuilt:\n'
printf '  frontend/dist/\n'
printf '  normalizer/target/normalizer-1.0.0.jar\n'
printf '  service/target/service-1.0.0.jar\n'
