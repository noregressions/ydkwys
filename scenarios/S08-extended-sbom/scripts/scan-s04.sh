#!/usr/bin/env bash
# Two SBOMs of S04, from the same POM, with no changes to that POM:
#   standard  cyclonedx-maven-plugin  makeBom
#   extended  sbom-plus-maven-plugin  scan
set -euo pipefail
source "$(dirname "$0")/common.sh"
need mvn; need jq

REPO="$S04/.maven-repo"
INJECTOR="$REPO/dev/noregressions/trace/trace-injector-maven-plugin/1.0.0/trace-injector-maven-plugin-1.0.0.jar"
[[ -f "$INJECTOR" ]] || {
  echo "S04 is not built: $INJECTOR is missing." >&2
  echo "Run  (cd \"$S04\" && ./scripts/build.sh)  first." >&2
  exit 1
}

OUT="$RESULTS/s04"; mkdir -p "$OUT"
ensure_plugin "$REPO"

echo
echo "== Standard: CycloneDX Maven plugin (project dependency model) =="
( cd "$S04" && mvn -q -Dmaven.repo.local="$REPO" \
    "$CDX:makeBom" -DoutputFormat=json \
    -DoutputDirectory="$OUT" -DoutputName=standard.cdx )
echo "   -> $OUT/standard.cdx.json"

echo
echo "== Extended: SBOM+ (main graph + build tooling + BOM imports) =="
( cd "$S04" && mvn -q -Dmaven.repo.local="$REPO" \
    "$PLUS:scan" \
    -DsbomPlus.outputFile="$OUT/plus.report.json" \
    -DsbomPlus.sbomOutputFile="$OUT/plus.cdx.json" )
echo "   -> $OUT/plus.cdx.json  (CycloneDX)"
echo "   -> $OUT/plus.report.json  (scan report: origin + broughtInBy)"

echo
echo "===== S04: what each SBOM says ====="
cdx_summary "standard " "$OUT/standard.cdx.json"
cdx_summary "extended " "$OUT/plus.cdx.json"
report_origins "$OUT/plus.report.json"

echo
echo "-- The S04 tracked components --"
echo "standard SBOM:"
cdx_rows "$OUT/standard.cdx.json" 'trace-injector|trace-route-payload' | sed 's/^/   /'
[[ -n "$(cdx_rows "$OUT/standard.cdx.json" 'trace-injector|trace-route-payload')" ]] || echo "   (absent)"
echo "extended SBOM:"
cdx_rows "$OUT/plus.cdx.json" 'trace-injector|trace-route-payload' | sed 's/^/   /'
echo "SBOM+ report (origin, scope, path):"
report_rows "$OUT/plus.report.json" '^(trace-injector-maven-plugin|trace-route-payload)$' | sed 's/^/   /'

echo
echo "-- Build tooling the extended SBOM records that the standard one cannot (first 10) --"
jq -r '.modules[].dependencies[] | select(.origin=="BUILD_TOOLING" and (.broughtInBy|length)==0)
       | "\(.coordinate.artifactId):\(.coordinate.version)"' "$OUT/plus.report.json" \
  | sort -u | head -10 | sed 's/^/   /'
echo "   ... $(jq '[.modules[].dependencies[] | select(.origin=="BUILD_TOOLING")] | length' "$OUT/plus.report.json") BUILD_TOOLING rows in total"
