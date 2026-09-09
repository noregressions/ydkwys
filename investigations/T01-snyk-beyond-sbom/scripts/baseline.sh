#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

require_command mvn
require_command jq

S04="$(resolve_s04)" || {
  echo "Could not find S04-maven-plugin-hidden-content." >&2
  echo "Set S04_DIR=/path/to/S04-maven-plugin-hidden-content" >&2
  exit 1
}

OUT="$ROOT/results/baseline"
mkdir -p "$OUT"

LOCAL_REPO="$S04/.maven-repo"
JAR="$S04/target/maven-plugin-hidden-content-1.0.0.jar"

echo "S04: $S04"
echo "Output: $OUT"

echo
echo "== Ensure S04 is built =="
(
  cd "$S04"
  ./scripts/build.sh
) >"$OUT/build.log" 2>&1
cat "$OUT/build.log"

echo
echo "== Maven project dependency tree =="
(
  cd "$S04"
  mvn -Dmaven.repo.local="$LOCAL_REPO" dependency:tree
) >"$OUT/maven-dependency-tree.txt" 2>&1
cat "$OUT/maven-dependency-tree.txt"

echo
echo "== Maven plugin resolution =="
(
  cd "$S04"
  mvn \
    -Dmaven.repo.local="$LOCAL_REPO" \
    dependency:resolve-plugins \
    -DincludeArtifactIds=trace-injector-maven-plugin
) >"$OUT/maven-resolve-plugins.txt" 2>&1
cat "$OUT/maven-resolve-plugins.txt"

echo
echo "== Actual Maven plugin ClassRealm =="
(
  cd "$S04"
  mvn \
    -Dmaven.repo.local="$LOCAL_REPO" \
    -X generate-sources 2>&1 \
    | grep -E 'trace-injector|trace-route-payload'
) >"$OUT/maven-plugin-realm.txt"
cat "$OUT/maven-plugin-realm.txt"

echo
echo "== Maven-model CycloneDX =="
(
  cd "$S04"
  mvn \
    -Dmaven.repo.local="$LOCAL_REPO" \
    org.cyclonedx:cyclonedx-maven-plugin:2.9.3:makeBom \
    -DoutputFormat=json
) >"$OUT/maven-cyclonedx.log" 2>&1
cat "$OUT/maven-cyclonedx.log"

cp "$S04/target/bom.json" "$OUT/maven-bom.json"

echo
echo "Relevant Maven BOM components:"
jq -r '.components[]? | [.name, .version] | @tsv' "$OUT/maven-bom.json" \
  | grep -E 'trace-injector|trace-route-payload|maven-plugin-hidden-content' \
  || true

echo
echo "== Final JAR evidence =="
unzip -l "$JAR" \
  | grep -E 'GeneratedTraceRoute|META-INF/services|plugin-injection' \
  | tee "$OUT/jar-evidence.txt"

if command -v syft >/dev/null 2>&1; then
  echo
  echo "== Syft final-JAR baseline =="
  syft "$JAR" | tee "$OUT/syft-final-jar.txt"
else
  echo "Syft not installed; final-JAR Syft baseline skipped." \
    | tee "$OUT/syft-final-jar.txt"
fi

echo
echo "Baseline captured in $OUT"
