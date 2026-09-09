#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

WAR="target/payara-mvnpm-trace-lab-1.0.0.war"

if [[ ! -f "$WAR" ]]; then
  echo "WAR not found. Run ./scripts/build.sh first." >&2
  exit 1
fi

echo "=== Ordinary project dependency: commons-lang3 ==="
mvn dependency:tree -Dincludes=org.apache.commons:commons-lang3

echo
echo "=== mvnpm package in ordinary project dependency tree (expected: absent) ==="
mvn dependency:tree -Dincludes=org.mvnpm:lodash-es

echo
echo "=== mvnpm package in actual plugin execution realm ==="
mvn -X generate-resources 2>&1 | grep 'org.mvnpm:lodash-es' || true

echo
echo "=== Generated browser assets ==="
find target/generated-web -maxdepth 2 -type f -print

echo
echo "=== lodash sources represented in the source map ==="
jq -r '.sources[]' target/generated-web/assets/app.js.map | grep 'lodash' || true

echo
echo "=== Relevant WAR entries ==="
unzip -l "$WAR" | grep -E 'WEB-INF/lib/commons-lang3|assets/app\.js' || true
