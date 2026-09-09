#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/trace-output"
mkdir -p "$OUT"
cd "$ROOT"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need mvn
need jar
need jq

printf '\n==> Declared vs resolved: Jackson\n'
grep -n -A4 'jackson-databind' service/pom.xml || true
mvn -pl service -am dependency:tree \
  -Dincludes=com.fasterxml.jackson.core:jackson-databind \
  | tee "$OUT/jackson-dependency-tree.txt"

printf '\n==> Declared vs resolved: commons-codec\n'
grep -n -A4 'commons-codec' normalizer/pom.xml || true
mvn -pl normalizer dependency:tree \
  -Dincludes=commons-codec:commons-codec \
  | tee "$OUT/codec-dependency-tree.txt"

printf '\n==> Frontend package evidence\n'
if [[ -f frontend/package-lock.json ]]; then
  jq '.packages["node_modules/lodash"] | {version,resolved,integrity}' frontend/package-lock.json \
    | tee "$OUT/lodash-lock-evidence.json"
else
  echo "frontend/package-lock.json does not exist yet; run scripts/build.sh first." >&2
fi

printf '\n==> Build-time Maven software\n'
mvn -q -pl service dependency:resolve-plugins \
  -DoutputFile="$OUT/service-build-plugins.txt"
mvn -q -pl normalizer dependency:resolve-plugins \
  -DoutputFile="$OUT/normalizer-build-plugins.txt"
grep -E 'spring-boot|shade|compiler' "$OUT"/*-build-plugins.txt || true

printf '\n==> Shaded commons-codec evidence\n'
jar tf normalizer/target/normalizer-1.0.0.jar \
  | grep '^com/acme/internal/codec/' \
  | head -20 \
  | tee "$OUT/relocated-codec-classes.txt" || true
jar tf normalizer/target/normalizer-1.0.0.jar \
  | grep '^org/apache/commons/codec/' \
  | head -20 || true

printf '\n==> Spring Boot nested JAR evidence\n'
jar tf service/target/service-1.0.0.jar \
  | grep 'BOOT-INF/lib/.*jackson-databind' \
  | tee "$OUT/jackson-in-boot-jar.txt" || true
jar tf service/target/service-1.0.0.jar \
  | grep 'BOOT-INF/lib/.*normalizer' \
  | tee "$OUT/normalizer-in-boot-jar.txt" || true
jar tf service/target/service-1.0.0.jar \
  | grep 'BOOT-INF/classes/static/' \
  | head -20 \
  | tee "$OUT/frontend-in-boot-jar.txt" || true

if command -v syft >/dev/null 2>&1; then
  printf '\n==> Artifact-observed SBOM\n'
  syft service/target/service-1.0.0.jar \
    -o cyclonedx-json="$OUT/artifact.cdx.json"
  jq '.components[] | select(.name == "jackson-databind" or .name == "normalizer" or .name == "commons-codec" or .name == "lodash") | {name,version,purl}' \
    "$OUT/artifact.cdx.json" || true

  printf '\n==> Frontend bundle observation\n'
  syft frontend/dist -o syft-json="$OUT/frontend-dist.syft.json"
  jq '[.artifacts[] | select(.name == "lodash") | {name,version,locations}]' \
    "$OUT/frontend-dist.syft.json" || true
else
  echo "\nSyft not installed: skipping artifact scans."
fi

printf '\nTrace evidence written to %s\n' "$OUT"
