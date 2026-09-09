#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

EXPECTED_DIRECT="reportkit==1.0.0"
EXPECTED_TRANSITIVE="tracehook-demo==1.0.0"
EXPECTED_EVENT="pep517-build-backend-executed"
EXPECTED_GENERATOR="tracehook_backend.build_wheel"
EXPECTED_PORT="${PROOF_PORT:-18083}"

SKIP_BUILD=0
SKIP_RUNTIME=0

usage() {
  cat <<'USAGE'
Usage: ./scripts/proof-check.sh [options]

Proves that the S03 Python PEP 517 demo still produces the outcomes
recorded in LESSON.md.

Options:
  --skip-build     Check the existing .venv and trace-output instead of rebuilding.
  --skip-runtime   Do not start the HTTP application.
  --quick          Equivalent to --skip-runtime.
  -h, --help       Show this help.

Environment:
  PYTHON=python3       Python interpreter used to create the venv.
  PROOF_PORT=18083     Port used for the runtime proof.
USAGE
}

while (($#)); do
  case "$1" in
    --skip-build)   SKIP_BUILD=1 ;;
    --skip-runtime) SKIP_RUNTIME=1 ;;
    --quick)        SKIP_RUNTIME=1 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

PASS=0
FAIL=0
WARN=0
RUNTIME_STARTED=0

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
  printf 'S03 proof result: %d passed, %d failed, %d warnings\n' "$PASS" "$FAIL" "$WARN"

  if [[ "$FAIL" -eq 0 ]]; then
    printf 'RESULT: PASS — the demo outcomes are still true.\n'
    return 0
  fi

  printf 'RESULT: FAIL — do not rely on this demo until the failed proof(s) are resolved.\n' >&2
  return 1
}

cleanup() {
  if [[ "$RUNTIME_STARTED" -eq 1 ]]; then
    ./scripts/stop.sh >/dev/null 2>&1 || true
  fi
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

assert_file_contains() {
  local description="$1"
  local pattern="$2"
  local file="$3"

  if grep -Eq "$pattern" "$file"; then
    pass "$description"
  else
    fail "$description"
  fi
}

phase "Preflight"

for cmd in "${PYTHON:-python3}" curl tar unzip grep find; do
  require "$cmd"
done

if [[ "$FAIL" -ne 0 ]]; then
  summary
  exit 1
fi

phase "Source declaration and package metadata"

if [[ "$(tr -d '\r\n' < requirements.txt)" == "$EXPECTED_DIRECT" ]]; then
  pass "requirements.txt declares only $EXPECTED_DIRECT"
else
  fail "requirements.txt declares only $EXPECTED_DIRECT"
fi

DIRECT_METADATA=$(unzip -p \
  python-repo/reportkit-1.0.0-py3-none-any.whl \
  reportkit-1.0.0.dist-info/METADATA)

if grep -Fq 'Requires-Dist: tracehook-demo==1.0.0' <<<"$DIRECT_METADATA"; then
  pass "reportkit metadata introduces transitive tracehook-demo 1.0.0"
else
  fail "reportkit metadata introduces transitive tracehook-demo 1.0.0"
fi

SDIST_LIST=$(tar -tzf python-repo/tracehook_demo-1.0.0.tar.gz)

if grep -Fq 'tracehook_demo-1.0.0/pyproject.toml' <<<"$SDIST_LIST" \
   && grep -Fq 'tracehook_demo-1.0.0/tracehook_backend.py' <<<"$SDIST_LIST"; then
  pass "transitive sdist contains PEP 517 configuration and backend code"
else
  fail "transitive sdist contains PEP 517 configuration and backend code"
fi

if grep -Eq 'tracehook_demo/__init__\.py|build-hook\.json' <<<"$SDIST_LIST"; then
  fail "generated runtime package files are absent from the source distribution"
else
  pass "generated runtime package files are absent from the source distribution"
fi

PYPROJECT=$(tar -xOzf \
  python-repo/tracehook_demo-1.0.0.tar.gz \
  tracehook_demo-1.0.0/pyproject.toml)

if grep -Fq 'build-backend = "tracehook_backend"' <<<"$PYPROJECT"; then
  pass "sdist selects tracehook_backend as its PEP 517 build backend"
else
  fail "sdist selects tracehook_backend as its PEP 517 build backend"
fi

if grep -Fq 'backend-path = ["."]' <<<"$PYPROJECT"; then
  pass "PEP 517 backend is supplied from inside the sdist"
else
  fail "PEP 517 backend is supplied from inside the sdist"
fi

BACKEND=$(tar -xOzf \
  python-repo/tracehook_demo-1.0.0.tar.gz \
  tracehook_demo-1.0.0/tracehook_backend.py)

if grep -Fq 'def build_wheel(' <<<"$BACKEND" \
   && grep -Fq 'build-hook.json' <<<"$BACKEND" \
   && grep -Fq '__init__.py' <<<"$BACKEND"; then
  pass "build_wheel code generates the runtime package and marker"
else
  fail "build_wheel code generates the runtime package and marker"
fi

phase "Fresh pip install and PEP 517 execution"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  if ./scripts/build.sh >/tmp/s03-proof-build.log 2>&1; then
    pass "fresh Python build/install completes"
  else
    fail "fresh Python build/install completes"
    cat /tmp/s03-proof-build.log >&2 || true
    summary
    exit 1
  fi
else
  warn "build skipped; checking existing .venv and trace-output"
fi

if [[ -x .venv/bin/python ]]; then
  pass "virtual environment exists"
else
  fail "virtual environment exists"
fi

if [[ -f trace-output/pip-install.log ]]; then
  pass "pip install evidence log exists"
else
  fail "pip install evidence log exists"
fi

if [[ "$FAIL" -ne 0 ]]; then
  summary
  exit 1
fi

assert_file_contains \
  "pip processed tracehook-demo from the local sdist" \
  'Processing .*python-repo/tracehook_demo-1\.0\.0\.tar\.gz' \
  trace-output/pip-install.log

assert_file_contains \
  "pip entered the PEP 517 wheel-build path for tracehook-demo" \
  'Building wheel for tracehook-demo \(pyproject\.toml\)' \
  trace-output/pip-install.log

assert_file_contains \
  "pip successfully built tracehook-demo" \
  'Successfully built tracehook-demo' \
  trace-output/pip-install.log

FREEZE=$(PIP_NO_CACHE_DIR=1 .venv/bin/python -m pip freeze 2>/dev/null)

if grep -Fxq "$EXPECTED_DIRECT" <<<"$FREEZE"; then
  pass "installed environment contains $EXPECTED_DIRECT"
else
  fail "installed environment contains $EXPECTED_DIRECT"
fi

if grep -Fxq "$EXPECTED_TRANSITIVE" <<<"$FREEZE"; then
  pass "installed environment contains transitive $EXPECTED_TRANSITIVE"
else
  fail "installed environment contains transitive $EXPECTED_TRANSITIVE"
fi

phase "Generated installed content"

INIT_FILE=$(find .venv -path '*site-packages/tracehook_demo/__init__.py' -print -quit)
MARKER_FILE=$(find .venv -path '*site-packages/tracehook_demo/build-hook.json' -print -quit)

if [[ -n "$INIT_FILE" && -f "$INIT_FILE" ]]; then
  pass "PEP 517-generated tracehook_demo/__init__.py is installed"
else
  fail "PEP 517-generated tracehook_demo/__init__.py is installed"
fi

if [[ -n "$MARKER_FILE" && -f "$MARKER_FILE" ]]; then
  pass "PEP 517-generated build-hook.json is installed"
else
  fail "PEP 517-generated build-hook.json is installed"
fi

if [[ -n "$MARKER_FILE" && -f "$MARKER_FILE" ]]; then
  if .venv/bin/python - "$MARKER_FILE" <<'PY' >/dev/null 2>&1
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    value = json.load(fh)

assert value["event"] == "pep517-build-backend-executed"
assert value["package"] == "tracehook-demo"
assert value["version"] == "1.0.0"
assert value["generatedBy"] == "tracehook_backend.build_wheel"
PY
  then
    pass "generated marker records the expected PEP 517 backend execution"
  else
    fail "generated marker records the expected PEP 517 backend execution"
  fi
fi

phase "Python runtime import path"

if .venv/bin/python - <<'PY' >/dev/null 2>&1
import reportkit

value = reportkit.runtime_trace()
assert value["event"] == "pep517-build-backend-executed"
assert value["package"] == "tracehook-demo"
assert value["version"] == "1.0.0"
assert value["generatedBy"] == "tracehook_backend.build_wheel"
PY
then
  pass "reportkit reaches the generated transitive package at runtime"
else
  fail "reportkit reaches the generated transitive package at runtime"
fi

if [[ "$SKIP_RUNTIME" -eq 0 ]]; then
  phase "HTTP runtime"

  ./scripts/stop.sh >/dev/null 2>&1 || true

  if PORT="$EXPECTED_PORT" ./scripts/run.sh >/tmp/s03-proof-run.log 2>&1; then
    RUNTIME_STARTED=1
    pass "application starts on proof port $EXPECTED_PORT"
  else
    fail "application starts on proof port $EXPECTED_PORT"
    cat /tmp/s03-proof-run.log >&2 || true
  fi

  if [[ "$RUNTIME_STARTED" -eq 1 ]]; then
    RUNTIME_JSON=$(curl -fsS "http://127.0.0.1:${EXPECTED_PORT}/trace" || true)

    if .venv/bin/python -c '
import json, sys
value=json.load(sys.stdin)
assert value["event"] == "pep517-build-backend-executed"
assert value["generatedBy"] == "tracehook_backend.build_wheel"
assert value["package"] == "tracehook-demo"
assert value["version"] == "1.0.0"
' <<<"$RUNTIME_JSON" >/dev/null 2>&1; then
      pass "HTTP /trace exposes the PEP 517-generated runtime data"
    else
      fail "HTTP /trace exposes the PEP 517-generated runtime data"
    fi
  fi
else
  warn "HTTP runtime proof skipped"
fi

summary
