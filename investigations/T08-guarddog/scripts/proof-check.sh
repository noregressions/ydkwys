#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/common.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1" >&2; }

contains()     { [[ -f "$1" ]] && grep -Fq "$2" "$1" && pass "$3" || fail "$3"; }
not_contains() { [[ -f "$1" ]] && ! grep -Fq "$2" "$1" && pass "$3" || fail "$3"; }

S05_SCAN="$RESULTS/s05/scan.txt"
S05_FILES="$RESULTS/s05/tarball-files.txt"
S03_SCAN="$RESULTS/s03/scan.txt"
CTL_SCAN="$RESULTS/control/scan.txt"

echo "T08 GuardDog proof check"
echo "========================"

# S05: clean because the generator was never in the shipped tarball.
contains     "$S05_SCAN"  "No risks detected"     "S05 published tarball scans clean"
contains     "$S05_FILES" "package/dist/index.js" "S05 tarball ships the generated runtime"
not_contains "$S05_FILES" "generate-dist.js"      "S05 tarball excludes the generator itself"

# S03: clean because the backend IS present and GuardDog read it — benign.
contains "$S03_SCAN" "No risks detected"    "S03 sdist scans clean"
contains "$RESULTS/s03/sdist-files.txt" "tracehook_backend.py" \
  "S03 sdist DOES carry the executable build backend"

# Positive control: proves the scanner fires on a detectable pattern.
contains "$CTL_SCAN" "High risk"      "positive control is flagged High risk"
not_contains "$CTL_SCAN" "No risks detected" "positive control is not a clean result"

# Malicious S05 variant: the catch-vs-miss contrast (run scan-malicious.sh first).
MAL="$RESULTS/malicious"
if [[ -d "$MAL" ]]; then
  contains     "$MAL/A-tarball.txt" "No risks detected" \
    "case A published tarball is clean (generator payload not shipped)"
  contains     "$MAL/A-source.txt"  "High risk" \
    "case A source is caught (generator present)"
  contains     "$MAL/B-tarball.txt" "High risk" \
    "case B published tarball is caught (payload rode into shipped dist)"
else
  echo "SKIP  malicious variant (run ./scripts/scan-malicious.sh to include)"
fi

echo
echo "Passed: $PASS"
echo "Failed: $FAIL"
(( FAIL == 0 ))
