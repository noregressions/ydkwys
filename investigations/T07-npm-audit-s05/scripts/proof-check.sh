#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/common.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1" >&2; }

contains() {
  local file="$1" pattern="$2" label="$3"
  if [[ -f "$file" ]] && grep -Fq "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

not_contains() {
  local file="$1" pattern="$2" label="$3"
  if [[ -f "$file" ]] && ! grep -Fq "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

equals() {
  local file="$1" expected="$2" label="$3"
  if [[ -f "$file" ]] && [[ "$(tr -d '\r\n' < "$file")" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label"
  fi
}

result_contains() {
  contains "$AUDIT/$1/result.txt" "$2" "$3"
}

echo "T07 npm audit proof check"
echo "========================"

contains "$BASE/build.log" 'trace-route-package@1.0.0 prepack' \
  'npm prepack executed'
contains "$BASE/build.log" 'node scripts/generate-dist.js' \
  'generator executed during prepack'
contains "$BASE/tarball-files.txt" 'package/dist/index.js' \
  'published tarball contains generated runtime'
contains "$BASE/tarball-files.txt" 'package/dist/prepack-evidence.json' \
  'published tarball contains generated evidence'
not_contains "$BASE/tarball-files.txt" 'generate-dist.js' \
  'published tarball excludes generator implementation'
not_contains "$BASE/tarball-files.txt" 'build-input/route.json' \
  'published tarball excludes original build input'
contains "$BASE/unpacked-package/package.json" '"prepack": "node scripts/generate-dist.js"' \
  'published package.json retains prepack declaration'
contains "$BASE/installed-prepack-evidence.json" '"event": "npm-prepack-generated"' \
  'installed package retains generated provenance event'
contains "$BASE/installed-prepack-evidence.json" '"route": "/hidden/prepack-info"' \
  'installed package retains generated runtime route'

equals "$AUDIT/application/exit.txt" '0' \
  'application audit exits successfully'
result_contains application 'vulnerabilityRecords=0' \
  'application audit has zero vulnerability records'
result_contains application 'dependencyTotal=1' \
  'application audit sees one dependency'

equals "$AUDIT/application-lock-only/exit.txt" '0' \
  'package-lock-only application audit exits successfully'
result_contains application-lock-only 'vulnerabilityRecords=0' \
  'package-lock-only audit has zero vulnerability records'
result_contains application-lock-only 'dependencyTotal=1' \
  'package-lock-only audit sees one dependency'

equals "$AUDIT/source-package/exit.txt" '1' \
  'source package normal audit fails without lockfile'
contains "$AUDIT/source-package/audit.stderr" 'ENOLOCK' \
  'source package failure is ENOLOCK'

equals "$AUDIT/source-package-no-lock/exit.txt" '0' \
  'source package --no-package-lock audit succeeds'
result_contains source-package-no-lock 'dependencyTotal=0' \
  'source package metadata rebuild has zero dependencies'
result_contains source-package-no-lock 'vulnerabilityRecords=0' \
  'source package metadata rebuild has zero vulnerabilities'

equals "$AUDIT/published-package/exit.txt" '1' \
  'published package normal audit fails without lockfile'
contains "$AUDIT/published-package/audit.stderr" 'ENOLOCK' \
  'published package failure is ENOLOCK'

equals "$AUDIT/published-package-no-lock/exit.txt" '0' \
  'published package --no-package-lock audit succeeds'
result_contains published-package-no-lock 'dependencyTotal=0' \
  'published package metadata rebuild has zero dependencies'
result_contains published-package-no-lock 'vulnerabilityRecords=0' \
  'published package metadata rebuild has zero vulnerabilities'

equals "$AUDIT/public-vulnerable-control/exit.txt" '1' \
  'known-vulnerable lodash control exits non-zero'
result_contains public-vulnerable-control 'vulnerabilityRecords=1' \
  'lodash control returns one vulnerability record'
result_contains public-vulnerable-control 'dependencyTotal=1' \
  'lodash control sees one dependency'
result_contains public-vulnerable-control $'lodash\thigh\tdirect' \
  'lodash control returns high direct vulnerability'

for term in \
  'scripts/generate-dist.js' \
  'npm-prepack-generated' \
  'prepack-evidence.json' \
  '/hidden/prepack-info'
do
  if grep -R -F -q "$term" "$AUDIT" \
       --include='audit.json' --include='audit.stderr'; then
    fail "npm audit output omits provenance string: $term"
  else
    pass "npm audit output omits provenance string: $term"
  fi
done

echo
echo "Passed: $PASS"
echo "Failed: $FAIL"

(( FAIL == 0 ))
