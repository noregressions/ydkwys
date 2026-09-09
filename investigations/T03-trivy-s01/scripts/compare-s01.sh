#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BASE="results/s01/baseline"
TRIVY="results/s01/trivy"

[[ -d "$BASE" && -d "$TRIVY" ]] || {
  echo "Need both baseline and Trivy results." >&2
  exit 1
}

echo "T03 / S01 — Trivy across evidence boundaries"
echo "=============================================="
echo

echo "== Baseline ground truth =="
grep -E \
  'commons-codec|jackson-databind|normalizer' \
  "$BASE/maven-normalizer.txt" \
  "$BASE/maven-service.txt" || true
cat "$BASE/npm-lodash.txt" || true

echo
echo "== Trivy tracked identity by boundary =="

for label in \
  normalizer-pom \
  service-pom \
  frontend-lock \
  normalizer-jar \
  normalizer-stripped-jar \
  service-jar \
  frontend-dist \
  container-image
do
  echo
  echo "-- $label"
  if [[ ! -f "$TRIVY/$label.tracers.txt" ]]; then
    echo "(not captured)"
  elif [[ -s "$TRIVY/$label.tracers.txt" ]]; then
    cat "$TRIVY/$label.tracers.txt"
  else
    echo "(no tracked identities)"
  fi
done

echo
echo "== Trivy tracked vulnerabilities by boundary =="

for label in \
  normalizer-pom \
  service-pom \
  frontend-lock \
  normalizer-jar \
  normalizer-stripped-jar \
  service-jar \
  frontend-dist \
  container-image
do
  echo
  echo "-- $label"
  if [[ ! -f "$TRIVY/$label.vulns.txt" ]]; then
    echo "(not captured)"
  elif [[ -s "$TRIVY/$label.vulns.txt" ]]; then
    cat "$TRIVY/$label.vulns.txt"
  else
    echo "(no tracked vulnerability findings)"
  fi
done

echo
echo "Interpretation questions:"
echo "  1. Does Trivy identify codec 1.17.1 from normalizer/pom.xml?"
echo "  2. Does Trivy identify codec 1.17.1 from the shaded normalizer JAR?"
echo "  3. Does removing only codec Maven metadata change Trivy's answer?"
echo "  4. Does Trivy identify codec 1.18.0 and Jackson from the service boundary?"
echo "  5. Does the service JAR expose both codec versions to Trivy?"
echo "  6. Does Trivy identify lodash 4.17.21 from package-lock.json?"
echo "  7. Does Trivy recover lodash from frontend/dist after Vite bundling?"
echo "  8. Does Trivy recover lodash from the final container image?"
echo "  9. Do vulnerability findings change when package identity changes?"
echo " 10. Which boundary gives the broadest deployed view, and which gives the best build-time history?"
