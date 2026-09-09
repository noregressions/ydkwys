#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")/.."

LOCAL_REPO="$PWD/.maven-repo"
JAR="target/maven-plugin-hidden-content-1.0.0.jar"
PROOF_PORT="${PROOF_PORT:-18084}"

PASS=0
FAIL=0
WARN=0

pass() {
  PASS=$((PASS + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

warn() {
  WARN=$((WARN + 1))
  printf 'WARN: %s\n' "$1"
}

need() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "required command available: $1"
  else
    fail "required command missing: $1"
  fi
}

cleanup_runtime() {
  ./scripts/stop.sh >/dev/null 2>&1 || true
}
trap cleanup_runtime EXIT

echo "S04 proof check"
echo "==============="
echo

for cmd in mvn java curl grep unzip javap; do
  need "$cmd"
done

if (( FAIL > 0 )); then
  echo
  echo "Cannot continue without required tools."
  exit 1
fi

# Do not let an earlier workshop run occupy the scenario PID file.
cleanup_runtime

# Start from generated-output clean state but keep the local Maven repository.
./scripts/clean.sh >/dev/null 2>&1 || true
mkdir -p trace-output

if ! grep -R -q '/hidden/build-info' src/main/java pom.xml; then
  pass "hidden route is absent from checked-in application Java source and application POM"
else
  fail "hidden route unexpectedly exists in application Java source or application POM"
fi

if ! grep -q '<dependencies>' pom.xml; then
  pass "application POM declares no ordinary project dependencies"
else
  fail "application POM unexpectedly declares project dependencies"
fi

if grep -q 'trace-injector-maven-plugin' pom.xml \
   && grep -q '<phase>generate-sources</phase>' pom.xml \
   && grep -q '<goal>inject-route</goal>' pom.xml; then
  pass "application attaches trace-injector-maven-plugin to generate-sources"
else
  fail "custom plugin lifecycle declaration is missing"
fi

if grep -q '<artifactId>trace-route-payload</artifactId>' tooling/plugin/pom.xml; then
  pass "trace-route-payload is declared as a dependency of the Maven plugin"
else
  fail "plugin no longer declares trace-route-payload"
fi

if grep -q '^path=/hidden/build-info$' tooling/payload/src/main/resources/trace-route.properties \
   && grep -q '^origin=trace-route-payload$' tooling/payload/src/main/resources/trace-route.properties; then
  pass "plugin payload carries the hidden route definition"
else
  fail "plugin payload route definition changed"
fi

echo
echo "Building fixtures and application..."

if ./scripts/build.sh >trace-output/proof-build.log 2>&1; then
  pass "tooling and application build successfully"
else
  fail "build failed; see trace-output/proof-build.log"
fi

if [[ -f "$JAR" ]]; then
  pass "application JAR exists"
else
  fail "application JAR missing"
fi

echo
echo "Checking Maven evidence views..."

TREE_LOG="trace-output/proof-dependency-tree.log"
if mvn -Dmaven.repo.local="$LOCAL_REPO" dependency:tree >"$TREE_LOG" 2>&1; then
  pass "Maven project dependency tree resolves"
else
  fail "Maven project dependency tree failed"
fi

if ! grep -q 'trace-injector-maven-plugin' "$TREE_LOG" \
   && ! grep -q 'trace-route-payload' "$TREE_LOG"; then
  pass "project dependency tree omits the plugin and plugin payload"
else
  fail "plugin or payload unexpectedly appears in project dependency tree"
fi

PLUGIN_LOG="trace-output/proof-resolve-plugins.log"
if mvn \
     -Dmaven.repo.local="$LOCAL_REPO" \
     dependency:resolve-plugins \
     -DincludeArtifactIds=trace-injector-maven-plugin \
     >"$PLUGIN_LOG" 2>&1; then
  pass "Maven plugin dependency view resolves"
else
  fail "Maven plugin dependency resolution failed"
fi

if grep -q 'trace-injector-maven-plugin:jar:1.0.0' "$PLUGIN_LOG" \
   && grep -q 'trace-route-payload:jar:1.0.0' "$PLUGIN_LOG"; then
  pass "plugin dependency view contains plugin and transitive payload"
else
  fail "plugin dependency view does not contain both expected artifacts"
fi

REALM_LOG="trace-output/proof-plugin-realm.log"
if mvn \
     -Dmaven.repo.local="$LOCAL_REPO" \
     -X generate-sources \
     >"$REALM_LOG" 2>&1; then
  pass "generate-sources executes under Maven debug tracing"
else
  fail "generate-sources debug run failed"
fi

if grep -q 'Created new class realm plugin>dev.noregressions.trace:trace-injector-maven-plugin:1.0.0' "$REALM_LOG" \
   && grep -q 'Included: dev.noregressions.trace:trace-injector-maven-plugin:jar:1.0.0' "$REALM_LOG" \
   && grep -q 'Included: dev.noregressions.trace:trace-route-payload:jar:1.0.0' "$REALM_LOG"; then
  pass "actual Maven plugin ClassRealm contains plugin and payload"
else
  fail "expected plugin ClassRealm evidence is missing"
fi

echo
echo "Checking generated and packaged evidence..."

GEN_SOURCE="target/generated-sources/trace-injector/dev/noregressions/trace/s04/generated/GeneratedTraceRoute.java"
SERVICE_FILE="target/generated-resources/trace-injector/META-INF/services/dev.noregressions.trace.s04.TraceRoute"
META_FILE="target/generated-resources/trace-injector/META-INF/trace-lab/plugin-injection.properties"

if [[ -f "$GEN_SOURCE" ]] \
   && grep -q 'return "/hidden/build-info";' "$GEN_SOURCE" \
   && grep -q 'trace-route-payload' "$GEN_SOURCE" \
   && grep -q 'trace-injector-maven-plugin' "$GEN_SOURCE"; then
  pass "plugin generated Java source containing route and provenance"
else
  fail "generated route source is missing or changed"
fi

if [[ -f "$SERVICE_FILE" ]] \
   && [[ "$(tr -d '\r\n' <"$SERVICE_FILE")" == "dev.noregressions.trace.s04.generated.GeneratedTraceRoute" ]]; then
  pass "generated ServiceLoader descriptor activates GeneratedTraceRoute"
else
  fail "ServiceLoader descriptor is missing or incorrect"
fi

if [[ -f "$META_FILE" ]] \
   && grep -q '^plugin=trace-injector-maven-plugin$' "$META_FILE" \
   && grep -q '^payload=trace-route-payload$' "$META_FILE" \
   && grep -q '^route=/hidden/build-info$' "$META_FILE"; then
  pass "generated provenance metadata identifies plugin, payload and route"
else
  fail "generated provenance metadata is missing or incorrect"
fi

if unzip -l "$JAR" >trace-output/proof-jar-entries.log 2>&1 \
   && grep -q 'dev/noregressions/trace/s04/generated/GeneratedTraceRoute.class' trace-output/proof-jar-entries.log \
   && grep -q 'META-INF/services/dev.noregressions.trace.s04.TraceRoute' trace-output/proof-jar-entries.log \
   && grep -q 'META-INF/trace-lab/plugin-injection.properties' trace-output/proof-jar-entries.log; then
  pass "generated class and resources are packaged in final JAR"
else
  fail "expected generated content is missing from final JAR"
fi

if javap \
     -classpath "$JAR" \
     -c -p \
     dev.noregressions.trace.s04.generated.GeneratedTraceRoute \
     >trace-output/proof-javap.log 2>&1 \
   && grep -q '/hidden/build-info' trace-output/proof-javap.log \
   && grep -q 'trace-route-payload' trace-output/proof-javap.log \
   && grep -q 'trace-injector-maven-plugin' trace-output/proof-javap.log; then
  pass "compiled bytecode retains hidden route and provenance strings"
else
  fail "compiled bytecode no longer proves expected behaviour"
fi

echo
echo "Checking inventory/SBOM evidence..."

if command -v syft >/dev/null 2>&1; then
  if syft "$JAR" >trace-output/proof-syft.log 2>&1; then
    pass "Syft scan completes"
  else
    fail "Syft scan failed"
  fi

  if grep -q 'maven-plugin-hidden-content' trace-output/proof-syft.log \
     && ! grep -q 'trace-route-payload' trace-output/proof-syft.log \
     && ! grep -q 'trace-injector-maven-plugin' trace-output/proof-syft.log; then
    pass "Syft identifies application archive but not plugin/payload provenance"
  else
    fail "Syft result no longer matches the demonstrated evidence boundary"
  fi
else
  warn "Syft not installed; scanner-specific proof skipped"
fi

BOM_LOG="trace-output/proof-cyclonedx.log"
if mvn \
     -Dmaven.repo.local="$LOCAL_REPO" \
     org.cyclonedx:cyclonedx-maven-plugin:2.9.3:makeBom \
     -DoutputFormat=json \
     >"$BOM_LOG" 2>&1; then
  pass "CycloneDX Maven SBOM generation completes"
else
  fail "CycloneDX Maven SBOM generation failed"
fi

if [[ -f target/bom.json ]] \
   && ! grep -q 'trace-injector-maven-plugin' target/bom.json \
   && ! grep -q 'trace-route-payload' target/bom.json; then
  pass "Maven-model SBOM omits plugin and transitive plugin payload"
else
  fail "Maven-model SBOM now contains plugin or payload"
fi

if command -v jq >/dev/null 2>&1; then
  components="$(jq '.components // [] | length' target/bom.json 2>/dev/null || echo ERROR)"
  if [[ "$components" == "0" ]]; then
    pass "Maven-model SBOM contains zero dependency components"
  else
    fail "Maven-model SBOM component count is no longer zero"
  fi
else
  warn "jq not installed; exact CycloneDX component-count assertion skipped"
fi

echo
echo "Checking runtime behaviour..."

if curl -fsS --max-time 1 "http://127.0.0.1:${PROOF_PORT}/" >/dev/null 2>&1; then
  fail "proof port ${PROOF_PORT} is already in use"
else
  if PORT="$PROOF_PORT" ./scripts/run.sh >trace-output/proof-runtime-start.log 2>&1; then
    pass "application starts on isolated proof port ${PROOF_PORT}"
  else
    fail "application failed to start on proof port; see trace-output/proof-runtime-start.log"
  fi

  HEALTH="$(curl -fsS --max-time 3 "http://127.0.0.1:${PROOF_PORT}/health" 2>/dev/null || true)"
  if [[ "$HEALTH" == *'"application": "maven-plugin-hidden-content"'* ]] \
     && [[ "$HEALTH" == *'"status": "UP"'* ]]; then
    pass "source-defined health endpoint responds"
  else
    fail "health endpoint response is incorrect"
  fi

  HIDDEN="$(curl -fsS --max-time 3 "http://127.0.0.1:${PROOF_PORT}/hidden/build-info" 2>/dev/null || true)"
  if [[ "$HIDDEN" == *'"origin": "trace-route-payload"'* ]] \
     && [[ "$HIDDEN" == *'"introducedBy": "trace-injector-maven-plugin"'* ]] \
     && [[ "$HIDDEN" == *'"route": "/hidden/build-info"'* ]]; then
    pass "build-supplied runtime endpoint ties behaviour to plugin and payload"
  else
    fail "hidden runtime endpoint response is incorrect"
  fi

  cleanup_runtime
fi

echo
echo "S04 proof result: ${PASS} passed, ${FAIL} failed, ${WARN} warnings"

if (( FAIL > 0 )); then
  echo "RESULT: FAIL — one or more demonstrated outcomes are no longer true."
  exit 1
fi

echo "RESULT: PASS — the demonstrated S04 outcomes are still true."
