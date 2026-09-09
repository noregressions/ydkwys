#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BASE="results/s03/baseline"
SNYK="results/s03/snyk"

if [[ ! -d "$BASE" || ! -d "$SNYK" ]]; then
  echo "Need both S03 baseline and Snyk results." >&2
  echo "Run ./scripts/baseline-s03.sh and ./scripts/run-snyk-s03.sh first." >&2
  exit 1
fi

echo "T01 / S03 comparison"
echo "===================="
echo

echo "Tracers:"
echo "  reportkit 1.0.0"
echo "  tracehook-demo 1.0.0"
echo "  tracehook_backend"
echo "  tracehook_backend.build_wheel"
echo "  build-hook.json"
echo

echo "== Baseline package/build evidence =="
for f in \
  "$BASE/requirements.txt" \
  "$BASE/reportkit-metadata.txt" \
  "$BASE/tracehook-sdist-files.txt" \
  "$BASE/tracehook-pyproject.toml" \
  "$BASE/tracehook-backend-relevant.txt" \
  "$BASE/pip-build-evidence.txt" \
  "$BASE/pip-freeze.txt" \
  "$BASE/pip-show.txt" \
  "$BASE/installed-tracehook-files.txt" \
  "$BASE/build-hook.json" \
  "$BASE/runtime-trace.txt" \
  "$BASE/generated-wheel-relevant-files.txt" \
  "$BASE/generated-wheel-metadata.txt"
do
  echo
  echo "-- $f"
  grep -E \
    'reportkit|tracehook|build_wheel|build-hook|pep517-build-backend-executed|Requires-Dist|build-backend' \
    "$f" || echo "(no matching evidence)"
done

echo
echo "== Snyk command exit codes =="
for f in "$SNYK"/*.exit; do
  [[ -e "$f" ]] || continue
  printf '%-52s %s\n' "$(basename "${f%.exit}")" "$(cat "$f")"
done

echo
echo "== Snyk package identity hits =="
for f in "$SNYK"/*.txt "$SNYK"/*.json; do
  [[ -s "$f" ]] || continue
  echo
  echo "-- $f"
  grep -E \
    'reportkit|tracehook-demo|tracehook_demo' \
    "$f" || echo "(no package identity hits)"
done

echo
echo "== Snyk build-execution evidence hits =="
for token in \
  'tracehook_backend' \
  'build_wheel' \
  'build-hook.json' \
  'pep517-build-backend-executed'
do
  echo
  echo "-- $token"
  grep -R -n -F "$token" "$SNYK" \
    --include='*.txt' --include='*.json' \
    || echo "(no hits)"
done

echo
echo "== Snyk SBOM tracked components =="
if [[ -s "$SNYK/snyk-pip-sbom.json" ]]; then
  jq -r '
    .components[]?
    | [.name, .version, (.purl // "")]
    | @tsv
  ' "$SNYK/snyk-pip-sbom.json" \
    | grep -E 'reportkit|tracehook' \
    || echo "(no tracked components)"
fi

echo
echo "== Snyk SBOM relationships involving tracked components =="
if [[ -s "$SNYK/snyk-pip-sbom.json" ]]; then
  jq -r '
    .dependencies[]?
    | select(
        (.ref // "" | test("reportkit|tracehook"; "i"))
        or ((.dependsOn // []) | join(" ") | test("reportkit|tracehook"; "i"))
      )
    | [.ref, ((.dependsOn // []) | join(","))]
    | @tsv
  ' "$SNYK/snyk-pip-sbom.json" || true
fi

echo
echo "Interpretation questions:"
echo "  1. Does Snyk recover tracehook-demo as a transitive dependency from the installed Pip environment?"
echo "  2. Does the Snyk SBOM preserve reportkit -> tracehook-demo?"
echo "  3. Does either Snyk view expose that tracehook-demo arrived as an sdist?"
echo "  4. Does either view name tracehook_backend or build_wheel?"
echo "  5. Does either view expose build-hook.json or the generated runtime files?"
echo "  6. Can Snyk treat the unpacked PEP 517 sdist itself as a supported Python project?"
echo "  7. Can Snyk treat the generated wheel or site-packages directory as a project without requirements metadata?"
echo "  8. What execution history is present in pip/build evidence but absent from Snyk's dependency inventory?"
