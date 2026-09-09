#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BASE="results/s02/baseline"
SNYK="results/s02/snyk"

if [[ ! -d "$BASE" || ! -d "$SNYK" ]]; then
  echo "Need both S02 baseline and Snyk results." >&2
  echo "Run ./scripts/baseline-s02.sh and ./scripts/run-snyk-s02.sh first." >&2
  exit 1
fi

names='lodash-es|commons-lang3|jakarta|esbuild|mvnpm'

echo "T01 / S02 comparison"
echo "===================="
echo

echo "Tracer of interest:"
echo "  lodash-es"
echo
echo "Positive control:"
echo "  commons-lang3"
echo

echo "== Baseline name hits =="
for f in \
  "$BASE/maven-dependency-tree.txt" \
  "$BASE/maven-resolve-plugins.txt" \
  "$BASE/maven-plugin-realm.txt" \
  "$BASE/source-map-lodash.txt" \
  "$BASE/maven-bom.json" \
  "$BASE/syft-generated-web.txt" \
  "$BASE/syft-war.txt"
do
  echo
  echo "-- $f"
  grep -E "$names" "$f" || echo "(no matching names)"
done

echo
echo "== Snyk command exit codes =="
for f in "$SNYK"/*.exit; do
  [[ -e "$f" ]] || continue
  printf '%-48s %s\n' "$(basename "${f%.exit}")" "$(cat "$f")"
done

echo
echo "== Snyk textual name hits =="
for f in "$SNYK"/*.txt; do
  [[ -e "$f" ]] || continue
  echo
  echo "-- $f"
  grep -E "$names" "$f" || echo "(no matching names)"
done

echo
echo "== Snyk JSON name hits =="
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
for f in "$SNYK/snyk-sbom.json" "$SNYK/snyk-sbom-provenance.json"; do
  [[ -s "$f" ]] || continue
  echo
  echo "-- $f"
  jq -r '.components[]? | [.name, .version, (.purl // "")] | @tsv' "$f" \
    | grep -E 'lodash|commons-lang3|jakarta|esbuild|mvnpm' \
    || echo "(no relevant components)"
done

echo
echo "Interpretation questions:"
echo "  1. Does Snyk Maven analysis identify lodash-es anywhere?"
echo "  2. Does Snyk's SBOM identify lodash-es?"
echo "  3. Does --include-provenance broaden the component set?"
echo "  4. Does direct WAR inspection identify embedded commons-lang3?"
echo "  5. Does unpacking the WAR improve Snyk's Java package identification?"
echo "  6. Can any Snyk mode recover lodash-es after it has become bundled JavaScript?"
echo "  7. What does Snyk know about Jakarta provided dependencies compared with WAR bytes?"
