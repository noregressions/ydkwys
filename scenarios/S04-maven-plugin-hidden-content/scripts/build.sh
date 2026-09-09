#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

LOCAL_REPO="$PWD/.maven-repo"
mkdir -p "$LOCAL_REPO" trace-output

echo "== Build the Maven plugin and its transitive payload =="
mvn \
  -Dmaven.repo.local="$LOCAL_REPO" \
  -f tooling/pom.xml \
  install

echo
echo "== Build the application =="
mvn \
  -Dmaven.repo.local="$LOCAL_REPO" \
  clean package
