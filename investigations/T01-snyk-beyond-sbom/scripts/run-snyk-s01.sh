#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in snyk jq unzip find; do
  require_command "$cmd"
done

S01="$(resolve_s01)" || {
  echo "Could not find S01-spring-node." >&2
  echo "Set S01_DIR=/path/to/S01-spring-node" >&2
  exit 1
}

BASE="$ROOT/results/s01/baseline"
OUT="$ROOT/results/s01/snyk"
mkdir -p "$OUT"

for f in service-jar-path.txt normalizer-jar-path.txt stripped-jar-path.txt maven-repo-path.txt; do
  [[ -f "$BASE/$f" ]] || {
    echo "Run ./scripts/baseline-s01.sh first." >&2
    exit 1
  }
done

SERVICE_JAR="$(cat "$BASE/service-jar-path.txt")"
NORMALIZER_JAR="$(cat "$BASE/normalizer-jar-path.txt")"
STRIPPED_JAR="$(cat "$BASE/stripped-jar-path.txt")"
M2="$(cat "$BASE/maven-repo-path.txt")"

snyk --version | tee "$OUT/snyk-version.txt"

echo
echo "S01: $S01"
echo "Output: $OUT"

(
  cd "$S01"
  capture_command \
    "1. Snyk Maven aggregate test" \
    "$OUT/snyk-maven-test.txt" \
    snyk test \
      --maven-aggregate-project \
      --print-deps \
      --json-file-output="$OUT/snyk-maven-test.json" \
      -- \
      -Dmaven.repo.local="$M2"
)

(
  cd "$S01"
  capture_command \
    "2. Snyk Maven aggregate test with provenance" \
    "$OUT/snyk-maven-test-provenance.txt" \
    snyk test \
      --maven-aggregate-project \
      --print-deps \
      --include-provenance \
      --json-file-output="$OUT/snyk-maven-test-provenance.json" \
      -- \
      -Dmaven.repo.local="$M2"
)

(
  cd "$S01"
  capture_command \
    "3. Snyk Maven aggregate CycloneDX SBOM" \
    "$OUT/snyk-maven-sbom.txt" \
    snyk sbom \
      --maven-aggregate-project \
      --format=cyclonedx1.6+json \
      --name=S01-maven-reactor \
      --version=1.0.0 \
      --json-file-output="$OUT/snyk-maven-sbom.json" \
      -- \
      -Dmaven.repo.local="$M2"
)

(
  cd "$S01"
  capture_command \
    "4. Snyk Maven aggregate CycloneDX SBOM with provenance" \
    "$OUT/snyk-maven-sbom-provenance.txt" \
    snyk sbom \
      --maven-aggregate-project \
      --format=cyclonedx1.6+json \
      --name=S01-maven-reactor \
      --version=1.0.0 \
      --include-provenance \
      --json-file-output="$OUT/snyk-maven-sbom-provenance.json" \
      -- \
      -Dmaven.repo.local="$M2"
)

(
  cd "$S01/frontend"
  capture_command \
    "5. Snyk npm source test" \
    "$OUT/snyk-frontend-test.txt" \
    snyk test \
      --print-deps \
      --json-file-output="$OUT/snyk-frontend-test.json"
)

(
  cd "$S01/frontend"
  capture_command \
    "6. Snyk npm source CycloneDX SBOM" \
    "$OUT/snyk-frontend-sbom.txt" \
    snyk sbom \
      --format=cyclonedx1.6+json \
      --json-file-output="$OUT/snyk-frontend-sbom.json"
)

(
  cd "$S01/frontend/dist"
  capture_command \
    "7. Snyk scan of deployable frontend/dist only" \
    "$OUT/snyk-frontend-dist.txt" \
    snyk test \
      --all-projects \
      --json-file-output="$OUT/snyk-frontend-dist.json"
)

capture_command \
  "8. Snyk unmanaged shaded normalizer JAR" \
  "$OUT/snyk-unmanaged-normalizer.txt" \
  snyk test \
    --scan-unmanaged \
    --file="$NORMALIZER_JAR" \
    --print-deps \
    --print-dep-paths \
    --json-file-output="$OUT/snyk-unmanaged-normalizer.json"

capture_command \
  "9. Snyk unmanaged metadata-stripped normalizer JAR" \
  "$OUT/snyk-unmanaged-normalizer-stripped.txt" \
  snyk test \
    --scan-unmanaged \
    --file="$STRIPPED_JAR" \
    --print-deps \
    --print-dep-paths \
    --json-file-output="$OUT/snyk-unmanaged-normalizer-stripped.json"

capture_command \
  "10. Snyk unmanaged final Spring Boot JAR" \
  "$OUT/snyk-unmanaged-service.txt" \
  snyk test \
    --scan-unmanaged \
    --file="$SERVICE_JAR" \
    --print-deps \
    --print-dep-paths \
    --json-file-output="$OUT/snyk-unmanaged-service.json"

echo
echo "== Unpack Spring Boot JAR for recursive unmanaged scan =="
rm -rf "$OUT/service-unpacked"
mkdir -p "$OUT/service-unpacked"
unzip -q "$SERVICE_JAR" -d "$OUT/service-unpacked"

(
  cd "$OUT/service-unpacked"
  capture_command \
    "11. Snyk recursive unmanaged scan of unpacked Spring Boot JAR" \
    "$OUT/snyk-unmanaged-service-unpacked.txt" \
    snyk test \
      --scan-all-unmanaged \
      --print-deps \
      --print-dep-paths \
      --json-file-output="$OUT/snyk-unmanaged-service-unpacked.json"
)

echo
echo "S01 Snyk probes captured."
echo "Run:"
echo "  ./scripts/compare-s01.sh"
