#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

EXPECTED_APP="1.0.0"
EXPECTED_COMMONS="3.18.0"
EXPECTED_JAKARTA="11.0.0"
EXPECTED_LODASH="4.17.21"
EXPECTED_PAYARA="7.2026.7"

WAR="target/payara-mvnpm-trace-lab-${EXPECTED_APP}.war"

SKIP_BUILD=0
SKIP_RUNTIME=0
SKIP_IMAGE=0

usage() {
  cat <<'EOF'
Usage: ./scripts/proof-check.sh [options]

Proves that the S02 Payara + mvnpm demo still produces the outcomes
described in LESSON.md.

Options:
  --skip-build     Check existing Maven/build output instead of rebuilding.
  --skip-runtime   Do not start Payara and call the runtime endpoint.
  --skip-image     Do not generate/check the container-image inventory.
  --quick          Equivalent to --skip-runtime --skip-image.
  -h, --help       Show this help.

Environment:
  PROOF_PORT=18081       Host port used for the Payara runtime check.
  KEEP_PROOF_IMAGE=1     Keep the temporary proof Docker image.
EOF
}

while (($#)); do
  case "$1" in
    --skip-build)   SKIP_BUILD=1 ;;
    --skip-runtime) SKIP_RUNTIME=1 ;;
    --skip-image)   SKIP_IMAGE=1 ;;
    --quick)        SKIP_RUNTIME=1; SKIP_IMAGE=1 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

PASS=0
FAIL=0
WARN=0

PROOF_PORT="${PROOF_PORT:-18081}"
IMAGE_TAG="kcdc-s02-proof:local-$$"
CONTAINER_NAME="kcdc-s02-proof-$$"
IMAGE_BUILT=0
CONTAINER_STARTED=0

TMP=$(mktemp -d "${TMPDIR:-/tmp}/s02-proof.XXXXXX")

pass() {
  PASS=$((PASS + 1))
  printf '  PASS  %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL  %s\n' "$1" >&2
}

warn() {
  WARN=$((WARN + 1))
  printf '  WARN  %s\n' "$1" >&2
}

phase() {
  printf '\n==> %s\n' "$1"
}

summary() {
  printf '\n========================================\n'
  printf 'S02 proof result: %d passed, %d failed, %d warnings\n' "$PASS" "$FAIL" "$WARN"

  if [[ "$FAIL" -eq 0 ]]; then
    printf 'RESULT: PASS — the demo outcomes are still true.\n'
    return 0
  fi

  printf 'RESULT: FAIL — do not rely on this demo until the failed proof(s) are resolved.\n' >&2
  return 1
}

cleanup() {
  if [[ "$CONTAINER_STARTED" -eq 1 ]]; then
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi

  if [[ "$IMAGE_BUILT" -eq 1 && "${KEEP_PROOF_IMAGE:-0}" != "1" ]]; then
    docker image rm -f "$IMAGE_TAG" >/dev/null 2>&1 || true
  fi

  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

require() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "required command available: $cmd"
  else
    fail "required command missing: $cmd"
  fi
}

assert_grep() {
  local description="$1"
  local pattern="$2"
  local file="$3"

  if grep -Eq "$pattern" "$file"; then
    pass "$description"
  else
    fail "$description"
  fi
}

assert_not_grep() {
  local description="$1"
  local pattern="$2"
  local file="$3"

  if grep -Eq "$pattern" "$file"; then
    fail "$description"
  else
    pass "$description"
  fi
}

assert_json() {
  local description="$1"
  local file="$2"
  local expression="$3"

  if jq -e "$expression" "$file" >/dev/null 2>&1; then
    pass "$description"
  else
    fail "$description"
  fi
}

# ---------------------------------------------------------------------------

phase "Preflight"

for cmd in java mvn unzip jq syft curl grep find; do
  require "$cmd"
done

if [[ "$SKIP_RUNTIME" -eq 0 || "$SKIP_IMAGE" -eq 0 ]]; then
  require docker
fi

if [[ "$FAIL" -ne 0 ]]; then
  summary
  exit 1
fi

# ---------------------------------------------------------------------------

phase "Source invariants"

assert_grep \
  "POM pins commons-lang3 $EXPECTED_COMMONS" \
  "<commons-lang3\.version>${EXPECTED_COMMONS}</commons-lang3\.version>" \
  pom.xml

assert_grep \
  "POM pins Jakarta EE Web API $EXPECTED_JAKARTA" \
  "<jakartaee\.version>${EXPECTED_JAKARTA}</jakartaee\.version>" \
  pom.xml

assert_grep \
  "Jakarta EE dependency remains Maven provided scope" \
  '<scope>provided</scope>' \
  pom.xml

assert_grep \
  "POM pins lodash-es $EXPECTED_LODASH" \
  "<lodash-es\.version>${EXPECTED_LODASH}</lodash-es\.version>" \
  pom.xml

assert_grep \
  "esbuild Maven plugin remains configured" \
  '<artifactId>esbuild-maven-plugin</artifactId>' \
  pom.xml

assert_grep \
  "lodash-es remains declared as a Maven plugin dependency" \
  '<artifactId>lodash-es</artifactId>' \
  pom.xml

assert_grep \
  "browser source actually imports lodash-es" \
  'from[[:space:]]+"lodash-es"' \
  src/main/web/app.js

assert_grep \
  "servlet actually uses commons-lang3" \
  'org\.apache\.commons\.lang3\.StringUtils' \
  src/main/java/dev/noregressions/trace/payara/InfoServlet.java

assert_grep \
  "servlet actually uses Jakarta JSON-P" \
  'jakarta\.json\.Json' \
  src/main/java/dev/noregressions/trace/payara/InfoServlet.java

# ---------------------------------------------------------------------------

phase "Clean build"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  rm -rf trace-output

  if ./scripts/build.sh >"$TMP/build.log" 2>&1; then
    pass "clean Maven build completes"
  else
    fail "clean Maven build completes"
    printf '\n--- build.log ---\n' >&2
    cat "$TMP/build.log" >&2 || true
    summary
    exit 1
  fi
else
  warn "build skipped; checking existing outputs"
fi

[[ -f "$WAR" ]] \
  && pass "deployable WAR exists" \
  || fail "deployable WAR exists"

[[ -f target/generated-web/assets/app.js ]] \
  && pass "generated app.js exists" \
  || fail "generated app.js exists"

[[ -f target/generated-web/assets/app.js.map ]] \
  && pass "generated app.js.map exists" \
  || fail "generated app.js.map exists"

if [[ "$FAIL" -ne 0 ]]; then
  summary
  exit 1
fi

# ---------------------------------------------------------------------------

phase "Maven dependency domains"

if mvn dependency:tree \
     -Dincludes=org.apache.commons:commons-lang3 \
     >"$TMP/commons-tree.log" 2>&1; then
  pass "Maven resolves ordinary project dependency tree"
else
  fail "Maven resolves ordinary project dependency tree"
fi

assert_grep \
  "commons-lang3 $EXPECTED_COMMONS is in the project dependency graph" \
  "org\.apache\.commons:commons-lang3:jar:${EXPECTED_COMMONS}:compile" \
  "$TMP/commons-tree.log"

if mvn dependency:tree \
     -Dincludes=org.mvnpm:lodash-es \
     >"$TMP/lodash-tree.log" 2>&1; then
  pass "Maven resolves project tree when filtered for lodash-es"
else
  fail "Maven resolves project tree when filtered for lodash-es"
fi

assert_not_grep \
  "lodash-es is absent from the normal project dependency graph" \
  'org\.mvnpm:lodash-es:jar:' \
  "$TMP/lodash-tree.log"

if mvn dependency:resolve-plugins \
     -DincludeArtifactIds=esbuild-maven-plugin \
     >"$TMP/resolve-plugins.log" 2>&1; then
  pass "Maven resolve-plugins report succeeds"
else
  fail "Maven resolve-plugins report succeeds"
fi

assert_grep \
  "resolve-plugins sees esbuild-maven-plugin" \
  "io\.mvnpm:esbuild-maven-plugin:maven-plugin:2\.0\.0:runtime" \
  "$TMP/resolve-plugins.log"

assert_not_grep \
  "project-added lodash-es is absent from resolve-plugins report" \
  'org\.mvnpm:lodash-es:jar:' \
  "$TMP/resolve-plugins.log"

if mvn -X generate-resources >"$TMP/plugin-realm.log" 2>&1; then
  pass "Maven debug plugin execution succeeds"
else
  fail "Maven debug plugin execution succeeds"
fi

assert_grep \
  "lodash-es $EXPECTED_LODASH is resolved into the actual plugin realm" \
  "org\.mvnpm:lodash-es:jar:${EXPECTED_LODASH}:runtime" \
  "$TMP/plugin-realm.log"

assert_grep \
  "Maven explicitly includes lodash-es $EXPECTED_LODASH in the plugin realm" \
  "Included: org\.mvnpm:lodash-es:jar:${EXPECTED_LODASH}" \
  "$TMP/plugin-realm.log"

# ---------------------------------------------------------------------------

phase "lodash-es contributes code but loses package identity"

SOURCE_MAP="target/generated-web/assets/app.js.map"

assert_json \
  "source map contains lodash-es source modules" \
  "$SOURCE_MAP" \
  '[.sources[]? | select(contains("node_modules/lodash-es/"))] | length > 0'

assert_json \
  "source map contains lodash-es escape.js used by the application" \
  "$SOURCE_MAP" \
  '[.sources[]? | select(endswith("/lodash-es/escape.js"))] | length > 0'

assert_json \
  "source map contains lodash-es startCase.js used by the application" \
  "$SOURCE_MAP" \
  '[.sources[]? | select(endswith("/lodash-es/startCase.js"))] | length > 0'

if syft target/generated-web \
     -o syft-json="$TMP/generated-web.syft.json" \
     >/dev/null 2>&1; then
  pass "Syft scans only the generated frontend"
else
  fail "Syft scans only the generated frontend"
fi

assert_json \
  "generated frontend has zero identifiable packages" \
  "$TMP/generated-web.syft.json" \
  '(.artifacts // []) | length == 0'

assert_json \
  "Syft does not identify lodash-es from generated frontend bytes" \
  "$TMP/generated-web.syft.json" \
  '[.artifacts[]? | select(.name == "lodash-es")] | length == 0'

# ---------------------------------------------------------------------------

phase "WAR boundary"

unzip -l "$WAR" >"$TMP/war-entries.txt"

assert_grep \
  "WAR physically contains commons-lang3 $EXPECTED_COMMONS" \
  "WEB-INF/lib/commons-lang3-${EXPECTED_COMMONS}\.jar" \
  "$TMP/war-entries.txt"

assert_grep \
  "WAR physically contains generated app.js" \
  'assets/app\.js$' \
  "$TMP/war-entries.txt"

assert_grep \
  "WAR physically contains generated app.js.map" \
  'assets/app\.js\.map$' \
  "$TMP/war-entries.txt"

assert_not_grep \
  "WAR does not contain the Jakarta EE umbrella API JAR" \
  'WEB-INF/lib/jakarta\.jakartaee-web-api-' \
  "$TMP/war-entries.txt"

if mvn dependency:tree \
     -Dincludes=jakarta.platform:jakarta.jakartaee-web-api \
     >"$TMP/jakarta-tree.log" 2>&1; then
  pass "Maven resolves Jakarta EE Web API dependency"
else
  fail "Maven resolves Jakarta EE Web API dependency"
fi

assert_grep \
  "Jakarta EE Web API $EXPECTED_JAKARTA resolves as provided" \
  "jakarta\.platform:jakarta\.jakartaee-web-api:jar:${EXPECTED_JAKARTA}:provided" \
  "$TMP/jakarta-tree.log"

if syft "$WAR" \
     -o cyclonedx-json="$TMP/war.cdx.json" \
     >/dev/null 2>&1; then
  pass "Syft generates a CycloneDX SBOM from the physical WAR"
else
  fail "Syft generates a CycloneDX SBOM from the physical WAR"
fi

assert_json \
  "WAR-derived SBOM identifies commons-lang3 $EXPECTED_COMMONS" \
  "$TMP/war.cdx.json" \
  "[.components[]? | select(.name == \"commons-lang3\" and .version == \"$EXPECTED_COMMONS\")] | length > 0"

assert_json \
  "WAR-derived SBOM identifies the application $EXPECTED_APP" \
  "$TMP/war.cdx.json" \
  "[.components[]? | select(.name == \"payara-mvnpm-trace-lab\" and .version == \"$EXPECTED_APP\")] | length > 0"

assert_json \
  "WAR-derived SBOM does not identify lodash-es" \
  "$TMP/war.cdx.json" \
  '[.components[]? | select(.name == "lodash-es")] | length == 0'

assert_json \
  "WAR-derived SBOM does not identify the provided Jakarta EE umbrella API" \
  "$TMP/war.cdx.json" \
  '[.components[]? | select(.name == "jakarta.jakartaee-web-api")] | length == 0'

# ---------------------------------------------------------------------------

phase "Maven-model versus WAR-derived CycloneDX"

if mvn org.cyclonedx:cyclonedx-maven-plugin:2.9.3:makeBom \
     -DoutputFormat=json \
     >"$TMP/cyclonedx-maven.log" 2>&1; then
  pass "CycloneDX Maven plugin generates target/bom.json"
else
  fail "CycloneDX Maven plugin generates target/bom.json"
fi

MAVEN_BOM="target/bom.json"

[[ -f "$MAVEN_BOM" ]] \
  && pass "Maven-model CycloneDX BOM exists" \
  || fail "Maven-model CycloneDX BOM exists"

if [[ -f "$MAVEN_BOM" ]]; then
  assert_json \
    "Maven-model SBOM contains commons-lang3 $EXPECTED_COMMONS" \
    "$MAVEN_BOM" \
    "[.components[]? | select(.name == \"commons-lang3\" and .version == \"$EXPECTED_COMMONS\")] | length > 0"

  assert_json \
    "Maven-model SBOM contains Jakarta EE Web API $EXPECTED_JAKARTA" \
    "$MAVEN_BOM" \
    "[.components[]? | select(.name == \"jakarta.jakartaee-web-api\" and .version == \"$EXPECTED_JAKARTA\")] | length > 0"

  assert_json \
    "CycloneDX Maven output currently maps the provided Jakarta dependency to scope required" \
    "$MAVEN_BOM" \
    "[.components[]? | select(.name == \"jakarta.jakartaee-web-api\" and .version == \"$EXPECTED_JAKARTA\" and .scope == \"required\")] | length > 0"

  assert_json \
    "Maven-model SBOM omits the build-plugin dependency lodash-es" \
    "$MAVEN_BOM" \
    '[.components[]? | select(.name == "lodash-es")] | length == 0'
fi

assert_json \
  "WAR-derived SBOM lacks Jakarta EE umbrella dependency that Maven-model SBOM contains" \
  "$TMP/war.cdx.json" \
  '[.components[]? | select(.name == "jakarta.jakartaee-web-api")] | length == 0'

# ---------------------------------------------------------------------------

if [[ "$SKIP_RUNTIME" -eq 0 || "$SKIP_IMAGE" -eq 0 ]]; then
  phase "Build Payara proof image"

  if docker build -t "$IMAGE_TAG" . >"$TMP/docker-build.log" 2>&1; then
    IMAGE_BUILT=1
    pass "Docker image builds from Payara Server Web $EXPECTED_PAYARA"
  else
    fail "Docker image builds from Payara Server Web $EXPECTED_PAYARA"
    printf '\n--- docker-build.log ---\n' >&2
    cat "$TMP/docker-build.log" >&2 || true
  fi
fi

# ---------------------------------------------------------------------------

if [[ "$SKIP_RUNTIME" -eq 0 && "$IMAGE_BUILT" -eq 1 ]]; then
  phase "Runtime"

  if docker run -d \
       --name "$CONTAINER_NAME" \
       -p "${PROOF_PORT}:8080" \
       "$IMAGE_TAG" \
       >"$TMP/container.id" 2>"$TMP/docker-run.log"; then
    CONTAINER_STARTED=1
    pass "Payara proof container starts"
  else
    fail "Payara proof container starts"
    cat "$TMP/docker-run.log" >&2 || true
  fi

  RUNTIME_OK=0

  if [[ "$CONTAINER_STARTED" -eq 1 ]]; then
    for _ in $(seq 1 90); do
      if curl -fsS \
           "http://localhost:${PROOF_PORT}/trace/api/info?name=runtime%20trace" \
           >"$TMP/runtime.json" 2>/dev/null; then
        RUNTIME_OK=1
        break
      fi

      if ! docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
        break
      fi

      sleep 2
    done
  fi

  if [[ "$RUNTIME_OK" -eq 1 ]]; then
    pass "Payara deploys the WAR and runtime endpoint responds"

    assert_json \
      "runtime returns expected message" \
      "$TMP/runtime.json" \
      '.message == "Hello Runtime trace"'

    assert_json \
      "runtime identifies the application" \
      "$TMP/runtime.json" \
      '.application == "payara-mvnpm-trace-lab"'

    assert_json \
      "runtime confirms commons-lang3-backed servlet path" \
      "$TMP/runtime.json" \
      '.javaLibrary == "commons-lang3"'

    assert_json \
      "runtime identifies Payara" \
      "$TMP/runtime.json" \
      '.server == "Payara"'
  else
    fail "Payara deploys the WAR and runtime endpoint responds"

    if [[ "$CONTAINER_STARTED" -eq 1 ]]; then
      printf '\n--- Payara container log ---\n' >&2
      docker logs "$CONTAINER_NAME" >&2 || true
    fi
  fi
elif [[ "$SKIP_RUNTIME" -eq 1 ]]; then
  warn "runtime proof skipped"
fi

# ---------------------------------------------------------------------------

if [[ "$SKIP_IMAGE" -eq 0 && "$IMAGE_BUILT" -eq 1 ]]; then
  phase "Container inventory"

  if syft "$IMAGE_TAG" \
       -o cyclonedx-json="$TMP/image.cdx.json" \
       >/dev/null 2>&1; then
    pass "Syft generates a CycloneDX SBOM from the container image"
  else
    fail "Syft generates a CycloneDX SBOM from the container image"
  fi

  assert_json \
    "container inventory still identifies commons-lang3 $EXPECTED_COMMONS" \
    "$TMP/image.cdx.json" \
    "[.components[]? | select(.name == \"commons-lang3\" and .version == \"$EXPECTED_COMMONS\")] | length > 0"

  assert_json \
    "container inventory identifies the application $EXPECTED_APP" \
    "$TMP/image.cdx.json" \
    "[.components[]? | select(.name == \"payara-mvnpm-trace-lab\" and .version == \"$EXPECTED_APP\")] | length > 0"

  assert_json \
    "container inventory includes concrete Jakarta JSON runtime API" \
    "$TMP/image.cdx.json" \
    '[.components[]? | select(.name == "jakarta.json-api")] | length > 0'

  assert_json \
    "container inventory includes concrete Jakarta Servlet runtime API" \
    "$TMP/image.cdx.json" \
    '[.components[]? | select(.name == "jakarta.servlet-api")] | length > 0'

  assert_json \
    "container inventory includes Payara runtime software" \
    "$TMP/image.cdx.json" \
    "[.components[]? | select(.name == \"payara-api\" and .version == \"$EXPECTED_PAYARA\")] | length > 0"

  assert_json \
    "container inventory still does not identify lodash-es" \
    "$TMP/image.cdx.json" \
    '[.components[]? | select(.name == "lodash-es")] | length == 0'

  WAR_COUNT=$(jq '(.components // []) | length' "$TMP/war.cdx.json")
  IMAGE_COUNT=$(jq '(.components // []) | length' "$TMP/image.cdx.json")

  if [[ "$IMAGE_COUNT" -gt "$WAR_COUNT" ]]; then
    pass "container inventory is larger than WAR inventory ($IMAGE_COUNT > $WAR_COUNT components)"
  else
    fail "container inventory is larger than WAR inventory ($IMAGE_COUNT > $WAR_COUNT components)"
  fi
elif [[ "$SKIP_IMAGE" -eq 1 ]]; then
  warn "container-image inventory proof skipped"
fi

# ---------------------------------------------------------------------------

summary
