#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in mvn jq unzip grep find; do
  require_command "$cmd"
done

S02="$(resolve_s02)" || {
  echo "Could not find S02-payara-mvnpm." >&2
  echo "Set S02_DIR=/path/to/S02-payara-mvnpm" >&2
  exit 1
}

OUT="$ROOT/results/s02/baseline"
mkdir -p "$OUT"

echo "S02: $S02"
echo "Output: $OUT"

echo
echo "== Ensure S02 is built =="
(
  cd "$S02"
  ./scripts/build.sh
) >"$OUT/build.log" 2>&1
cat "$OUT/build.log"

WAR="$(find "$S02/target" -maxdepth 1 -type f -name '*.war' | sort | head -1)"
if [[ -z "${WAR:-}" || ! -f "$WAR" ]]; then
  echo "Could not find built WAR beneath $S02/target" >&2
  exit 1
fi
printf '%s\n' "$WAR" >"$OUT/war-path.txt"

echo
echo "WAR: $WAR"

echo
echo "== Maven project dependency tree =="
(
  cd "$S02"
  mvn dependency:tree
) >"$OUT/maven-dependency-tree.txt" 2>&1
cat "$OUT/maven-dependency-tree.txt"

echo
echo "== Maven plugin resolution =="
(
  cd "$S02"
  mvn dependency:resolve-plugins
) >"$OUT/maven-resolve-plugins.txt" 2>&1
grep -E 'esbuild|lodash-es|mvnpm|commons-lang3|jakarta' \
  "$OUT/maven-resolve-plugins.txt" || true

echo
echo "== Actual Maven plugin execution realm =="
(
  cd "$S02"
  mvn -X generate-resources 2>&1 \
    | grep -E 'esbuild|lodash-es|mvnpm|Created new class realm|Included:'
) >"$OUT/maven-plugin-realm.txt"
cat "$OUT/maven-plugin-realm.txt"

echo
echo "== Generated browser bundle evidence =="
find "$S02/target/generated-web" -maxdepth 3 -type f -print \
  >"$OUT/generated-web-files.txt" 2>/dev/null || true
cat "$OUT/generated-web-files.txt"

if [[ -f "$S02/target/generated-web/assets/app.js.map" ]]; then
  grep -E 'lodash-es|escape\.js|startCase\.js' \
    "$S02/target/generated-web/assets/app.js.map" \
    >"$OUT/source-map-lodash.txt" || true
  cat "$OUT/source-map-lodash.txt"
else
  echo "No app.js.map found." | tee "$OUT/source-map-lodash.txt"
fi

echo
echo "== Final WAR relevant entries =="
unzip -l "$WAR" \
  | grep -E 'commons-lang3|assets/app\.js|app\.js\.map|lodash' \
  | tee "$OUT/war-relevant-entries.txt" || true

echo
echo "== Maven-model CycloneDX =="
(
  cd "$S02"
  mvn \
    org.cyclonedx:cyclonedx-maven-plugin:2.9.3:makeBom \
    -DoutputFormat=json
) >"$OUT/maven-cyclonedx.log" 2>&1
cat "$OUT/maven-cyclonedx.log"

cp "$S02/target/bom.json" "$OUT/maven-bom.json"

echo
echo "Relevant Maven BOM components:"
jq -r '.components[]? | [.group // "", .name, .version] | @tsv' \
  "$OUT/maven-bom.json" \
  | grep -E 'commons-lang3|jakarta|lodash|mvnpm|esbuild' \
  || true

if command -v syft >/dev/null 2>&1; then
  echo
  echo "== Syft generated-web baseline =="
  syft "dir:$S02/target/generated-web" \
    | tee "$OUT/syft-generated-web.txt"

  echo
  echo "== Syft WAR baseline =="
  syft "$WAR" \
    | tee "$OUT/syft-war.txt"
else
  echo "Syft not installed." | tee "$OUT/syft-generated-web.txt"
  echo "Syft not installed." | tee "$OUT/syft-war.txt"
fi

echo
echo "S02 baseline captured in $OUT"
