#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/common.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1" >&2; }

JAR="$SRC/service/target/service-1.0.0.jar"
DIGEST="$(cat "$RESULTS/image-digest.txt" 2>/dev/null || true)"

echo "S07 provenance proof check"
echo "=========================="

# Baseline gap: the shipped Dockerfile carries none of our OCI labels.
if docker image inspect "$IMG:baseline" >/dev/null 2>&1; then
  if docker image inspect "$IMG:baseline" --format '{{json .Config.Labels}}' \
       | grep -q 'opencontainers.image.revision'; then
    fail "baseline image has NO revision label"
  else
    pass "baseline image has NO revision label"
  fi
fi

# Layer 1: git.properties inside the JAR.
if unzip -p "$JAR" BOOT-INF/classes/git.properties 2>/dev/null | grep -q 'git.commit.id'; then
  pass "JAR carries git.properties with a commit id"
else
  fail "JAR carries git.properties with a commit id"
fi

# Layer 2: OCI labels on the provenance image.
LBL="$(docker image inspect "$IMG:prov" --format '{{json .Config.Labels}}' 2>/dev/null)"
echo "$LBL" | grep -q 'opencontainers.image.revision' && pass "prov image has a revision label" || fail "prov image has a revision label"
echo "$LBL" | grep -q 'opencontainers.image.source'   && pass "prov image has a source label"   || fail "prov image has a source label"

# Layer 3: an SBOM exists and names our tracked components.
if [[ -f "$RESULTS/checkout-service.cdx.json" ]] \
   && grep -q 'jackson-databind' "$RESULTS/checkout-service.cdx.json"; then
  pass "SBOM lists the jackson-databind tracked component"
else
  fail "SBOM lists the jackson-databind tracked component"
fi

# Layer 4: signature and attestation verify with the public key alone.
if [[ -n "$DIGEST" && -f "$RESULTS/cosign.pub" ]]; then
  cosign verify --key "$RESULTS/cosign.pub" "$DIGEST" >/dev/null 2>&1 \
    && pass "image signature verifies" || fail "image signature verifies"
  cosign verify-attestation --key "$RESULTS/cosign.pub" --type cyclonedx "$DIGEST" >/dev/null 2>&1 \
    && pass "SBOM attestation verifies" || fail "SBOM attestation verifies"
else
  fail "signature/attestation present to verify"
fi

echo
echo "Passed: $PASS"
echo "Failed: $FAIL"
(( FAIL == 0 ))
