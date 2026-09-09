#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in mvn npm jq unzip jar grep find; do
  require_command "$cmd"
done

S01="$(resolve_s01)" || {
  echo "Could not find S01-spring-node." >&2
  echo "Set S01_DIR=/path/to/S01-spring-node" >&2
  exit 1
}

OUT="$ROOT/results/s01/baseline"
M2="$ROOT/results/s01/maven-repo"
mkdir -p "$OUT" "$M2"

echo "S01: $S01"
echo "Output: $OUT"
echo "Isolated Maven repo for provenance probes: $M2"

echo
echo "== Ensure S01 is built =="
(
  cd "$S01"
  ./scripts/build.sh
) >"$OUT/build.log" 2>&1
cat "$OUT/build.log"

echo
echo "== Populate isolated Maven repository =="
(
  cd "$S01"
  mvn -DskipTests -Dmaven.repo.local="$M2" install
) >"$OUT/maven-install.log" 2>&1
tail -n 30 "$OUT/maven-install.log"

SERVICE_JAR="$S01/service/target/service-1.0.0.jar"
NORMALIZER_JAR="$S01/normalizer/target/normalizer-1.0.0.jar"
STRIPPED_JAR="$S01/trace-output/normalizer-no-codec-metadata.jar"

for f in "$SERVICE_JAR" "$NORMALIZER_JAR"; do
  [[ -f "$f" ]] || {
    echo "Expected built artefact not found: $f" >&2
    exit 1
  }
done

printf '%s\n' "$SERVICE_JAR" >"$OUT/service-jar-path.txt"
printf '%s\n' "$NORMALIZER_JAR" >"$OUT/normalizer-jar-path.txt"
printf '%s\n' "$M2" >"$OUT/maven-repo-path.txt"

echo
echo "== Maven tracked-component resolution =="

(
  cd "$S01"
  mvn -pl normalizer dependency:tree \
    -Dincludes=commons-codec:commons-codec
) >"$OUT/maven-normalizer-codec.txt" 2>&1
cat "$OUT/maven-normalizer-codec.txt"

(
  cd "$S01"
  mvn -pl service -am dependency:tree \
    -Dincludes=commons-codec:commons-codec \
    -Dverbose
) >"$OUT/maven-service-codec.txt" 2>&1
cat "$OUT/maven-service-codec.txt"

(
  cd "$S01"
  mvn -pl service -am dependency:tree \
    -Dincludes=com.fasterxml.jackson.core:jackson-databind
) >"$OUT/maven-service-jackson.txt" 2>&1
cat "$OUT/maven-service-jackson.txt"

echo
echo "== npm tracked-component resolution =="
(
  cd "$S01/frontend"
  npm ls lodash
) >"$OUT/npm-lodash.txt" 2>&1
cat "$OUT/npm-lodash.txt"

jq '.packages["node_modules/lodash"] // empty' \
  "$S01/frontend/package-lock.json" \
  >"$OUT/lodash-lock-entry.json"
cat "$OUT/lodash-lock-entry.json"

echo
echo "== Shaded normalizer evidence =="
unzip -l "$NORMALIZER_JAR" \
  | grep 'com/acme/internal/codec' \
  | head \
  | tee "$OUT/relocated-codec-classes.txt" || true

unzip -l "$NORMALIZER_JAR" \
  | grep 'org/apache/commons/codec' \
  | head \
  >"$OUT/original-codec-classes.txt" || true

unzip -l "$NORMALIZER_JAR" \
  | grep 'META-INF/maven/commons-codec' \
  | tee "$OUT/codec-maven-metadata.txt" || true

unzip -p "$NORMALIZER_JAR" \
  META-INF/maven/commons-codec/commons-codec/pom.properties \
  | tee "$OUT/codec-pom.properties"

echo
echo "== Controlled metadata-loss artefact =="
(
  cd "$S01"
  ./scripts/strip-codec-metadata.sh
) >"$OUT/strip-codec-metadata.txt" 2>&1
cat "$OUT/strip-codec-metadata.txt"

[[ -f "$STRIPPED_JAR" ]] || {
  echo "Expected metadata-stripped artefact not found: $STRIPPED_JAR" >&2
  exit 1
}
printf '%s\n' "$STRIPPED_JAR" >"$OUT/stripped-jar-path.txt"

echo
echo "== Frontend deployable output =="
find "$S01/frontend/dist" -maxdepth 2 -type f -print \
  | tee "$OUT/frontend-dist-files.txt"

echo
echo "== Final Spring Boot JAR tracked-component evidence =="
unzip -l "$SERVICE_JAR" \
  | grep -E 'jackson-databind|commons-codec|normalizer-1\.0\.0\.jar|BOOT-INF/classes/static/' \
  | tee "$OUT/service-jar-tracers.txt" || true

echo
echo "== Maven/CycloneDX module SBOM baseline =="
(
  cd "$S01"
  mvn -pl service -am \
    org.cyclonedx:cyclonedx-maven-plugin:2.9.3:makeBom \
    -DoutputFormat=json
) >"$OUT/maven-cyclonedx.log" 2>&1
tail -n 40 "$OUT/maven-cyclonedx.log"

cp "$S01/normalizer/target/bom.json" "$OUT/normalizer-maven-bom.json"
cp "$S01/service/target/bom.json" "$OUT/service-maven-bom.json"

echo
echo "Relevant normalizer Maven BOM components:"
jq -r '.components[]? | [.name, .version, (.purl // "")] | @tsv' \
  "$OUT/normalizer-maven-bom.json" \
  | grep -E 'commons-codec|jackson|normalizer|lodash' || true

echo
echo "Relevant service Maven BOM components:"
jq -r '.components[]? | [.name, .version, (.purl // "")] | @tsv' \
  "$OUT/service-maven-bom.json" \
  | grep -E 'commons-codec|jackson-databind|normalizer|lodash' || true

if command -v syft >/dev/null 2>&1; then
  echo
  echo "== Syft shaded normalizer baseline =="
  syft "$NORMALIZER_JAR" | tee "$OUT/syft-normalizer.txt"

  echo
  echo "== Syft metadata-stripped normalizer baseline =="
  syft "$STRIPPED_JAR" | tee "$OUT/syft-normalizer-stripped.txt"

  echo
  echo "== Syft frontend/dist baseline =="
  syft "$S01/frontend/dist" | tee "$OUT/syft-frontend-dist.txt"

  echo
  echo "== Syft final service JAR baseline =="
  syft "$SERVICE_JAR" | tee "$OUT/syft-service-jar.txt"
else
  echo "Syft not installed." | tee "$OUT/syft-normalizer.txt"
  echo "Syft not installed." | tee "$OUT/syft-normalizer-stripped.txt"
  echo "Syft not installed." | tee "$OUT/syft-frontend-dist.txt"
  echo "Syft not installed." | tee "$OUT/syft-service-jar.txt"
fi

echo
echo "S01 baseline captured in $OUT"
