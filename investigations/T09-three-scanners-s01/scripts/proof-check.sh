#!/usr/bin/env bash
#
# T09 proof check: assert the structural claims the lesson makes, against
# whatever results/ currently holds. Counts and CVE IDs drift as databases
# update; these claims should not.
set -uo pipefail

source "$(dirname "$0")/common.sh"

RES="$ROOT/results/s01"
PASS=0; FAIL=0; SKIP=0

ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
no()   { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP  $1"; SKIP=$((SKIP+1)); }

have_tool() { [[ -d "$RES/$1" ]]; }

names() { # tool boundary component -> 0 if named
  # Match the artifact segment: grype writes "jackson-databind", trivy and
  # osv-scanner write "com.fasterxml.jackson.core:jackson-databind".
  local f="$RES/$1/$2.tracers.txt"
  [[ -s "$f" ]] || return 1
  awk -F'\t' -v t="$3" '
    { n = $1; sub(/^.*:/, "", n) }
    tolower(n) == tolower(t) { found = 1 }
    END { exit !found }' "$f"
}

echo "T09 proof check"
echo

# 1. The baseline exists and the differential pair was built.
[[ -f "$RES/baseline/physical-evidence.txt" ]] \
  && ok "baseline captured" || no "baseline captured (run baseline-s01.sh)"

# 2. At least two tools ran — without two, there is no comparison.
ran=0
for t in grype trivy osv; do have_tool "$t" && ran=$((ran+1)); done
[[ $ran -ge 2 ]] && ok "at least two scanners produced results ($ran)" \
                 || no "need results from at least two scanners (have $ran)"

# 3. The control: every tool that ran should name jackson-databind somewhere.
for t in grype trivy osv; do
  have_tool "$t" || { skip "$t: not run"; continue; }
  found=0
  for b in service-pom service-jar container-image; do
    names "$t" "$b" "jackson-databind" && found=1
  done
  [[ $found -eq 1 ]] && ok "$t names the control component (jackson-databind)" \
                     || no "$t never names jackson-databind — check the probe, not the finding"
done

# 4. The differential: stripping META-INF must not be invisible to every tool.
#    Whichever tools change their answer between these two JARs are the ones
#    reading metadata. At least one should.
changed=0
for t in grype trivy osv; do
  have_tool "$t" || continue
  a=$(names "$t" "normalizer-jar" "commons-codec" && echo 1 || echo 0)
  b=$(names "$t" "normalizer-stripped-jar" "commons-codec" && echo 1 || echo 0)
  if [[ "$a" != "$b" ]]; then
    changed=$((changed+1))
    ok "$t changed its answer when only META-INF was removed (intact=$a stripped=$b)"
  else
    ok "$t gave the same answer either way (intact=$a stripped=$b)"
  fi
done
[[ $ran -ge 2 ]] && { [[ $changed -ge 1 ]] \
  && ok "the metadata differential is visible to at least one tool" \
  || no "no tool changed its answer — the strip step probably did not run"; }

# 5. The bundle: lodash is code, not a package. A metadata scanner should miss
#    it. If a tool DOES name it, that is the interesting result, not a failure.
for t in grype trivy osv; do
  have_tool "$t" || continue
  if names "$t" "frontend-dist" "lodash"; then
    ok "$t named lodash in the built bundle — note how, it is the exception"
  else
    ok "$t did not name lodash in the built bundle (expected: no package boundary)"
  fi
done

# 6. The comparison artefact exists.
[[ -f "$RES/compare/matrix.txt" ]] \
  && ok "comparison matrix written" || no "comparison matrix missing (run compare-s01.sh)"

echo
echo "Passed: $PASS  Failed: $FAIL  Skipped: $SKIP"
[[ $FAIL -eq 0 ]]
