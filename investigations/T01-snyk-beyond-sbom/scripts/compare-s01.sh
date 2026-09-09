#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BASE="results/s01/baseline"
SNYK="results/s01/snyk"

if [[ ! -d "$BASE" || ! -d "$SNYK" ]]; then
  echo "Need both S01 baseline and Snyk results." >&2
  echo "Run ./scripts/baseline-s01.sh and ./scripts/run-snyk-s01.sh first." >&2
  exit 1
fi

names='commons-codec|jackson-databind|lodash|normalizer|checkout-trace-frontend'

echo "T01 / S01 comparison"
echo "===================="
echo

echo "Tracers:"
echo "  jackson-databind 2.19.4     ordinary nested JAR"
echo "  commons-codec 1.17.1        shaded + relocated, metadata survives"
echo "  commons-codec 1.18.0        ordinary nested JAR in service"
echo "  lodash 4.17.21               bundled into frontend JavaScript"
echo

echo "== Baseline tracked hits =="
for f in \
  "$BASE/maven-normalizer-codec.txt" \
  "$BASE/maven-service-codec.txt" \
  "$BASE/maven-service-jackson.txt" \
  "$BASE/npm-lodash.txt" \
  "$BASE/codec-pom.properties" \
  "$BASE/service-jar-tracers.txt" \
  "$BASE/syft-normalizer.txt" \
  "$BASE/syft-normalizer-stripped.txt" \
  "$BASE/syft-frontend-dist.txt" \
  "$BASE/syft-service-jar.txt"
do
  echo
  echo "-- $f"
  grep -E "$names|version=1\.17\.1" "$f" || echo "(no matching names)"
done

echo
echo "== Snyk command exit codes =="
for f in "$SNYK"/*.exit; do
  [[ -e "$f" ]] || continue
  printf '%-52s %s\n' "$(basename "${f%.exit}")" "$(cat "$f")"
done

echo
echo "== Snyk textual tracked hits =="
for f in "$SNYK"/*.txt; do
  [[ -e "$f" ]] || continue
  echo
  echo "-- $f"
  grep -E "$names" "$f" || echo "(no matching names)"
done

echo
echo "== Snyk JSON tracked hits =="
for f in "$SNYK"/*.json; do
  [[ -s "$f" ]] || continue
  echo
  echo "-- $f"
  jq -r '.. | strings' "$f" 2>/dev/null \
    | grep -E "$names" \
    | sort -u \
    || echo "(no matching names)"
done

echo
echo "== Snyk SBOM relevant components =="
for f in \
  "$SNYK/snyk-maven-sbom.json" \
  "$SNYK/snyk-maven-sbom-provenance.json" \
  "$SNYK/snyk-frontend-sbom.json"
do
  [[ -s "$f" ]] || continue
  echo
  echo "-- $f"
  jq -r '.components[]? | [.name, .version, (.purl // "")] | @tsv' "$f" \
    | grep -E 'commons-codec|jackson-databind|lodash|normalizer|checkout-trace-frontend' \
    || echo "(no relevant components)"
done

echo
echo "== Provenance PURL changes =="
if [[ -s "$SNYK/snyk-maven-sbom.json" && -s "$SNYK/snyk-maven-sbom-provenance.json" ]]; then
  diff -u \
    <(jq -r '.. | objects | .purl? // empty' "$SNYK/snyk-maven-sbom.json" | sort -u) \
    <(jq -r '.. | objects | .purl? // empty' "$SNYK/snyk-maven-sbom-provenance.json" | sort -u) \
    || true
fi

echo
echo "Interpretation questions:"
echo "  1. Does Snyk's Maven reactor view expose commons-codec 1.17.1 and 1.18.0, and in which module contexts?"
echo "  2. Does provenance enrich the same Maven set, or change the component set?"
echo "  3. Does Snyk identify lodash 4.17.21 from npm source/lockfile?"
echo "  4. Does the deployable frontend/dist retain enough package evidence for Snyk to identify lodash?"
echo "  5. Can unmanaged scanning identify commons-codec 1.17.1 inside the shaded custom normalizer JAR?"
echo "  6. Does stripping Maven metadata change Snyk's unmanaged result as it changed Syft's?"
echo "  7. Can an unpacked Spring Boot JAR recover the intact nested JARs?"
echo "  8. Does any artefact-oriented Snyk view recover lodash after Vite bundling?"
