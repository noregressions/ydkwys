#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

LOCAL_REPO="$PWD/.maven-repo"
JAR="target/maven-plugin-hidden-content-1.0.0.jar"

echo "== Application dependency tree =="
mvn -Dmaven.repo.local="$LOCAL_REPO" dependency:tree
echo

echo "== Application plugin declaration =="
grep -n -A16 -B3 'trace-injector-maven-plugin' pom.xml
echo

echo "== Plugin's transitive payload declaration =="
grep -n -A8 -B3 'trace-route-payload' tooling/plugin/pom.xml
echo

echo "== Payload route definition =="
cat tooling/payload/src/main/resources/trace-route.properties
echo

echo "== Generated application source =="
find target/generated-sources -type f -print 2>/dev/null || true
echo

echo "== Generated application resources =="
find target/generated-resources -type f -print 2>/dev/null || true
echo

echo "== Relevant JAR entries =="
if [[ -f "$JAR" ]]; then
  unzip -l "$JAR" \
    | grep -E 'GeneratedTraceRoute|META-INF/services|plugin-injection'
else
  echo "Build first: $JAR does not exist."
fi
