#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# Adds provenance to S01's build in four layers, re-auditing after each so you
# can see exactly what each one makes recoverable. Run build-baseline.sh first.

[[ -d "$SRC" ]] || { echo "Run ./scripts/build-baseline.sh first." >&2; exit 1; }
need syft; need cosign; need curl
cd "$SRC"
COMMIT="$(git rev-parse HEAD)"
SOURCE="$(git remote get-url origin)"

echo "############ Layer 1 — git commit inside the JAR ############"
# Inject the git-commit-id plugin snippet just before the spring-boot plugin.
python3 - "$ROOT/provenance/git-plugin-snippet.xml" <<'PY'
import sys, re
snippet = open(sys.argv[1]).read()
snippet = re.sub(r"<!--.*?-->", "", snippet, flags=re.DOTALL).strip()   # drop XML comment
p = "service/pom.xml"; s = open(p).read()
anchor = "      <plugin>\n        <groupId>org.springframework.boot</groupId>"
if "git-commit-id" not in s:
    indented = "\n".join(("      " + l) if l else l for l in snippet.splitlines())
    s = s.replace(anchor, indented + "\n\n" + anchor, 1)
    open(p, "w").write(s)
print("  git-commit-id plugin added to service/pom.xml")
PY
mvn -q -pl service -am clean package -DskipTests
echo "  Recovered from the JAR:"
unzip -p service/target/service-1.0.0.jar BOOT-INF/classes/git.properties | sed 's/^/    /'

echo
echo "############ Layer 2 — OCI labels on the image ############"
ensure_registry
BUILD_TIME="$(TZ=UTC date +%Y-%m-%dT%H:%M:%SZ)"
docker build -q \
  --build-arg GIT_COMMIT="$COMMIT" \
  --build-arg GIT_SOURCE="$SOURCE" \
  --build-arg BUILD_TIME="$BUILD_TIME" \
  --build-arg VERSION="1.0.0" \
  -f "$ROOT/provenance/Dockerfile.provenance" -t "$IMG:prov" . >/dev/null
echo "  Recovered from the image config:"
docker image inspect "$IMG:prov" --format '{{json .Config.Labels}}' \
  | python3 -m json.tool | sed 's/^/    /'

echo
echo "############ Layer 3 — an SBOM, keyed to the image digest ############"
docker push "$IMG:prov" >/dev/null
DIGEST="$(docker image inspect "$IMG:prov" --format '{{index .RepoDigests 0}}')"
echo "  Image digest: $DIGEST"
echo "$DIGEST" > "$RESULTS/image-digest.txt"
syft "$DIGEST" -o cyclonedx-json="$RESULTS/checkout-service.cdx.json" -q
echo "  SBOM components: $(python3 -c 'import json;print(len(json.load(open("'"$RESULTS"'/checkout-service.cdx.json"))["components"]))')"

echo
echo "############ Layer 4 — a signed attestation binding it all to the digest ############"
export COSIGN_PASSWORD=""
[[ -f "$RESULTS/cosign.key" ]] || cosign generate-key-pair --output-key-prefix "$RESULTS/cosign" >/dev/null
cosign sign   --yes --key "$RESULTS/cosign.key" "$DIGEST" >/dev/null
cosign attest --yes --key "$RESULTS/cosign.key" --type cyclonedx \
  --predicate "$RESULTS/checkout-service.cdx.json" "$DIGEST" >/dev/null
echo "  Signed and attested. Now verify with the PUBLIC key only:"
cosign verify             --key "$RESULTS/cosign.pub" "$DIGEST" >/dev/null 2>&1 \
  && echo "    signature:   VERIFIED"
cosign verify-attestation --key "$RESULTS/cosign.pub" --type cyclonedx "$DIGEST" >/dev/null 2>&1 \
  && echo "    attestation: VERIFIED (the SBOM travels bound to the digest)"

echo
echo "Reverse audit now answers every question the baseline could not:"
echo "  commit  -> git.properties + OCI revision label"
echo "  repo    -> OCI source label"
echo "  inventory -> attested SBOM, recoverable from the image by digest"
echo "  identity  -> content digest, cryptographically signed"
