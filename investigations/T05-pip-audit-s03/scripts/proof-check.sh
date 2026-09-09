#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

pass=0
fail=0

ok()  { printf 'PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL  %s\n' "$1"; fail=$((fail+1)); }

contains() {
  local file="$1" pattern="$2" label="$3"
  if [[ -f "$file" ]] && grep -Fq "$pattern" "$file"; then
    ok "$label"
  else
    bad "$label"
  fi
}

not_contains() {
  local file="$1" pattern="$2" label="$3"
  if [[ -f "$file" ]] && ! grep -Fq "$pattern" "$file"; then
    ok "$label"
  else
    bad "$label"
  fi
}

empty_file() {
  local file="$1" label="$2"
  if [[ -f "$file" ]] && [[ ! -s "$file" ]]; then
    ok "$label"
  else
    bad "$label"
  fi
}

echo "T05 pip-audit proof check"
echo "========================="

contains results/s03/baseline/requirements.txt \
  'reportkit==1.0.0' \
  'Direct requirement is reportkit 1.0.0'

contains results/s03/baseline/reportkit-metadata.txt \
  'Requires-Dist: tracehook-demo==1.0.0' \
  'reportkit metadata declares transitive tracehook-demo'

contains results/s03/baseline/tracehook-pyproject.toml \
  'build-backend = "tracehook_backend"' \
  'tracehook-demo declares custom PEP 517 backend'

empty_file results/s03/baseline/sdist-generated-files.txt \
  'Generated runtime files are absent from source distribution'

contains results/s03/baseline/build-hook.json \
  'pep517-build-backend-executed' \
  'Installed marker proves wheel backend executed during ordinary install'

contains results/s03/pip-audit/requirements-resolved.tsv \
  'reportkit' \
  'Normal requirements audit identifies reportkit'

contains results/s03/pip-audit/requirements-resolved.tsv \
  'tracehook-demo' \
  'Normal requirements audit identifies transitive tracehook-demo'

contains results/s03/pip-audit/requirements-resolved.tsv \
  'Dependency not found on PyPI and could not be audited' \
  'Private packages are identified but skipped by vulnerability service'

contains results/s03/pip-audit/pep517-audit-executed.txt \
  'tracehook_backend imported during pip-audit dependency resolution' \
  'pip-audit dependency collection executes PEP 517 backend code'

contains results/s03/pip-audit/requirements-no-deps.tsv \
  'tracehook-demo' \
  '--no-deps alone still includes tracehook-demo in observed run'

contains results/s03/pip-audit/requirements-no-deps-disable-pip.tsv \
  'reportkit' \
  '--no-deps --disable-pip retains direct reportkit'

not_contains results/s03/pip-audit/requirements-no-deps-disable-pip.tsv \
  'tracehook-demo' \
  '--no-deps --disable-pip excludes transitive tracehook-demo'

contains results/s03/pip-audit/installed.tsv \
  'pip' \
  'Installed-environment audit identifies pip'

contains results/s03/pip-audit/installed.tsv \
  'reportkit' \
  'Installed-environment audit identifies reportkit'

contains results/s03/pip-audit/installed.tsv \
  'tracehook-demo' \
  'Installed-environment audit identifies tracehook-demo'

contains results/s03/pip-audit/installed.json \
  'PYSEC-2026-3721' \
  'Installed-environment audit finds PYSEC-2026-3721'

contains results/s03/pip-audit/installed.json \
  'CVE-2026-13346' \
  'Installed-environment audit records CVE-2026-13346'

contains results/s03/pip-audit/installed.json \
  '"26.2"' \
  'pip vulnerability has fix version 26.2'

contains results/s03/pip-audit/installed-cdx-components.tsv \
  $'pip\t26.1.2' \
  'CycloneDX output contains pip 26.1.2'

not_contains results/s03/pip-audit/installed-cdx-components.tsv \
  'reportkit' \
  'Observed CycloneDX component view omits skipped reportkit'

not_contains results/s03/pip-audit/installed-cdx-components.tsv \
  'tracehook-demo' \
  'Observed CycloneDX component view omits skipped tracehook-demo'

echo
echo "Passed: $pass"
echo "Failed: $fail"

[[ "$fail" -eq 0 ]]
