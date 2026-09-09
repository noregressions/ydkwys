#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

EXPECTED_JACKSON="2.19.4"
EXPECTED_CODEC_EMBEDDED="1.17.1"
EXPECTED_CODEC_SERVICE="1.18.0"
EXPECTED_LODASH="4.17.21"
EXPECTED_NORMALIZER="1.0.0"

SKIP_BUILD=0
SKIP_RUNTIME=0
SKIP_IMAGE=0

usage() {
  cat <<'EOF'
Usage: ./scripts/proof-check.sh [options]

Proves that the S01 demo still produces the outcomes described in LESSON.md.

Options:
  --skip-build     Check existing build output instead of rebuilding.
  --skip-runtime   Do not start the Spring Boot application.
  --skip-image     Do not build/scan the Docker image.
  --quick          Equivalent to --skip-runtime --skip-image.
  -h, --help       Show this help.

Environment:
  PROOF_PORT=18080       Port used for the runtime check.
  KEEP_PROOF_IMAGE=1    Keep the temporary proof Docker image.
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
APP_PID=""
IMAGE_BUILT=0
IMAGE_TAG="kcdc-s01-proof:local-$$"
PROOF_PORT="${PROOF_PORT:-18080}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/s01-proof.XXXXXX")

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

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi

  if [[ "$IMAGE_BUILT" -eq 1 && "${KEEP_PROOF_IMAGE:-0}" != "1" ]]; then
    docker image rm -f "$IMAGE_TAG" >/dev/null 2>&1 || true
  fi

  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

summary() {
  printf '\n========================================\n'
  printf 'S01 proof result: %d passed, %d failed, %d warnings\n' "$PASS" "$FAIL" "$WARN"
  if [[ "$FAIL" -eq 0 ]]; then
    printf 'RESULT: PASS — the demo outcomes are still true.\n'
    return 0
  else
    printf 'RESULT: FAIL — do not rely on this demo until the failed proof(s) are resolved.\n' >&2
    return 1
  fi
}

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

assert_jar_has() {
  local description="$1"
  local jar_file="$2"
  local pattern="$3"
  if jar tf "$jar_file" | grep -Eq "$pattern"; then
    pass "$description"
  else
    fail "$description"
  fi
}

assert_jar_lacks() {
  local description="$1"
  local jar_file="$2"
  local pattern="$3"
  if jar tf "$jar_file" | grep -Eq "$pattern"; then
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

for cmd in java mvn node npm jar unzip zip jq syft curl grep; do
  require "$cmd"
done
if [[ "$SKIP_IMAGE" -eq 0 ]]; then
  require docker
fi

if [[ "$FAIL" -ne 0 ]]; then
  summary
  exit 1
fi

phase "Source invariants"

if [[ -f frontend/package.json ]]; then
  assert_json \
    "frontend declares lodash $EXPECTED_LODASH" \
    frontend/package.json \
    ".dependencies.lodash == \"$EXPECTED_LODASH\""
else
  fail "frontend/package.json exists"
fi

if grep -Eq "from ['\"]lodash['\"]" frontend/src/main.jsx; then
  pass "frontend actually imports lodash"
else
  fail "frontend actually imports lodash"
fi

assert_grep \
  "normalizer declares commons-codec through the scenario property" \
  '<artifactId>commons-codec</artifactId>' \
  normalizer/pom.xml

assert_grep \
  "Shade relocation target remains com.acme.internal.codec" \
  '<shadedPattern>com\.acme\.internal\.codec</shadedPattern>' \
  normalizer/pom.xml

assert_grep \
  "service declares jackson-databind" \
  '<artifactId>jackson-databind</artifactId>' \
  service/pom.xml

# ---------------------------------------------------------------------------

phase "Clean build"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  if ./scripts/clean.sh >"$TMP/clean.log" 2>&1 &&
     ./scripts/build.sh >"$TMP/build.log" 2>&1; then
    pass "clean build completes"
  else
    fail "clean build completes"
    printf '\n--- clean.log ---\n' >&2
    cat "$TMP/clean.log" >&2 || true
    printf '\n--- build.log ---\n' >&2
    cat "$TMP/build.log" >&2 || true
    summary
    exit 1
  fi
else
  warn "build skipped; checking existing outputs"
fi

NORMALIZER_JAR="normalizer/target/normalizer-$EXPECTED_NORMALIZER.jar"
SERVICE_JAR="service/target/service-$EXPECTED_NORMALIZER.jar"

[[ -f "$NORMALIZER_JAR" ]] && pass "normalizer JAR exists" || fail "normalizer JAR exists"
[[ -f "$SERVICE_JAR" ]] && pass "service JAR exists" || fail "service JAR exists"
[[ -d frontend/dist ]] && pass "frontend dist exists" || fail "frontend dist exists"

if [[ -f frontend/package-lock.json ]]; then
  pass "package-lock.json exists after build"
  assert_json \
    "lockfile resolves lodash $EXPECTED_LODASH" \
    frontend/package-lock.json \
    ".packages[\"node_modules/lodash\"].version == \"$EXPECTED_LODASH\""

  if command -v git >/dev/null 2>&1 &&
     git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git ls-files --error-unmatch frontend/package-lock.json >/dev/null 2>&1; then
      pass "package-lock.json is committed"
    else
      warn "package-lock.json is generated but not committed; demo works, but dependency evidence is not reproducible from checkout alone"
    fi
  fi
else
  fail "package-lock.json exists after build"
fi

if [[ "$FAIL" -ne 0 ]]; then
  summary
  exit 1
fi

# ---------------------------------------------------------------------------

phase "Resolver truth"

if mvn -pl service -am dependency:tree \
     -Dincludes=com.fasterxml.jackson.core:jackson-databind \
     >"$TMP/jackson-tree.txt" 2>&1; then
  pass "Maven can resolve the Jackson dependency tree"
  assert_grep \
    "service resolves jackson-databind $EXPECTED_JACKSON" \
    "com\.fasterxml\.jackson\.core:jackson-databind:jar:${EXPECTED_JACKSON}:compile" \
    "$TMP/jackson-tree.txt"
else
  fail "Maven can resolve the Jackson dependency tree"
fi

if mvn -pl normalizer dependency:tree \
     -Dincludes=commons-codec:commons-codec \
     >"$TMP/normalizer-codec-tree.txt" 2>&1; then
  pass "Maven can resolve the normalizer commons-codec tree"
  assert_grep \
    "normalizer resolves commons-codec $EXPECTED_CODEC_EMBEDDED" \
    "commons-codec:commons-codec:jar:${EXPECTED_CODEC_EMBEDDED}:compile" \
    "$TMP/normalizer-codec-tree.txt"
else
  fail "Maven can resolve the normalizer commons-codec tree"
fi

if mvn -pl service -am dependency:tree \
     -Dincludes=commons-codec:commons-codec \
     -Dverbose \
     >"$TMP/service-codec-tree.txt" 2>&1; then
  pass "Maven can resolve the service commons-codec tree"
  assert_grep \
    "service resolves a separate commons-codec $EXPECTED_CODEC_SERVICE" \
    "commons-codec:commons-codec:jar:${EXPECTED_CODEC_SERVICE}:compile" \
    "$TMP/service-codec-tree.txt"
else
  fail "Maven can resolve the service commons-codec tree"
fi

# ---------------------------------------------------------------------------

phase "Physical artefact truth"

assert_jar_has \
  "normalizer contains relocated commons-codec bytecode" \
  "$NORMALIZER_JAR" \
  '^com/acme/internal/codec/'

assert_jar_lacks \
  "normalizer no longer contains the original commons-codec class namespace" \
  "$NORMALIZER_JAR" \
  '^org/apache/commons/codec/'

assert_jar_has \
  "normalizer retains commons-codec Maven identity metadata" \
  "$NORMALIZER_JAR" \
  '^META-INF/maven/commons-codec/commons-codec/pom\.properties$'

if unzip -p "$NORMALIZER_JAR" \
     META-INF/maven/commons-codec/commons-codec/pom.properties \
     >"$TMP/codec-pom.properties" 2>/dev/null; then
  assert_grep \
    "surviving metadata identifies commons-codec $EXPECTED_CODEC_EMBEDDED" \
    "^version=${EXPECTED_CODEC_EMBEDDED}$" \
    "$TMP/codec-pom.properties"
else
  fail "commons-codec pom.properties can be read from shaded normalizer"
fi

assert_jar_has \
  "service packages jackson-databind $EXPECTED_JACKSON" \
  "$SERVICE_JAR" \
  "^BOOT-INF/lib/jackson-databind-${EXPECTED_JACKSON}\.jar$"

assert_jar_has \
  "service packages the shaded normalizer" \
  "$SERVICE_JAR" \
  "^BOOT-INF/lib/normalizer-${EXPECTED_NORMALIZER}\.jar$"

assert_jar_has \
  "service separately packages commons-codec $EXPECTED_CODEC_SERVICE" \
  "$SERVICE_JAR" \
  "^BOOT-INF/lib/commons-codec-${EXPECTED_CODEC_SERVICE}\.jar$"

assert_jar_lacks \
  "service does not separately package commons-codec $EXPECTED_CODEC_EMBEDDED" \
  "$SERVICE_JAR" \
  "^BOOT-INF/lib/commons-codec-${EXPECTED_CODEC_EMBEDDED}\.jar$"

assert_jar_has \
  "service contains the built frontend assets" \
  "$SERVICE_JAR" \
  '^BOOT-INF/classes/static/assets/.*\.js$'

# ---------------------------------------------------------------------------

phase "Identification survives shading only while metadata survives"

if syft "$NORMALIZER_JAR" -o syft-json="$TMP/normalizer.syft.json" >/dev/null 2>&1; then
  pass "Syft scans the shaded normalizer"
  assert_json \
    "Syft identifies embedded commons-codec $EXPECTED_CODEC_EMBEDDED" \
    "$TMP/normalizer.syft.json" \
    "[.artifacts[]? | select(.name == \"commons-codec\" and .version == \"$EXPECTED_CODEC_EMBEDDED\")] | length > 0"
else
  fail "Syft scans the shaded normalizer"
fi

STRIPPED="$TMP/normalizer-no-codec-metadata.jar"
cp "$NORMALIZER_JAR" "$STRIPPED"
zip -qd "$STRIPPED" 'META-INF/maven/commons-codec/commons-codec/*' >/dev/null 2>&1 || true

assert_jar_has \
  "metadata-stripped copy still contains relocated codec bytecode" \
  "$STRIPPED" \
  '^com/acme/internal/codec/'

assert_jar_lacks \
  "metadata-stripped copy no longer contains commons-codec Maven metadata" \
  "$STRIPPED" \
  '^META-INF/maven/commons-codec/commons-codec/'

if syft "$STRIPPED" -o syft-json="$TMP/stripped.syft.json" >/dev/null 2>&1; then
  pass "Syft scans the metadata-stripped normalizer"
  assert_json \
    "commons-codec $EXPECTED_CODEC_EMBEDDED becomes unidentifiable after metadata removal" \
    "$TMP/stripped.syft.json" \
    "[.artifacts[]? | select(.name == \"commons-codec\" and .version == \"$EXPECTED_CODEC_EMBEDDED\")] | length == 0"
else
  fail "Syft scans the metadata-stripped normalizer"
fi

# ---------------------------------------------------------------------------

phase "Bundled frontend loses npm package identity"

if syft frontend/dist -o syft-json="$TMP/frontend.syft.json" >/dev/null 2>&1; then
  pass "Syft scans only frontend/dist"
  assert_json \
    "Syft does not identify lodash from the deployable frontend bundle" \
    "$TMP/frontend.syft.json" \
    "[.artifacts[]? | select(.name == \"lodash\")] | length == 0"
else
  fail "Syft scans only frontend/dist"
fi

if find frontend/dist -type d -path '*/node_modules/lodash' -print -quit | grep -q .; then
  fail "deployable frontend has no discrete node_modules/lodash package directory"
else
  pass "deployable frontend has no discrete node_modules/lodash package directory"
fi

# ---------------------------------------------------------------------------

phase "CycloneDX viewpoint difference"

if mvn -pl service -am \
     org.cyclonedx:cyclonedx-maven-plugin:2.9.3:makeBom \
     -DoutputFormat=json \
     >"$TMP/cyclonedx-maven.log" 2>&1; then
  pass "CycloneDX Maven plugin generates module SBOMs"
else
  fail "CycloneDX Maven plugin generates module SBOMs"
fi

MAVEN_SERVICE_BOM="service/target/bom.json"

if [[ -f "$MAVEN_SERVICE_BOM" ]]; then
  pass "Maven-generated service CycloneDX SBOM exists"
  assert_json \
    "Maven SBOM contains commons-codec $EXPECTED_CODEC_SERVICE" \
    "$MAVEN_SERVICE_BOM" \
    "[.components[]? | select(.name == \"commons-codec\" and .version == \"$EXPECTED_CODEC_SERVICE\")] | length > 0"
  assert_json \
    "Maven SBOM omits embedded commons-codec $EXPECTED_CODEC_EMBEDDED" \
    "$MAVEN_SERVICE_BOM" \
    "[.components[]? | select(.name == \"commons-codec\" and .version == \"$EXPECTED_CODEC_EMBEDDED\")] | length == 0"
  assert_json \
    "Maven SBOM contains jackson-databind $EXPECTED_JACKSON" \
    "$MAVEN_SERVICE_BOM" \
    "[.components[]? | select(.name == \"jackson-databind\" and .version == \"$EXPECTED_JACKSON\")] | length > 0"
  assert_json \
    "Maven SBOM has no lodash component" \
    "$MAVEN_SERVICE_BOM" \
    "[.components[]? | select(.name == \"lodash\")] | length == 0"
else
  fail "Maven-generated service CycloneDX SBOM exists"
fi

SYFT_SERVICE_BOM="$TMP/service-syft.cdx.json"
if syft "$SERVICE_JAR" -o cyclonedx-json="$SYFT_SERVICE_BOM" >/dev/null 2>&1; then
  pass "Syft generates a CycloneDX SBOM from the finished service JAR"
  assert_json \
    "Syft SBOM sees embedded commons-codec $EXPECTED_CODEC_EMBEDDED" \
    "$SYFT_SERVICE_BOM" \
    "[.components[]? | select(.name == \"commons-codec\" and .version == \"$EXPECTED_CODEC_EMBEDDED\")] | length > 0"
  assert_json \
    "Syft SBOM sees separately packaged commons-codec $EXPECTED_CODEC_SERVICE" \
    "$SYFT_SERVICE_BOM" \
    "[.components[]? | select(.name == \"commons-codec\" and .version == \"$EXPECTED_CODEC_SERVICE\")] | length > 0"
  assert_json \
    "Syft SBOM sees jackson-databind $EXPECTED_JACKSON" \
    "$SYFT_SERVICE_BOM" \
    "[.components[]? | select(.name == \"jackson-databind\" and .version == \"$EXPECTED_JACKSON\")] | length > 0"
  assert_json \
    "Syft SBOM still does not identify lodash" \
    "$SYFT_SERVICE_BOM" \
    "[.components[]? | select(.name == \"lodash\")] | length == 0"
else
  fail "Syft generates a CycloneDX SBOM from the finished service JAR"
fi

# ---------------------------------------------------------------------------

if [[ "$SKIP_RUNTIME" -eq 0 ]]; then
  phase "Runtime proof"

  java -jar "$SERVICE_JAR" --server.port="$PROOF_PORT" >"$TMP/application.log" 2>&1 &
  APP_PID=$!

  RUNTIME_JSON="$TMP/runtime.json"
  READY=0
  for _ in $(seq 1 30); do
    if curl -fsS \
       "http://127.0.0.1:${PROOF_PORT}/api/trace?value=Hello%20Supply%20Chain" \
       >"$RUNTIME_JSON" 2>/dev/null; then
      READY=1
      break
    fi
    if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if [[ "$READY" -eq 1 ]]; then
    pass "Spring Boot application starts and /api/trace responds"
    assert_json \
      "runtime normalizes the sample value" \
      "$RUNTIME_JSON" \
      '.normalized == "hello supply chain"'
    assert_json \
      "runtime returns a SHA-256 value" \
      "$RUNTIME_JSON" \
      '.sha256 | test("^[0-9a-f]{64}$")'
    assert_json \
      "runtime reports all three tracked names" \
      "$RUNTIME_JSON" \
      '(.tracers | sort) == ["commons-codec","jackson-databind","lodash"]'
  else
    fail "Spring Boot application starts and /api/trace responds"
    printf '\n--- application.log ---\n' >&2
    cat "$TMP/application.log" >&2 || true
  fi

  if kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
  APP_PID=""
else
  warn "runtime proof skipped"
fi

# ---------------------------------------------------------------------------

if [[ "$SKIP_IMAGE" -eq 0 ]]; then
  phase "Container boundary proof"

  if docker build -t "$IMAGE_TAG" . >"$TMP/docker-build.log" 2>&1; then
    IMAGE_BUILT=1
    pass "Docker image builds"
  else
    fail "Docker image builds"
    printf '\n--- docker-build.log ---\n' >&2
    cat "$TMP/docker-build.log" >&2 || true
  fi

  if [[ "$IMAGE_BUILT" -eq 1 ]]; then
    IMAGE_BOM="$TMP/image.cdx.json"
    if syft "$IMAGE_TAG" -o cyclonedx-json="$IMAGE_BOM" >/dev/null 2>&1; then
      pass "Syft scans the complete container image"

      assert_json \
        "image contains embedded commons-codec $EXPECTED_CODEC_EMBEDDED" \
        "$IMAGE_BOM" \
        "[.components[]? | select(.name == \"commons-codec\" and .version == \"$EXPECTED_CODEC_EMBEDDED\")] | length > 0"
      assert_json \
        "image contains separately packaged commons-codec $EXPECTED_CODEC_SERVICE" \
        "$IMAGE_BOM" \
        "[.components[]? | select(.name == \"commons-codec\" and .version == \"$EXPECTED_CODEC_SERVICE\")] | length > 0"
      assert_json \
        "image contains jackson-databind $EXPECTED_JACKSON" \
        "$IMAGE_BOM" \
        "[.components[]? | select(.name == \"jackson-databind\" and .version == \"$EXPECTED_JACKSON\")] | length > 0"
      assert_json \
        "image still does not identify lodash" \
        "$IMAGE_BOM" \
        "[.components[]? | select(.name == \"lodash\")] | length == 0"

      if [[ -f "$SYFT_SERVICE_BOM" ]]; then
        SERVICE_COMPONENTS=$(jq '[.components[]?] | length' "$SYFT_SERVICE_BOM")
        IMAGE_COMPONENTS=$(jq '[.components[]?] | length' "$IMAGE_BOM")
        if [[ "$IMAGE_COMPONENTS" -gt "$SERVICE_COMPONENTS" ]]; then
          pass "container inventory is larger than the application-JAR inventory ($IMAGE_COMPONENTS > $SERVICE_COMPONENTS)"
        else
          fail "container inventory is larger than the application-JAR inventory ($IMAGE_COMPONENTS <= $SERVICE_COMPONENTS)"
        fi
      fi
    else
      fail "Syft scans the complete container image"
    fi
  fi
else
  warn "container boundary proof skipped"
fi

summary
