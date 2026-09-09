#!/usr/bin/env bash
#
# T09 baseline: put S01 into the exact state all three scanners are pointed
# at, and record the ground truth independently of any of them.
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in mvn npm jar docker jq; do
  require_command "$cmd"
done

S01="$(resolve_s01)" || {
  echo "Could not find S01-spring-node. Set S01_DIR=/path/to/S01-spring-node" >&2
  exit 1
}

OUT="$ROOT/results/s01/baseline"
mkdir -p "$OUT"

IMAGE="${S01_IMAGE:-registry.example.com/checkout-service:release-123}"

echo "S01:    $S01"
echo "Image:  $IMAGE"
echo "Output: $OUT"

echo
echo "== Build S01 from clean state =="
( cd "$S01" && ./scripts/build.sh ) | tee "$OUT/build.txt"

echo
echo "== Install the reactor into the local repo =="
# S01's build.sh runs `mvn package`, which leaves normalizer 1.0.0 absent from
# the local repository. Anything that resolves service's dependencies from the
# POM alone — osv-scanner's transitive enricher, mvn dependency:list — then
# fails on the missing sibling. Installing once makes the source-boundary
# probes resolvable for every tool.
( cd "$S01" && mvn -q -B install -DskipTests ) | tee "$OUT/mvn-install.txt"

echo
echo "== Create the controlled metadata-stripped normalizer =="
# Same bytecode, no META-INF/maven/commons-codec. This is the differential
# that separates "reads metadata" from "reads code".
( cd "$S01" && ./scripts/strip-codec-metadata.sh ) | tee "$OUT/strip-codec-metadata.txt"

echo
echo "== Ground truth: Maven =="
( cd "$S01" && mvn -pl service -am dependency:tree -Dverbose \
    -Dincludes=commons-codec:commons-codec,com.fasterxml.jackson.core:jackson-databind,dev.noregressions.trace:normalizer \
) | tee "$OUT/maven-service.txt"

echo
echo "== Ground truth: npm =="
( cd "$S01/frontend" && npm ls lodash --all ) | tee "$OUT/npm-lodash.txt"

echo
echo "== Ground truth: what is physically in the archives =="
{
  echo "--- normalizer (shaded, metadata intact)"
  jar tf "$S01/normalizer/target/normalizer-1.0.0.jar" \
    | grep -E '^com/acme/internal/codec/|META-INF/maven/commons-codec/' | head -20 || true
  echo
  echo "--- normalizer (shaded, metadata stripped)"
  jar tf "$S01/trace-output/normalizer-no-codec-metadata.jar" \
    | grep -E '^com/acme/internal/codec/|META-INF/maven/commons-codec/' | head -20 || true
  echo
  echo "--- service fat JAR"
  jar tf "$S01/service/target/service-1.0.0.jar" \
    | grep -E 'BOOT-INF/lib/(jackson-databind|commons-codec|normalizer)' || true
  echo
  echo "--- frontend bundle: lodash present as code, not as a package"
  grep -oE "__lodash_hash_undefined__|4\.17\.21" "$S01"/frontend/dist/assets/*.js \
    | sort | uniq -c || true
} | tee "$OUT/physical-evidence.txt"

echo
echo "== Build the container image =="
( cd "$S01" && docker build -t "$IMAGE" . ) | tee "$OUT/docker-build.txt"
printf '%s\n' "$IMAGE" >"$OUT/image-name.txt"

echo
echo "== Record the instruments =="
{
  echo "captured: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo -n "grype:        "; (grype version 2>/dev/null | head -3 | tr '\n' ' ') || echo "NOT INSTALLED"
  echo
  echo -n "trivy:        "; (trivy --version 2>/dev/null | head -1) || echo "NOT INSTALLED"
  echo -n "osv-scanner:  "; (osv-scanner --version 2>/dev/null | head -1) || echo "NOT INSTALLED"
  echo -n "osv cli form: "; (osv_mode 2>/dev/null) || echo "unknown"
} | tee "$OUT/instruments.txt"

echo
echo "T09 baseline captured. Next: ./scripts/run-scanners-s01.sh"
