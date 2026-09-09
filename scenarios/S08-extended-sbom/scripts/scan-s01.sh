#!/usr/bin/env bash
# The same two SBOMs for S01's multi-module reactor:
#   standard  cyclonedx-maven-plugin  makeAggregateBom
#   extended  sbom-plus-maven-plugin  scan-aggregate
# S01 resolves from Maven Central into ~/.m2, so no scenario-local repository.
set -euo pipefail
source "$(dirname "$0")/common.sh"
need mvn; need jq

OUT="$RESULTS/s01"; mkdir -p "$OUT"
ensure_plugin

echo
echo "== Standard: CycloneDX Maven plugin, aggregate over the reactor =="
( cd "$S01" && mvn -q "$CDX:makeAggregateBom" -DoutputFormat=json \
    -DoutputDirectory="$OUT" -DoutputName=standard.cdx )
echo "   -> $OUT/standard.cdx.json"

echo
echo "== Extended: SBOM+ scan-aggregate =="
( cd "$S01" && mvn "$PLUS:scan-aggregate" \
    -DsbomPlus.outputFile="$OUT/plus.report.json" \
    -DsbomPlus.sbomOutputFile="$OUT/plus.cdx.json" \
    | grep -E 'WARNING|ERROR|SBOM\+' | tee "$OUT/plus.log" || true )
echo "   -> $OUT/plus.cdx.json  (CycloneDX)"
echo "   -> $OUT/plus.report.json  (scan report)"

echo
echo "===== S01: what each SBOM says ====="
cdx_summary "standard " "$OUT/standard.cdx.json"
cdx_summary "extended " "$OUT/plus.cdx.json"
report_origins "$OUT/plus.report.json"

echo
echo "-- The S01 tracked components, plus the tooling that shaped them --"
echo "standard SBOM:"
cdx_rows "$OUT/standard.cdx.json" '^(jackson-databind|commons-codec|normalizer|maven-shade-plugin|spring-boot-dependencies)$' | sed 's/^/   /'
echo "extended SBOM:"
cdx_rows "$OUT/plus.cdx.json" '^(jackson-databind|commons-codec|normalizer|maven-shade-plugin|spring-boot-dependencies)$' | sed 's/^/   /'
echo "SBOM+ report (module, origin, scope, coordinate, path):"
report_rows "$OUT/plus.report.json" '^(jackson-databind|commons-codec|normalizer|maven-shade-plugin|spring-boot-dependencies)$' | sed 's/^/   /'

echo
echo "-- Components only one of them lists --"
cdx_gav_list "$OUT/standard.cdx.json" > "$OUT/standard.gav.txt"
cdx_gav_list "$OUT/plus.cdx.json"     > "$OUT/plus.gav.txt"
echo "   only in standard : $(comm -23 "$OUT/standard.gav.txt" "$OUT/plus.gav.txt" | tr '\n' ' ')"
echo "   only in extended : $(comm -13 "$OUT/standard.gav.txt" "$OUT/plus.gav.txt" | wc -l | tr -d ' ') (build tooling and the BOM import)"
echo "   in both          : $(comm -12 "$OUT/standard.gav.txt" "$OUT/plus.gav.txt" | wc -l | tr -d ' ')"

echo
echo "-- Unresolved (SBOM+ resolves from repositories, not from the reactor) --"
if [[ "$(jq '[.modules[].unresolved[]]|length' "$OUT/plus.report.json")" == 0 ]]; then
  echo "   none"
else
  jq -r '.modules[] | .module as $m | .unresolved[]
         | "   \($m|split(":")[1]) needs \(.coordinate.groupId):\(.coordinate.artifactId):\(.coordinate.version) (\(.scope)) - \(.reason)"' \
     "$OUT/plus.report.json"
  echo "   To close this gap, install the reactor modules and scan again:"
  echo "     (cd \"$S01\" && mvn -q install -DskipTests) && ./scripts/scan-s01.sh"
fi
