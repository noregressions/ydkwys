#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BASE="results/s02/baseline"
GRYPE="results/s02/grype"

[[ -d "$BASE" && -d "$GRYPE" ]] || {
  echo "Need both baseline and Grype results." >&2
  exit 1
}

echo "T04 / S02 — Grype: image discovery vs supplied SBOM"
echo "===================================================="
echo

echo "== Ground truth =="
grep -E \
  'commons-lang3|jakarta\.jakartaee-web-api' \
  "$BASE/maven-app-tree.txt" || true

grep -E \
  'esbuild-maven-plugin|lodash-es' \
  "$BASE/maven-plugin-tracers.txt" || true

echo
echo "== Final-image inventory counts =="
printf 'Syft JSON packages: '
cat "$BASE/syft-json-package-count.txt"
printf 'CycloneDX components: '
cat "$BASE/cdx-component-count.txt"

echo
echo "== Important final-image identities from Syft =="
grep -E \
  '^commons-lang3|^lodash-es|^payara-mvnpm-trace-lab|^jakarta\.' \
  "$BASE/syft-json-tracers.txt" || true

for label in direct-image syft-json cyclonedx; do
  echo
  echo "== Grype $label summary =="
  grep -E \
    'Packages|Scanned for vulnerabilities|vulnerability matches|by severity|by status' \
    "$GRYPE/$label.table.txt" || true

  printf 'Unique vulnerability matches: '
  if [[ -f "$GRYPE/$label.matches.tsv" ]]; then
    wc -l <"$GRYPE/$label.matches.tsv" | tr -d ' '
  else
    echo "(not captured)"
  fi

  echo "Tracer-related matches:"
  if [[ -s "$GRYPE/$label.tracer-matches.tsv" ]]; then
    cat "$GRYPE/$label.tracer-matches.tsv"
  else
    echo "(none)"
  fi
done

echo
echo "== Exact match-set differences =="
for f in \
  diff-direct-vs-syft-json.txt \
  diff-direct-vs-cyclonedx.txt \
  diff-syft-json-vs-cyclonedx.txt
do
  echo
  echo "-- $f"
  if [[ -s "$GRYPE/$f" ]]; then
    cat "$GRYPE/$f"
  else
    echo "(no differences)"
  fi
done

echo
echo "== PURL controls =="

for label in purl-commons-lang3 purl-lodash-es; do
  echo
  echo "-- $label"
  if [[ -s "$GRYPE/$label.matches.tsv" ]]; then
    cat "$GRYPE/$label.matches.tsv"
  else
    echo "(no vulnerability matches)"
  fi
done

echo
echo "Interpretation questions:"
echo "  1. How many vulnerability matches does Grype report when it discovers the image directly?"
echo "  2. How many packages/components are present in the Syft JSON and CycloneDX inventories?"
echo "  3. Are the direct-image and Syft-JSON vulnerability match sets identical?"
echo "  4. Are the Syft-JSON and CycloneDX vulnerability match sets identical?"
echo "  5. Does CycloneDX lose enough package metadata to change Grype's vulnerability answer?"
echo "  6. Is commons-lang3 represented in the image inventory, and does it have a Grype vulnerability match?"
echo "  7. Is lodash-es absent from the final image inventories even though Maven plugin evidence proves it participated in the build?"
echo "  8. Does the direct lodash-es PURL control produce any vulnerability match independently of image discovery?"
echo "  9. Which Jakarta/Payara findings come from the server/base image rather than the application WAR?"
echo " 10. If answers differ, is the cause inventory construction, SBOM representation, or the vulnerability database?"
