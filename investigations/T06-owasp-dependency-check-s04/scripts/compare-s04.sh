#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BASE="results/s04/baseline"
DC="results/s04/dependency-check"

[[ -d "$BASE" && -d "$DC" ]] || {
  echo "Need both baseline and Dependency-Check results." >&2
  exit 1
}

echo "T06 / S04 — OWASP Dependency-Check"
echo "=================================="
echo

echo "== Ground truth: application dependency model =="
grep -E \
  'dev\.noregressions\.trace:maven-plugin-hidden-content|trace-injector|trace-route-payload' \
  "$BASE/maven-app-tree.txt" || true

echo
echo "== Ground truth: plugin dependency model =="
grep -E \
  'trace-injector|trace-route-payload' \
  "$BASE/maven-plugin-resolution.txt" || true

echo
echo "== Ground truth: actual plugin execution realm =="
grep -E \
  'trace-injector|trace-route-payload' \
  "$BASE/maven-plugin-realm.txt" || true

echo
echo "== Ground truth: generated content in final JAR =="
cat "$BASE/app-jar-tracers.txt"
grep -E \
  '/hidden/build-info|trace-route-payload|trace-injector-maven-plugin' \
  "$BASE/generated-route-javap.txt" || true

for label in default-maven plugin-aware-maven final-jar plugin-payload-controls; do
  echo
  echo "== Dependency-Check: $label =="

  dir="$DC/$label"

  if [[ -f "$dir/result.dependency-count.txt" ]]; then
    echo "Dependencies: $(cat "$dir/result.dependency-count.txt")"
    echo "Vulnerability records: $(cat "$dir/result.vulnerability-count.txt")"
    echo "S04 tracked components:"
    if [[ -s "$dir/result.tracers.tsv" ]]; then
      cat "$dir/result.tracers.tsv"
    else
      echo "(none)"
    fi
  else
    echo "(report not captured)"
  fi
done

echo
echo "== Tracer-set differences =="

for pair in \
  "default-maven plugin-aware-maven" \
  "plugin-aware-maven final-jar" \
  "final-jar plugin-payload-controls"
do
  set -- $pair
  a="$1"
  b="$2"

  echo
  echo "-- $a vs $b"

  if [[ -f "$DC/$a/result.tracers.tsv" && -f "$DC/$b/result.tracers.tsv" ]]; then
    diff -u \
      "$DC/$a/result.tracers.tsv" \
      "$DC/$b/result.tracers.tsv" || true
  else
    echo "(missing result)"
  fi
done

echo
echo "Interpretation questions:"
echo "  1. Does the default Maven scan contain either trace-injector or trace-route-payload?"
echo "  2. Does enabling scanPlugins add the plugin and its transitive payload?"
echo "  3. How much larger is the build-tooling dependency universe when plugins are included?"
echo "  4. Does scanning only the final application JAR reconstruct either build-time component?"
echo "  5. Does the final JAR still contain the generated runtime behaviour even if those package identities are absent?"
echo "  6. When the plugin/payload JARs are directly supplied, can Dependency-Check identify them?"
echo "  7. Are any vulnerability findings tied to the two controlled packages?"
echo "  8. Is any difference caused by vulnerability data, or by what was admitted to the dependency inventory?"
