#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in mvn jar javap grep find cp; do
  require_command "$cmd"
done

S04="$(resolve_s04)" || {
  echo "Could not find S04-maven-plugin-hidden-content. Set S04_DIR=/path/to/S04-maven-plugin-hidden-content" >&2
  exit 1
}

OUT="$ROOT/results/s04/baseline"
CTRL="$ROOT/results/s04/controls"
mkdir -p "$OUT" "$CTRL"

LOCAL_REPO="$S04/.maven-repo"
APP_JAR="$S04/target/maven-plugin-hidden-content-1.0.0.jar"

echo "S04: $S04"
echo "Output: $OUT"

echo
echo "== Build S04 =="
(
  cd "$S04"
  ./scripts/build.sh
) | tee "$OUT/build.txt"

echo
echo "== Maven application dependency model =="
(
  cd "$S04"
  mvn \
    -Dmaven.repo.local="$LOCAL_REPO" \
    dependency:tree
) | tee "$OUT/maven-app-tree.txt"

echo
echo "== Maven plugin dependency model =="
(
  cd "$S04"
  mvn \
    -Dmaven.repo.local="$LOCAL_REPO" \
    dependency:resolve-plugins \
    -DincludeArtifactIds=trace-injector-maven-plugin
) | tee "$OUT/maven-plugin-resolution.txt"

echo
echo "== Maven plugin execution realm =="
(
  cd "$S04"
  mvn \
    -Dmaven.repo.local="$LOCAL_REPO" \
    -X generate-sources 2>&1
) >"$OUT/maven-generate-sources-debug.txt"

grep -E \
  'trace-injector|trace-route-payload|Created new class realm|Populating class realm|Included:' \
  "$OUT/maven-generate-sources-debug.txt" \
  | tee "$OUT/maven-plugin-realm.txt" || true

echo
echo "== Generated source/resources =="
find \
  "$S04/target/generated-sources/trace-injector" \
  "$S04/target/generated-resources/trace-injector" \
  -type f -print \
  | sort \
  | tee "$OUT/generated-files.txt"

echo
echo "== Final JAR hidden-content boundary =="
jar tf "$APP_JAR" \
  | grep -E \
    'GeneratedTraceRoute|META-INF/services|plugin-injection|META-INF/maven' \
  | tee "$OUT/app-jar-tracers.txt" || true

echo
echo "== Final JAR bytecode strings =="
javap \
  -classpath "$APP_JAR" \
  -c -p \
  dev.noregressions.trace.s04.generated.GeneratedTraceRoute \
  | tee "$OUT/generated-route-javap.txt"

echo
echo "== Prepare direct plugin/payload controls =="

PLUGIN_JAR="$LOCAL_REPO/dev/noregressions/trace/trace-injector-maven-plugin/1.0.0/trace-injector-maven-plugin-1.0.0.jar"
PAYLOAD_JAR="$LOCAL_REPO/dev/noregressions/trace/trace-route-payload/1.0.0/trace-route-payload-1.0.0.jar"

cp "$PLUGIN_JAR" "$CTRL/"
cp "$PAYLOAD_JAR" "$CTRL/"

printf '%s\n' "$APP_JAR" >"$OUT/app-jar-path.txt"
printf '%s\n' "$PLUGIN_JAR" >"$OUT/plugin-jar-path.txt"
printf '%s\n' "$PAYLOAD_JAR" >"$OUT/payload-jar-path.txt"

ls -l "$CTRL" | tee "$OUT/control-jars.txt"

echo
echo "T06 / S04 baseline captured."
