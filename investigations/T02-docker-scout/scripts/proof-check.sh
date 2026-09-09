#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

pass=0
fail=0

ok() { printf 'PASS  %s\n' "$1"; pass=$((pass+1)); }
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

echo "T02 Docker Scout proof check"
echo "============================"

contains results/s01/scout/sbom-list.txt \
  'commons-codec' \
  'S01 Scout identifies commons-codec'
contains results/s01/scout/sbom-list.txt \
  'jackson-databind' \
  'S01 Scout identifies jackson-databind'
contains results/s01/scout/sbom-list.txt \
  'normalizer' \
  'S01 Scout identifies normalizer'
not_contains results/s01/scout/sbom-list.txt \
  'lodash' \
  'S01 Scout does not recover bundled lodash'
contains results/s01/scout/quickview.txt \
  'Provenance obtained from attestation' \
  'S01 Scout obtains provenance attestation'

if [[ -d results/s02/scout ]]; then
  contains results/s02/scout/sbom-list.txt \
    'commons-lang3' \
    'S02 Scout identifies commons-lang3'
fi

echo
echo "Passed: $pass"
echo "Failed: $fail"

[[ "$fail" -eq 0 ]]
