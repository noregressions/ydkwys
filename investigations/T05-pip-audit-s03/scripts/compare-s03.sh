#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BASE="results/s03/baseline"
AUDIT="results/s03/pip-audit"

[[ -d "$BASE" && -d "$AUDIT" ]] || {
  echo "Need both baseline and pip-audit results." >&2
  exit 1
}

echo "T05 / S03 — pip-audit across Python dependency/execution boundaries"
echo "=================================================================="
echo

echo "== Ground truth =="
cat "$BASE/requirements.txt"
grep '^Requires-Dist:' "$BASE/reportkit-metadata.txt" || true
grep -E \
  'build-backend|backend-path|name =|version =' \
  "$BASE/tracehook-pyproject.toml" || true

echo
echo "sdist generated runtime files:"
if [[ -s "$BASE/sdist-generated-files.txt" ]]; then
  cat "$BASE/sdist-generated-files.txt"
else
  echo "(none)"
fi

echo
echo "installed generated marker:"
cat "$BASE/build-hook.json"

echo
echo "pip install build signals:"
cat "$BASE/pip-install-relevant.txt"

echo
echo "== pip-audit requirements resolution signals =="
cat "$AUDIT/requirements-resolved-signals.txt" || true

echo
echo "== controlled PEP 517 audit-execution marker =="
if [[ -f "$AUDIT/pep517-audit-executed.txt" ]]; then
  cat "$AUDIT/pep517-audit-executed.txt"
else
  echo "(not created)"
fi

echo
echo "== pip-audit dependency sets =="

for label in requirements-resolved requirements-no-deps requirements-no-deps-disable-pip installed; do
  echo
  echo "-- $label"
  if [[ -f "$AUDIT/$label.tsv" ]]; then
    cat "$AUDIT/$label.tsv"
  else
    echo "(not captured)"
  fi
done

echo
echo "== installed-environment vulnerability findings =="
if [[ -f "$AUDIT/installed.json" ]]; then
  jq -r '
    .dependencies[]?
    | select((.vulns // []) | length > 0)
    | . as $dep
    | .vulns[]
    | [
        $dep.name,
        ($dep.version // ""),
        .id,
        ((.aliases // []) | join(",")),
        ((.fix_versions // []) | join(","))
      ]
    | @tsv
  ' "$AUDIT/installed.json"
fi

echo
echo "== pip-audit installed CycloneDX components =="
if [[ -f "$AUDIT/installed-cdx-components.tsv" ]]; then
  grep -E \
    '^reportkit[[:space:]]|^tracehook-demo[[:space:]]|^tracehook_demo[[:space:]]' \
    "$AUDIT/installed-cdx-components.tsv" || true
else
  echo "(not captured)"
fi

echo
echo "Interpretation questions:"
echo "  1. Does normal requirements resolution recover tracehook-demo transitively?"
echo "  2. Does --no-deps alone remove the transitive dependency in this observed pip-audit version?"
echo "  3. Does --no-deps --disable-pip reduce the audit set to the explicitly pinned requirement?"
echo "  4. Does the controlled marker prove that normal requirements auditing executes PEP 517 backend code?"
echo "  5. Does pip-audit report that reportkit or tracehook-demo are skipped because they are not found in the vulnerability service?"
echo "  6. Does auditing the already-installed environment recover both installed package identities?"
echo "  7. Does the audit output say anything about build-hook.json being generated during wheel construction?"
echo "  8. Does the CycloneDX output preserve skipped/private package identities or omit them?"
echo "  9. What evidence is needed to distinguish package presence from PEP 517 execution history?"
