#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

require_command snyk
require_command jq

S04="$(resolve_s04)" || {
  echo "Could not find S04-maven-plugin-hidden-content." >&2
  echo "Set S04_DIR=/path/to/S04-maven-plugin-hidden-content" >&2
  exit 1
}

OUT="$ROOT/results/snyk"
mkdir -p "$OUT"

LOCAL_REPO="$S04/.maven-repo"
JAR="$S04/target/maven-plugin-hidden-content-1.0.0.jar"

if [[ ! -f "$JAR" ]]; then
  echo "S04 JAR is missing. Run ./scripts/baseline.sh first." >&2
  exit 1
fi

snyk --version | tee "$OUT/snyk-version.txt"

echo
echo "S04: $S04"
echo "Output: $OUT"

# Snyk may use 1 for "vulnerabilities found", so capture rather than abort.

(
  cd "$S04"
  capture_command \
    "1. Snyk normal Maven test + dependency print" \
    "$OUT/snyk-test.txt" \
    snyk test \
      --print-deps \
      --json-file-output="$OUT/snyk-test.json" \
      -- \
      -Dmaven.repo.local="$LOCAL_REPO"
)

(
  cd "$S04"
  capture_command \
    "2. Snyk Maven test with experimental provenance" \
    "$OUT/snyk-test-provenance.txt" \
    snyk test \
      --print-deps \
      --include-provenance \
      --json-file-output="$OUT/snyk-test-provenance.json" \
      -- \
      -Dmaven.repo.local="$LOCAL_REPO"
)

(
  cd "$S04"
  capture_command \
    "3. Snyk CycloneDX SBOM" \
    "$OUT/snyk-sbom.txt" \
    snyk sbom \
      --file=pom.xml \
      --format=cyclonedx1.6+json \
      --json-file-output="$OUT/snyk-sbom.json" \
      -- \
      -Dmaven.repo.local="$LOCAL_REPO"
)

(
  cd "$S04"
  capture_command \
    "4. Snyk CycloneDX SBOM with experimental provenance" \
    "$OUT/snyk-sbom-provenance.txt" \
    snyk sbom \
      --file=pom.xml \
      --format=cyclonedx1.6+json \
      --include-provenance \
      --json-file-output="$OUT/snyk-sbom-provenance.json" \
      -- \
      -Dmaven.repo.local="$LOCAL_REPO"
)

(
  cd "$S04"
  capture_command \
    "5. Snyk unmanaged final-JAR scan" \
    "$OUT/snyk-unmanaged-jar.txt" \
    snyk test \
      --scan-unmanaged \
      --file="$JAR" \
      --print-deps \
      --json-file-output="$OUT/snyk-unmanaged-jar.json"
)

echo
echo "Snyk probes captured."
echo "Run:"
echo "  ./scripts/compare.sh"
