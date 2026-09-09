#!/usr/bin/env bash
# Re-runs both scans and asserts the claims the lesson makes still hold.
set -uo pipefail
source "$(dirname "$0")/common.sh"
need mvn; need jq

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1" >&2; }
check() { if "$@" >/dev/null 2>&1; then return 0; else return 1; fi; }

echo "S08 extended-SBOM proof check"
echo "============================="

"$ROOT/scripts/scan-s04.sh" >/dev/null 2>&1 || { echo "scan-s04.sh failed (is S04 built?)" >&2; exit 1; }
"$ROOT/scripts/scan-s01.sh" >/dev/null 2>&1 || { echo "scan-s01.sh failed" >&2; exit 1; }

S4="$RESULTS/s04"; S1="$RESULTS/s01"

# --- S04 -------------------------------------------------------------------
[[ "$(jq '.components|length' "$S4/standard.cdx.json")" == 0 ]] \
  && pass "S04 standard SBOM has zero components" \
  || fail "S04 standard SBOM has zero components"

jq -e '.components[] | select(.name=="trace-injector-maven-plugin" and (.purl|endswith("?type=maven-plugin")) and .scope=="excluded")' "$S4/plus.cdx.json" >/dev/null \
  && pass "S04 extended SBOM lists trace-injector-maven-plugin as an excluded maven-plugin" \
  || fail "S04 extended SBOM lists trace-injector-maven-plugin as an excluded maven-plugin"

jq -e '.components[] | select(.name=="trace-route-payload" and .scope=="excluded")' "$S4/plus.cdx.json" >/dev/null \
  && pass "S04 extended SBOM lists trace-route-payload" \
  || fail "S04 extended SBOM lists trace-route-payload"

jq -e '.modules[].dependencies[] | select(.coordinate.artifactId=="trace-route-payload" and .origin=="BUILD_TOOLING" and (.broughtInBy|map(.artifactId)) == ["trace-injector-maven-plugin"])' "$S4/plus.report.json" >/dev/null \
  && pass "S04 report attributes trace-route-payload to trace-injector-maven-plugin" \
  || fail "S04 report attributes trace-route-payload to trace-injector-maven-plugin"

[[ "$(jq '[.modules[].dependencies[] | select(.origin!="BUILD_TOOLING")] | length' "$S4/plus.report.json")" == 0 ]] \
  && pass "S04 report: every row is BUILD_TOOLING (the app declares no dependencies)" \
  || fail "S04 report: every row is BUILD_TOOLING (the app declares no dependencies)"

[[ "$(jq '[.components[] | select(.scope!="excluded")] | length' "$S4/plus.cdx.json")" == 0 ]] \
  && pass "S04 extended SBOM marks every component excluded (nothing here ships)" \
  || fail "S04 extended SBOM marks every component excluded (nothing here ships)"

# --- S01 -------------------------------------------------------------------
jq -e '.components[] | select(.name=="jackson-databind" and .scope=="required")' "$S1/standard.cdx.json" >/dev/null \
  && pass "S01 standard SBOM lists jackson-databind as required" \
  || fail "S01 standard SBOM lists jackson-databind as required"

jq -e '.components[] | select(.name=="jackson-databind" and .scope=="required")' "$S1/plus.cdx.json" >/dev/null \
  && pass "S01 extended SBOM lists jackson-databind as required" \
  || fail "S01 extended SBOM lists jackson-databind as required"

jq -e '.components[] | select(.name=="maven-shade-plugin")' "$S1/standard.cdx.json" >/dev/null \
  && fail "S01 standard SBOM does NOT list maven-shade-plugin" \
  || pass "S01 standard SBOM does NOT list maven-shade-plugin"

jq -e '.components[] | select(.name=="maven-shade-plugin" and .scope=="excluded")' "$S1/plus.cdx.json" >/dev/null \
  && pass "S01 extended SBOM lists maven-shade-plugin as excluded build tooling" \
  || fail "S01 extended SBOM lists maven-shade-plugin as excluded build tooling"

jq -e '.components[] | select(.name=="spring-boot-dependencies" and (.purl|endswith("?type=pom")))' "$S1/plus.cdx.json" >/dev/null \
  && pass "S01 extended SBOM records the spring-boot-dependencies BOM import (type=pom)" \
  || fail "S01 extended SBOM records the spring-boot-dependencies BOM import (type=pom)"

jq -e '.modules[].dependencies[] | select(.coordinate.artifactId=="jackson-databind" and .origin=="BUILD_TOOLING")' "$S1/plus.report.json" >/dev/null \
  && pass "S01 report: jackson-databind also appears as BUILD_TOOLING (via spring-boot-maven-plugin)" \
  || fail "S01 report: jackson-databind also appears as BUILD_TOOLING (via spring-boot-maven-plugin)"

[[ "$(jq '[.modules[].dependencies[] | select(.origin=="BUILD_TOOLING")] | length' "$S1/plus.report.json")" -gt "$(jq '[.modules[].dependencies[] | select(.origin=="MAIN_BUILD")] | length' "$S1/plus.report.json")" ]] \
  && pass "S01 report: more build-tooling rows than main-graph rows" \
  || fail "S01 report: more build-tooling rows than main-graph rows"

echo
echo "Passed: $PASS"
echo "Failed: $FAIL"
(( FAIL == 0 ))
