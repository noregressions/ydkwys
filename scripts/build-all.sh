#!/usr/bin/env bash
#
# build-all.sh — do every download, pull and compile the workshop needs.
#
# Automates "setup/04 BUILDING.md" so a machine can be made ready in one
# command. It is the slowest step of the host route, so run it on a good
# network.
#
# This script drives the existing per-scenario scripts rather than
# reimplementing them, so it cannot drift from what the walkthroughs actually
# run.
#
# It starts no long-running servers and leaves no container running.

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

DO_PULL=1
DO_SCENARIOS=1
DO_IMAGES=1
DO_DB=1
DO_INVESTIGATIONS=0
LIST_ONLY=0

usage() {
  cat <<'EOF'
Usage: ./scripts/build-all.sh [options]

Performs every download, image pull and compile the workshop needs, so that
none of it happens during the workshop itself.

Phases, in order:

  1. Preflight        check the toolchain, report what is missing
  2. Base images      docker pull the two base images
  3. Scenarios        build S01-S05 (Maven, npm, Vite, Python venv)
  4. Scenario images  build the S01 and S02 container images
  5. Scanner data     warm Grype, Trivy and Syft
  6. Investigations   optional: run the T01-T07 baselines

Options:
  --skip-pull            Do not pull the base images.
  --skip-scenarios       Do not build the scenarios.
  --skip-images          Do not build the S01/S02 container images.
  --skip-db              Do not warm the scanner databases.
  --with-investigations  Also run the T01-T07 baselines (slow; T06 downloads
                         a large NVD dataset on first run).
  --quick                Scenarios only. Equivalent to
                         --skip-pull --skip-images --skip-db.
  --list                 Print the phases that would run, then exit.
  -h, --help             Show this help.

Environment:
  NVD_API_KEY   If set, T06 uses Dependency-Check 13.0.0; if unset it falls
                back to 12.2.2. Only relevant with --with-investigations.

Every phase is independent: a failure is recorded and the run continues, so
one command tells you everything that needs attention. Exit status is non-zero
if any step failed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-pull)           DO_PULL=0 ;;
    --skip-scenarios)      DO_SCENARIOS=0 ;;
    --skip-images)         DO_IMAGES=0 ;;
    --skip-db)             DO_DB=0 ;;
    --with-investigations) DO_INVESTIGATIONS=1 ;;
    --quick)               DO_PULL=0; DO_IMAGES=0; DO_DB=0 ;;
    --list)                LIST_ONLY=1 ;;
    -h|--help)             usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; echo >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Reporting
#
# Results accumulate into three parallel-indexed strings rather than an
# associative array, so this stays compatible with the Bash 3.2 that macOS
# ships.
# ---------------------------------------------------------------------------

RESULTS=""
FAILED=0
SKIPPED=0
PASSED=0

TOTAL_START=$(date +%s)

record() {
  # record <status> <label> <detail>
  RESULTS="${RESULTS}$1|$2|$3
"
  case "$1" in
    PASS) PASSED=$((PASSED + 1)) ;;
    FAIL) FAILED=$((FAILED + 1)) ;;
    SKIP) SKIPPED=$((SKIPPED + 1)) ;;
  esac
}

banner() {
  echo
  echo "==============================================================="
  echo "  $*"
  echo "==============================================================="
}

step() {
  echo
  echo "-- $*"
}

have() { command -v "$1" >/dev/null 2>&1; }

# run_step <label> <command...>
#
# Runs a command, times it, and records the outcome without aborting the run.
run_step() {
  local label="$1"; shift
  local start elapsed
  step "$label"
  start=$(date +%s)
  if "$@"; then
    elapsed=$(( $(date +%s) - start ))
    echo "   ok (${elapsed}s)"
    record PASS "$label" "${elapsed}s"
    return 0
  else
    elapsed=$(( $(date +%s) - start ))
    echo "   FAILED (${elapsed}s)" >&2
    record FAIL "$label" "${elapsed}s"
    return 1
  fi
}

skip_step() {
  step "$1"
  echo "   skipped: $2"
  record SKIP "$1" "$2"
}

in_dir() {
  # in_dir <dir> <command...>
  local d="$1"; shift
  ( cd "$ROOT/$d" && "$@" )
}

# ---------------------------------------------------------------------------
# Phase list / dry run
# ---------------------------------------------------------------------------

if [[ "$LIST_ONLY" == 1 ]]; then
  echo "Phases that would run:"
  echo "  1. Preflight                        always"
  [[ "$DO_PULL"           == 1 ]] && echo "  2. Pull base images"
  [[ "$DO_SCENARIOS"      == 1 ]] && echo "  3. Build scenarios S01-S05"
  [[ "$DO_IMAGES"         == 1 ]] && echo "  4. Build S01/S02 container images"
  [[ "$DO_DB"             == 1 ]] && echo "  5. Warm Grype / Trivy / Syft"
  [[ "$DO_INVESTIGATIONS" == 1 ]] && echo "  6. Run T01-T07 baselines"
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------

banner "1. Preflight"

REQUIRED="git java mvn node npm python3"
OPTIONAL="docker jq syft grype trivy snyk pip-audit unzip zip"

MISSING_REQUIRED=""
for c in $REQUIRED; do
  if have "$c"; then
    printf '   %-10s %s\n' "$c" "present"
  else
    printf '   %-10s %s\n' "$c" "MISSING (required)"
    MISSING_REQUIRED="$MISSING_REQUIRED $c"
  fi
done

echo
for c in $OPTIONAL; do
  if have "$c"; then
    printf '   %-10s %s\n' "$c" "present"
  else
    printf '   %-10s %s\n' "$c" "missing (phases needing it will be skipped)"
  fi
done

if [[ -n "$MISSING_REQUIRED" ]]; then
  echo
  echo "Cannot continue. Install:$MISSING_REQUIRED" >&2
  echo >&2
  echo "For versions and install links for every tool, run:" >&2
  echo "  ./scripts/tools-check.sh" >&2
  echo >&2
  echo "See setup/02 tools.md" >&2
  exit 1
fi

DOCKER_OK=0
if have docker && docker info >/dev/null 2>&1; then
  DOCKER_OK=1
else
  echo
  echo "   note: docker is not available or not running."
  echo "         Image pulls and image builds will be skipped."
fi

# ---------------------------------------------------------------------------
# 2. Base images
# ---------------------------------------------------------------------------

banner "2. Base images"

BASE_IMAGES="eclipse-temurin:21-jre-jammy payara/server-web:7.2026.7"

if [[ "$DO_PULL" != 1 ]]; then
  skip_step "pull base images" "--skip-pull"
elif [[ "$DOCKER_OK" != 1 ]]; then
  skip_step "pull base images" "docker unavailable"
else
  for img in $BASE_IMAGES; do
    run_step "pull $img" docker pull "$img" || true
  done
fi

# ---------------------------------------------------------------------------
# 3. Scenarios
#
# Order matters only in that S01 and S02 must be built before their container
# images in phase 4. The five scenarios are otherwise independent.
# ---------------------------------------------------------------------------

banner "3. Scenarios"

SCENARIOS="S01-spring-node S02-payara-mvnpm S03-python-pep517 S04-maven-plugin-hidden-content S05-node-prepack"

if [[ "$DO_SCENARIOS" != 1 ]]; then
  skip_step "build scenarios" "--skip-scenarios"
else
  for s in $SCENARIOS; do
    if [[ ! -x "$ROOT/scenarios/$s/scripts/build.sh" ]]; then
      skip_step "build $s" "scripts/build.sh not found or not executable"
      continue
    fi
    run_step "build $s" in_dir "scenarios/$s" ./scripts/build.sh || true
  done
fi

# ---------------------------------------------------------------------------
# 4. Scenario container images
#
# T02 scans local:// images, and T03/T04 use a Docker image source, so these
# must exist locally before those investigations can run.
# ---------------------------------------------------------------------------

banner "4. Scenario container images"

if [[ "$DO_IMAGES" != 1 ]]; then
  skip_step "build scenario images" "--skip-images"
elif [[ "$DOCKER_OK" != 1 ]]; then
  skip_step "build scenario images" "docker unavailable"
else
  # S01 -> registry.example.com/checkout-service:release-123
  run_step "build S01 image" \
    in_dir scenarios/S01-spring-node ./scripts/image-trace.sh || true

  # S02 -> payara-mvnpm-trace-lab:local  (builds the image only, starts nothing)
  run_step "build S02 image" \
    in_dir scenarios/S02-payara-mvnpm ./scripts/image-trace.sh || true
fi

# ---------------------------------------------------------------------------
# 5. Scanner data
# ---------------------------------------------------------------------------

banner "5. Scanner data"

if [[ "$DO_DB" != 1 ]]; then
  skip_step "warm scanner data" "--skip-db"
else
  if have grype; then
    run_step "grype db update" grype db update || true
  else
    skip_step "grype db update" "grype not installed"
  fi

  # A filesystem scan is enough to trigger Trivy's initial DB download. The
  # findings themselves are irrelevant here, so discard them rather than
  # dumping a full CVE table into the warm-up log.
  if have trivy; then
    run_step "trivy db download" \
      sh -c 'trivy fs --scanners vuln --no-progress --quiet scenarios/S01-spring-node >/dev/null' || true
  else
    skip_step "trivy db download" "trivy not installed"
  fi

  if have syft; then
    run_step "syft warm" \
      sh -c 'syft scenarios/S01-spring-node -o table >/dev/null' || true
  else
    skip_step "syft warm" "syft not installed"
  fi

  if have snyk; then
    if snyk whoami >/dev/null 2>&1; then
      record PASS "snyk authentication" "authenticated"
      step "snyk authentication"
      echo "   ok (authenticated)"
    else
      step "snyk authentication"
      echo "   not authenticated. Run: snyk auth"
      record SKIP "snyk authentication" "not authenticated"
    fi
  else
    skip_step "snyk authentication" "snyk not installed"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Investigations (optional)
#
# These are the slowest steps. T06 in particular downloads a large NVD dataset
# on its first run, cached under ~/.cache/kcdc-dependency-check/<version>.
# ---------------------------------------------------------------------------

banner "6. Investigations"

if [[ "$DO_INVESTIGATIONS" != 1 ]]; then
  skip_step "investigation baselines" "not requested (--with-investigations)"
else
  # T01 needs an authenticated Snyk CLI.
  if have snyk && snyk whoami >/dev/null 2>&1; then
    run_step "T01 baseline" \
      in_dir investigations/T01-snyk-beyond-sbom ./scripts/baseline.sh || true
  else
    skip_step "T01 baseline" "snyk missing or not authenticated"
  fi

  if [[ "$DOCKER_OK" == 1 ]] && have docker; then
    run_step "T02 baseline S01" \
      in_dir investigations/T02-docker-scout ./scripts/baseline-s01.sh || true
    run_step "T02 baseline S02" \
      in_dir investigations/T02-docker-scout ./scripts/baseline-s02.sh || true
  else
    skip_step "T02 baselines" "docker unavailable"
  fi

  if have trivy; then
    run_step "T03 baseline S01" \
      in_dir investigations/T03-trivy-s01 ./scripts/baseline-s01.sh || true
  else
    skip_step "T03 baseline" "trivy not installed"
  fi

  if have grype; then
    run_step "T04 baseline S02" \
      in_dir investigations/T04-grype-s02 ./scripts/baseline-s02.sh || true
  else
    skip_step "T04 baseline" "grype not installed"
  fi

  if have pip-audit; then
    run_step "T05 baseline S03" \
      in_dir investigations/T05-pip-audit-s03 ./scripts/baseline-s03.sh || true
  else
    skip_step "T05 baseline" "pip-audit not installed"
  fi

  # T06 is the big one: the longest single download in the run.
  if [[ -z "${NVD_API_KEY:-}" ]]; then
    echo
    echo "   note: NVD_API_KEY is not set, so T06 will use Dependency-Check"
    echo "         12.2.2 rather than 13.0.0, and the NVD download will be"
    echo "         slower. See setup/03 ACCOUNTS-AND-KEYS.md"
  fi
  run_step "T06 baseline S04" \
    in_dir investigations/T06-owasp-dependency-check-s04 ./scripts/baseline-s04.sh || true
  run_step "T06 dependency-check S04 (downloads NVD data)" \
    in_dir investigations/T06-owasp-dependency-check-s04 ./scripts/run-dependency-check-s04.sh || true

  run_step "T07 baseline S05" \
    in_dir investigations/T07-npm-audit-s05 ./scripts/baseline-s05.sh || true
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

TOTAL_ELAPSED=$(( $(date +%s) - TOTAL_START ))

banner "Summary"

printf '%s' "$RESULTS" | while IFS='|' read -r status label detail; do
  [[ -z "${status:-}" ]] && continue
  printf '   %-5s %-45s %s\n' "$status" "$label" "$detail"
done

echo
echo "   passed: $PASSED   failed: $FAILED   skipped: $SKIPPED"
printf '   total time: %dm %ds\n' $((TOTAL_ELAPSED / 60)) $((TOTAL_ELAPSED % 60))

echo
if [[ "$DOCKER_OK" == 1 ]]; then
  echo "   Base images:"
  for img in $BASE_IMAGES; do
    if docker image inspect "$img" >/dev/null 2>&1; then
      printf '     %-34s present\n' "$img"
    else
      printf '     %-34s MISSING\n' "$img"
    fi
  done
fi

echo
if [[ "$FAILED" -gt 0 ]]; then
  echo "   $FAILED step(s) failed. The machine is not fully warmed."
  exit 1
fi

if [[ "$SKIPPED" -gt 0 ]]; then
  echo "   No failures. $SKIPPED step(s) were skipped — review the list above"
  echo "   to confirm each skip was intentional."
else
  echo "   All requested steps completed."
fi

echo
echo "   Nothing is left running. To confirm the toolchain independently, see"
echo "   the readiness check at the end of setup/04 BUILDING.md"
