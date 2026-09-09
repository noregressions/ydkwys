#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in snyk jq unzip find; do
  require_command "$cmd"
done

S02="$(resolve_s02)" || {
  echo "Could not find S02-payara-mvnpm." >&2
  echo "Set S02_DIR=/path/to/S02-payara-mvnpm" >&2
  exit 1
}

BASE="$ROOT/results/s02/baseline"
OUT="$ROOT/results/s02/snyk"
mkdir -p "$OUT"

if [[ ! -f "$BASE/war-path.txt" ]]; then
  echo "Run ./scripts/baseline-s02.sh first." >&2
  exit 1
fi

WAR="$(cat "$BASE/war-path.txt")"
if [[ ! -f "$WAR" ]]; then
  echo "Recorded WAR no longer exists: $WAR" >&2
  exit 1
fi

snyk --version | tee "$OUT/snyk-version.txt"

echo
echo "S02: $S02"
echo "WAR: $WAR"
echo "Output: $OUT"

(
  cd "$S02"
  capture_command \
    "1. Snyk normal Maven test + dependency print" \
    "$OUT/snyk-test.txt" \
    snyk test \
      --print-deps \
      --json-file-output="$OUT/snyk-test.json"
)

(
  cd "$S02"
  capture_command \
    "2. Snyk Maven test with experimental provenance" \
    "$OUT/snyk-test-provenance.txt" \
    snyk test \
      --print-deps \
      --include-provenance \
      --json-file-output="$OUT/snyk-test-provenance.json"
)

(
  cd "$S02"
  capture_command \
    "3. Snyk CycloneDX SBOM" \
    "$OUT/snyk-sbom.txt" \
    snyk sbom \
      --file=pom.xml \
      --format=cyclonedx1.6+json \
      --json-file-output="$OUT/snyk-sbom.json"
)

(
  cd "$S02"
  capture_command \
    "4. Snyk CycloneDX SBOM with experimental provenance" \
    "$OUT/snyk-sbom-provenance.txt" \
    snyk sbom \
      --file=pom.xml \
      --format=cyclonedx1.6+json \
      --include-provenance \
      --json-file-output="$OUT/snyk-sbom-provenance.json"
)

(
  cd "$S02"
  capture_command \
    "5. Snyk unmanaged final-WAR scan" \
    "$OUT/snyk-unmanaged-war.txt" \
    snyk test \
      --scan-unmanaged \
      --file="$WAR" \
      --print-deps \
      --print-dep-paths \
      --json-file-output="$OUT/snyk-unmanaged-war.json"
)

echo
echo "== Unpack WAR for embedded-JAR inspection =="
rm -rf "$OUT/war-unpacked"
mkdir -p "$OUT/war-unpacked"
unzip -q "$WAR" -d "$OUT/war-unpacked"
find "$OUT/war-unpacked/WEB-INF/lib" -maxdepth 1 -type f -name '*.jar' -print \
  >"$OUT/embedded-jars.txt" 2>/dev/null || true
cat "$OUT/embedded-jars.txt"

COMMONS_JAR="$(find "$OUT/war-unpacked/WEB-INF/lib" -maxdepth 1 -type f \
  -name 'commons-lang3-*.jar' | sort | head -1 || true)"

if [[ -n "${COMMONS_JAR:-}" && -f "$COMMONS_JAR" ]]; then
  capture_command \
    "6. Positive control: Snyk unmanaged embedded commons-lang3 JAR" \
    "$OUT/snyk-unmanaged-commons-lang3.txt" \
    snyk test \
      --scan-unmanaged \
      --file="$COMMONS_JAR" \
      --print-deps \
      --print-dep-paths \
      --json-file-output="$OUT/snyk-unmanaged-commons-lang3.json"
else
  echo "No embedded commons-lang3 JAR found." \
    | tee "$OUT/snyk-unmanaged-commons-lang3.txt"
  printf '99\n' >"$OUT/snyk-unmanaged-commons-lang3.txt.exit"
fi

(
  cd "$OUT/war-unpacked"
  capture_command \
    "7. Snyk recursive unmanaged scan of unpacked WAR" \
    "$OUT/snyk-unmanaged-unpacked-war.txt" \
    snyk test \
      --scan-all-unmanaged \
      --print-deps \
      --print-dep-paths \
      --json-file-output="$OUT/snyk-unmanaged-unpacked-war.json"
)

echo
echo "S02 Snyk probes captured."
echo "Run:"
echo "  ./scripts/compare-s02.sh"
