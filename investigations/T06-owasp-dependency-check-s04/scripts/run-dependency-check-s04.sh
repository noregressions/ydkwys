#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in mvn jq; do
  require_command "$cmd"
done

S04="$(resolve_s04)" || {
  echo "Could not find S04-maven-plugin-hidden-content. Set S04_DIR=/path/to/S04-maven-plugin-hidden-content" >&2
  exit 1
}

BASE="$ROOT/results/s04/baseline"
CTRL="$ROOT/results/s04/controls"
OUT="$ROOT/results/s04/dependency-check"
mkdir -p "$OUT" "$DC_DATA_DIR"

[[ -f "$BASE/app-jar-path.txt" ]] || {
  echo "Run ./scripts/baseline-s04.sh first." >&2
  exit 1
}

APP_JAR="$(cat "$BASE/app-jar-path.txt")"
PLUGIN_JAR="$(cat "$BASE/plugin-jar-path.txt")"
PAYLOAD_JAR="$(cat "$BASE/payload-jar-path.txt")"
LOCAL_REPO="$S04/.maven-repo"

SCAN_ROOT="$ROOT/results/s04/scan-inputs"
FINAL_SCAN="$SCAN_ROOT/final-app"
TOOLING_SCAN="$SCAN_ROOT/plugin-payload"
rm -rf "$SCAN_ROOT"
mkdir -p "$FINAL_SCAN" "$TOOLING_SCAN"

cp "$APP_JAR" "$FINAL_SCAN/"
cp "$PLUGIN_JAR" "$TOOLING_SCAN/"
cp "$PAYLOAD_JAR" "$TOOLING_SCAN/"

run_maven_dc() {
  if [[ -n "${NVD_API_KEY:-}" ]]; then
    mvn "$@" -DnvdApiKeyEnvironmentVariable=NVD_API_KEY
  else
    mvn "$@"
  fi
}

run_dc() {
  local label="$1"
  shift

  local report_dir="$OUT/$label"
  rm -rf "$report_dir"
  mkdir -p "$report_dir"

  echo
  echo "== $label =="

  set +e
  (
    cd "$S04"
    run_maven_dc \
      -Dmaven.repo.local="$LOCAL_REPO" \
      org.owasp:dependency-check-maven:"$DC_VERSION":check \
      -Dformat=JSON \
      -DprettyPrint=true \
      -DfailBuildOnCVSS=11 \
      -DfailOnError=true \
      -DdataDirectory="$DC_DATA_DIR" \
      -DossIndexAnalyzerEnabled=false \
      -DretireJsAnalyzerEnabled=false \
      -DassemblyAnalyzerEnabled=false \
      -Dodc.outputDirectory="$report_dir" \
      "$@"
  ) 2>&1 | tee "$report_dir/run.log"
  local rc=${PIPESTATUS[0]}
  set -e

  printf '%s\n' "$rc" >"$report_dir/exit.txt"

  local report
  report="$(report_path "$report_dir")"

  if [[ -f "$report" ]]; then
    normalise_report "$report" "$report_dir/result"

    echo
    echo "Dependencies: $(cat "$report_dir/result.dependency-count.txt")"
    echo "Vulnerability records: $(cat "$report_dir/result.vulnerability-count.txt")"
    echo "S04 tracked components:"
    if [[ -s "$report_dir/result.tracers.tsv" ]]; then
      cat "$report_dir/result.tracers.tsv"
    else
      echo "(none)"
    fi
  else
    echo
    echo "No JSON report produced."
  fi
}

echo "Dependency-Check Maven plugin: $DC_VERSION"
echo "Data directory: $DC_DATA_DIR"
if [[ -n "${NVD_API_KEY:-}" ]]; then
  echo "NVD API key: supplied via NVD_API_KEY environment variable"
else
  echo "NVD API key: not supplied"
  if [[ "$DC_VERSION" == "12.2.2" ]]; then
    echo "Version selection: using 12.2.2 because 13.0.0 has a known no-key NVD update regression"
  elif [[ "$DC_VERSION" == "13.0.0" ]]; then
    echo "WARNING: Dependency-Check 13.0.0 is known to fail NVD updates without a valid API key"
  fi
fi

echo
echo "== Tool help / resolved version =="
(
  cd "$S04"
  mvn \
    -Dmaven.repo.local="$LOCAL_REPO" \
    org.owasp:dependency-check-maven:"$DC_VERSION":help \
    -Ddetail=false
) | tee "$OUT/version-help.txt"

# A. Default Maven-plugin behavior: scanDependencies=true, scanPlugins=false.
run_dc \
  "default-maven" \
  -Dodc.plugins.scan=false

# B. Explicitly include Maven plugins and their dependencies.
run_dc \
  "plugin-aware-maven" \
  -Dodc.plugins.scan=true

# C. Scan only the final application JAR as a physical archive boundary.
run_dc \
  "final-jar" \
  -Dodc.dependencies.scan=true \
  -Dodc.plugins.scan=false \
  -DscanDirectory="$FINAL_SCAN"

# D. Direct control: show Dependency-Check the plugin and payload JARs themselves.
run_dc \
  "plugin-payload-controls" \
  -Dodc.dependencies.scan=true \
  -Dodc.plugins.scan=false \
  -DscanDirectory="$TOOLING_SCAN"

echo
echo "T06 Dependency-Check probes captured."
echo "Run:"
echo "  ./scripts/compare-s04.sh"
