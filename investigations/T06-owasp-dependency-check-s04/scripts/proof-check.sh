#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

pass=0
fail=0

ok()  { printf 'PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL  %s\n' "$1"; fail=$((fail+1)); }

contains() {
  local file="$1" pattern="$2" label="$3"
  if [[ -f "$file" ]] && grep -Fq "$pattern" "$file"; then
    ok "$label"
  else
    bad "$label"
  fi
}

not_contains() {
  local file="$1" pattern="$2" label="$3"
  if [[ -f "$file" ]] && ! grep -Fq "$pattern" "$file"; then
    ok "$label"
  else
    bad "$label"
  fi
}

equals() {
  local file="$1" expected="$2" label="$3"
  if [[ -f "$file" ]] && [[ "$(tr -d '\r\n' < "$file")" == "$expected" ]]; then
    ok "$label"
  else
    bad "$label"
  fi
}

echo "T06 Dependency-Check proof check"
echo "================================"

contains results/s04/baseline/maven-app-tree.txt \
  'dev.noregressions.trace:maven-plugin-hidden-content:jar:1.0.0' \
  'Application dependency tree captured'

not_contains results/s04/baseline/maven-app-tree.txt \
  'trace-route-payload' \
  'Application dependency tree omits plugin payload'

contains results/s04/baseline/maven-plugin-resolution.txt \
  'trace-injector-maven-plugin' \
  'Plugin dependency model contains trace-injector'

contains results/s04/baseline/maven-plugin-resolution.txt \
  'trace-route-payload' \
  'Plugin dependency model contains trace-route-payload'

contains results/s04/baseline/maven-plugin-realm.txt \
  'Included: dev.noregressions.trace:trace-injector-maven-plugin:jar:1.0.0' \
  'Plugin execution realm contains trace-injector'

contains results/s04/baseline/maven-plugin-realm.txt \
  'Included: dev.noregressions.trace:trace-route-payload:jar:1.0.0' \
  'Plugin execution realm contains trace-route-payload'

contains results/s04/baseline/app-jar-tracers.txt \
  'GeneratedTraceRoute.class' \
  'Final JAR contains generated route class'

contains results/s04/baseline/app-jar-tracers.txt \
  'META-INF/services/dev.noregressions.trace.s04.TraceRoute' \
  'Final JAR contains generated ServiceLoader metadata'

contains results/s04/baseline/generated-route-javap.txt \
  '/hidden/build-info' \
  'Final JAR bytecode contains hidden route'

contains results/s04/baseline/generated-route-javap.txt \
  'trace-route-payload' \
  'Final JAR bytecode retains payload provenance string'

contains results/s04/baseline/generated-route-javap.txt \
  'trace-injector-maven-plugin' \
  'Final JAR bytecode retains plugin provenance string'

equals results/s04/dependency-check/default-maven/result.dependency-count.txt \
  '0' \
  'Default Maven scan has zero dependencies'

equals results/s04/dependency-check/default-maven/result.vulnerability-count.txt \
  '0' \
  'Default Maven scan has zero vulnerability records'

not_contains results/s04/dependency-check/default-maven/result.tracers.tsv \
  'trace-injector-maven-plugin' \
  'Default Maven scan omits trace-injector'

not_contains results/s04/dependency-check/default-maven/result.tracers.tsv \
  'trace-route-payload' \
  'Default Maven scan omits trace-route-payload'

equals results/s04/dependency-check/plugin-aware-maven/result.dependency-count.txt \
  '167' \
  'Plugin-aware Maven scan has 167 dependencies'

equals results/s04/dependency-check/plugin-aware-maven/result.vulnerability-count.txt \
  '78' \
  'Plugin-aware Maven scan has 78 vulnerability records'

contains results/s04/dependency-check/plugin-aware-maven/result.tracers.tsv \
  'trace-injector-maven-plugin-1.0.0.jar' \
  'Plugin-aware scan identifies trace-injector'

contains results/s04/dependency-check/plugin-aware-maven/result.tracers.tsv \
  'trace-route-payload-1.0.0.jar' \
  'Plugin-aware scan identifies trace-route-payload'

equals results/s04/dependency-check/final-jar/result.dependency-count.txt \
  '1' \
  'Final JAR scan has one dependency identity'

contains results/s04/dependency-check/final-jar/result.tracers.tsv \
  'maven-plugin-hidden-content-1.0.0.jar' \
  'Final JAR scan identifies application archive'

not_contains results/s04/dependency-check/final-jar/result.tracers.tsv \
  'trace-injector-maven-plugin' \
  'Final JAR scan does not reconstruct trace-injector identity'

not_contains results/s04/dependency-check/final-jar/result.tracers.tsv \
  'trace-route-payload' \
  'Final JAR scan does not reconstruct trace-route-payload identity'

equals results/s04/dependency-check/plugin-payload-controls/result.dependency-count.txt \
  '2' \
  'Direct plugin/payload control has two dependency identities'

contains results/s04/dependency-check/plugin-payload-controls/result.tracers.tsv \
  'trace-injector-maven-plugin-1.0.0.jar' \
  'Direct control identifies trace-injector'

contains results/s04/dependency-check/plugin-payload-controls/result.tracers.tsv \
  'trace-route-payload-1.0.0.jar' \
  'Direct control identifies trace-route-payload'

equals results/s04/dependency-check/plugin-payload-controls/result.vulnerability-count.txt \
  '0' \
  'Controlled packages have no vulnerability matches'

echo
echo "Passed: $pass"
echo "Failed: $fail"

[[ "$fail" -eq 0 ]]
