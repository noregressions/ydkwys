#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BASE="results/baseline"
SNYK="results/snyk"

if [[ ! -d "$BASE" || ! -d "$SNYK" ]]; then
  echo "Need both baseline and Snyk results." >&2
  echo "Run ./scripts/baseline.sh and ./scripts/run-snyk.sh first." >&2
  exit 1
fi

names='trace-injector-maven-plugin|trace-route-payload|maven-plugin-hidden-content'

echo "T01 comparison"
echo "=============="
echo

echo "Known names:"
echo "  trace-injector-maven-plugin"
echo "  trace-route-payload"
echo "  maven-plugin-hidden-content"
echo

echo "== Baseline name hits =="
for f in \
  "$BASE/maven-dependency-tree.txt" \
  "$BASE/maven-resolve-plugins.txt" \
  "$BASE/maven-plugin-realm.txt" \
  "$BASE/maven-bom.json" \
  "$BASE/syft-final-jar.txt"
do
  echo
  echo "-- $f"
  grep -E "$names" "$f" || echo "(no matching names)"
done

echo
echo "== Snyk command exit codes =="
for f in "$SNYK"/*.exit; do
  [[ -e "$f" ]] || continue
  printf '%-42s %s\n' "$(basename "${f%.exit}")" "$(cat "$f")"
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
  if command -v jq >/dev/null 2>&1; then
    jq -r '.. | strings' "$f" 2>/dev/null \
      | grep -E "$names" \
      | sort -u \
      || echo "(no matching names)"
  else
    grep -E "$names" "$f" || echo "(no matching names)"
  fi
done

echo
echo "== Snyk SBOM components, if generated =="
for f in \
  "$SNYK/snyk-sbom.json" \
  "$SNYK/snyk-sbom-provenance.json"
do
  [[ -s "$f" ]] || continue
  echo
  echo "-- $f"
  jq -r '.components[]? | [.name, .version, (.purl // "")] | @tsv' "$f" \
    || true
done

echo
echo "Interpretation questions:"
echo "  1. Does normal Snyk Maven analysis expose plugin or payload?"
echo "  2. Does Snyk's SBOM expose either?"
echo "  3. Does --include-provenance change the visible evidence?"
echo "  4. Can unmanaged JAR analysis identify anything useful?"
echo "  5. Which S04 ground-truth facts remain visible only in Maven's plugin domain?"
