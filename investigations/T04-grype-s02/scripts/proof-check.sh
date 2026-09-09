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

line_count_is() {
  local file="$1" expected="$2" label="$3"
  if [[ -f "$file" ]] && [[ "$(wc -l <"$file" | tr -d ' ')" == "$expected" ]]; then
    ok "$label"
  else
    bad "$label"
  fi
}

empty_file() {
  local file="$1" label="$2"
  if [[ -f "$file" ]] && [[ ! -s "$file" ]]; then
    ok "$label"
  else
    bad "$label"
  fi
}

echo "T04 Grype proof check"
echo "====================="

contains results/s02/baseline/maven-app-tree.txt \
  'jakarta.platform:jakarta.jakartaee-web-api:jar:11.0.0:provided' \
  'Maven application model contains Jakarta EE API as provided'

contains results/s02/baseline/maven-app-tree.txt \
  'org.apache.commons:commons-lang3:jar:3.18.0:compile' \
  'Maven application model contains commons-lang3 3.18.0'

contains results/s02/baseline/maven-plugin-tracers.txt \
  'org.mvnpm:lodash-es:jar:4.17.21' \
  'Maven plugin realm contains lodash-es 4.17.21'

contains results/s02/baseline/war-tracers.txt \
  'WEB-INF/lib/commons-lang3-3.18.0.jar' \
  'WAR physically contains commons-lang3'

not_contains results/s02/baseline/war-tracers.txt \
  'lodash-es' \
  'WAR does not contain a lodash-es package boundary'

contains results/s02/baseline/syft-json-tracers.txt \
  $'commons-lang3\t3.18.0' \
  'Final-image Syft inventory identifies commons-lang3'

not_contains results/s02/baseline/syft-json-tracers.txt \
  'lodash-es' \
  'Final-image Syft inventory does not identify lodash-es'

contains results/s02/baseline/syft-json-package-count.txt \
  '589' \
  'Syft JSON contains 589 package artifacts'

contains results/s02/baseline/cdx-component-count.txt \
  '6014' \
  'CycloneDX document contains 6014 components'

contains results/s02/grype/grype-db-status.txt \
  'Status:    valid' \
  'Grype vulnerability database is valid'

line_count_is results/s02/grype/direct-image.matches.tsv \
  169 \
  'Direct image scan has 169 unique vulnerability matches'

line_count_is results/s02/grype/syft-json.matches.tsv \
  169 \
  'Syft JSON scan has 169 unique vulnerability matches'

line_count_is results/s02/grype/cyclonedx.matches.tsv \
  169 \
  'CycloneDX scan has 169 unique vulnerability matches'

empty_file results/s02/grype/diff-direct-vs-syft-json.txt \
  'Direct image and Syft JSON match sets are identical'

empty_file results/s02/grype/diff-direct-vs-cyclonedx.txt \
  'Direct image and CycloneDX match sets are identical'

empty_file results/s02/grype/diff-syft-json-vs-cyclonedx.txt \
  'Syft JSON and CycloneDX match sets are identical'

empty_file results/s02/grype/purl-commons-lang3.matches.tsv \
  'commons-lang3 PURL control has no vulnerability match'

empty_file results/s02/grype/purl-lodash-es.matches.tsv \
  'lodash-es PURL control has no vulnerability match'

contains results/s02/grype/direct-image.matches.tsv \
  'GHSA-xwmg-2g98-w7v9' \
  'Direct image scan contains Nimbus JOSE JWT finding'

contains results/s02/grype/direct-image.matches.tsv \
  'GHSA-r7wm-3cxj-wff9' \
  'Direct image scan contains Jackson Core finding'

echo
echo "Passed: $pass"
echo "Failed: $fail"

[[ "$fail" -eq 0 ]]
