#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in snyk jq find; do
  require_command "$cmd"
done

S03="$(resolve_s03)" || {
  echo "Could not find S03-python-pep517." >&2
  echo "Set S03_DIR=/path/to/S03-python-pep517" >&2
  exit 1
}

BASE="$ROOT/results/s03/baseline"
OUT="$ROOT/results/s03/snyk"
mkdir -p "$OUT"

for f in site-packages-path.txt wheel-path.txt; do
  [[ -f "$BASE/$f" ]] || {
    echo "Run ./scripts/baseline-s03.sh first." >&2
    exit 1
  }
done

PY="$S03/.venv/bin/python"
SITE_PACKAGES="$(cat "$BASE/site-packages-path.txt")"
WHEEL="$(cat "$BASE/wheel-path.txt")"
VENV_PATH="$S03/.venv/bin:$PATH"

snyk --version | tee "$OUT/snyk-version.txt"

echo
echo "S03: $S03"
echo "Python: $PY"
echo "Output: $OUT"

(
  cd "$S03"
  capture_command \
    "1. Snyk Pip test using the installed S03 environment" \
    "$OUT/snyk-pip-test.txt" \
    env "PATH=$VENV_PATH" \
    snyk test \
      --file=requirements.txt \
      --package-manager=pip \
      --command=python \
      --print-deps \
      --json-file-output="$OUT/snyk-pip-test.json"
)

(
  cd "$S03"
  capture_command \
    "2. Snyk Pip CycloneDX SBOM using the installed S03 environment" \
    "$OUT/snyk-pip-sbom.txt" \
    env "PATH=$VENV_PATH" \
    snyk sbom \
      --file=requirements.txt \
      --package-manager=pip \
      --command=python \
      --format=cyclonedx1.6+json \
      --json-file-output="$OUT/snyk-pip-sbom.json"
)

(
  cd "$BASE/sdist-unpacked"
  capture_command \
    "3. Snyk project discovery against the unpacked tracehook sdist" \
    "$OUT/snyk-sdist-project.txt" \
    env "PATH=$VENV_PATH" \
    snyk test \
      --all-projects \
      --json-file-output="$OUT/snyk-sdist-project.json"
)

(
  cd "$BASE/wheel-unpacked"
  capture_command \
    "4. Snyk project discovery against the unpacked generated wheel" \
    "$OUT/snyk-wheel-project.txt" \
    env "PATH=$VENV_PATH" \
    snyk test \
      --all-projects \
      --json-file-output="$OUT/snyk-wheel-project.json"
)

(
  cd "$SITE_PACKAGES"
  capture_command \
    "5. Snyk project discovery against installed site-packages only" \
    "$OUT/snyk-site-packages-project.txt" \
    env "PATH=$VENV_PATH" \
    snyk test \
      --all-projects \
      --json-file-output="$OUT/snyk-site-packages-project.json"
)

echo
echo "== Search Snyk outputs for package identity vs build-execution evidence =="
for token in \
  'reportkit' \
  'tracehook-demo' \
  'tracehook_demo' \
  'tracehook_backend' \
  'build_wheel' \
  'build-hook.json' \
  'pep517-build-backend-executed'
do
  echo
  echo "-- $token"
  grep -R -n -F "$token" "$OUT" \
    --include='*.txt' --include='*.json' \
    || echo "(no hits)"
done >"$OUT/evidence-token-search.txt"

cat "$OUT/evidence-token-search.txt"

echo
echo "S03 Snyk probes captured."
echo "Run:"
echo "  ./scripts/compare-s03.sh"
