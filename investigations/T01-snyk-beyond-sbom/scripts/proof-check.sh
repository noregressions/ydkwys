#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

pass=0
fail=0

ok() {
  printf 'PASS  %s\n' "$1"
  pass=$((pass + 1))
}

bad() {
  printf 'FAIL  %s\n' "$1"
  fail=$((fail + 1))
}

contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if [[ -f "$file" ]] && grep -Fq "$pattern" "$file"; then
    ok "$label"
  else
    bad "$label"
  fi
}

not_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if [[ -f "$file" ]] && ! grep -Fq "$pattern" "$file"; then
    ok "$label"
  else
    bad "$label"
  fi
}

json_component() {
  local file="$1"
  local name="$2"
  local version="$3"
  local label="$4"
  if [[ -f "$file" ]] && jq -e \
    --arg n "$name" --arg v "$version" \
    '.components[]? | select(.name == $n and .version == $v)' \
    "$file" >/dev/null 2>&1; then
    ok "$label"
  else
    bad "$label"
  fi
}

echo "T01 proof check"
echo "==============="
echo

# S01
contains results/s01/baseline/maven-normalizer-codec.txt \
  'commons-codec:commons-codec:jar:1.17.1' \
  'S01 Maven normalizer resolves codec 1.17.1'
contains results/s01/baseline/maven-service-codec.txt \
  'commons-codec:commons-codec:jar:1.18.0' \
  'S01 service resolves codec 1.18.0'
contains results/s01/baseline/syft-service-jar.txt \
  'commons-codec                   1.17.1' \
  'S01 Syft final JAR sees shaded codec 1.17.1'
contains results/s01/baseline/syft-service-jar.txt \
  'commons-codec                   1.18.0' \
  'S01 Syft final JAR sees intact codec 1.18.0'
contains results/s01/snyk/snyk-maven-test.txt \
  'commons-codec:commons-codec @ 1.17.1' \
  'S01 Snyk Maven sees codec 1.17.1'
contains results/s01/snyk/snyk-maven-test.txt \
  'commons-codec:commons-codec @ 1.18.0' \
  'S01 Snyk Maven sees codec 1.18.0'
contains results/s01/snyk/snyk-frontend-test.txt \
  'lodash @ 4.17.21' \
  'S01 Snyk npm sees lodash before bundling'
contains results/s01/snyk/snyk-frontend-dist.txt \
  'No supported files found' \
  'S01 bundled frontend has no supported Snyk project'
contains results/s01/snyk/snyk-unmanaged-normalizer.txt \
  ' @ unknown' \
  'S01 shaded normalizer is unknown to Snyk unmanaged scan'
not_contains results/s01/snyk/snyk-unmanaged-service-unpacked.txt \
  'commons-codec:commons-codec @ 1.17.1' \
  'S01 unpacked Snyk artefact view does not recover shaded codec 1.17.1'
contains results/s01/snyk/snyk-unmanaged-service-unpacked.txt \
  'commons-codec:commons-codec @ 1.18.0' \
  'S01 unpacked Snyk artefact view recovers intact codec 1.18.0'

# S02
contains results/s02/baseline/maven-debug-plugin-realm.txt \
  'org.mvnpm:lodash-es:jar:4.17.21' \
  'S02 Maven plugin ClassRealm contains lodash-es'
not_contains results/s02/snyk/snyk-maven-test.txt \
  'lodash-es' \
  'S02 Snyk Maven app model omits lodash-es'
contains results/s02/snyk/snyk-unmanaged-war-unpacked.txt \
  'org.apache.commons:commons-lang3 @ 3.18.0' \
  'S02 unpacked WAR recovers commons-lang3'
not_contains results/s02/snyk/snyk-unmanaged-war-unpacked.txt \
  'lodash-es' \
  'S02 unpacked WAR does not recover bundled lodash-es'

# S03
contains results/s03/baseline/reportkit-metadata.txt \
  'Requires-Dist: tracehook-demo==1.0.0' \
  'S03 reportkit metadata introduces tracehook-demo'
contains results/s03/baseline/tracehook-pyproject.toml \
  'build-backend = "tracehook_backend"' \
  'S03 sdist declares tracehook backend'
contains results/s03/baseline/pip-build-evidence.txt \
  'Building wheel for tracehook-demo' \
  'S03 pip executes wheel build'
contains results/s03/baseline/build-hook.json \
  '"generatedBy": "tracehook_backend.build_wheel"' \
  'S03 generated marker records build_wheel'
contains results/s03/snyk/snyk-pip-test.txt \
  'tracehook-demo @ 1.0.0' \
  'S03 Snyk recovers transitive tracehook-demo'
json_component results/s03/snyk/snyk-pip-sbom.json \
  'tracehook-demo' '1.0.0' \
  'S03 Snyk SBOM contains tracehook-demo'
not_contains results/s03/snyk/snyk-pip-test.json \
  'tracehook_backend' \
  'S03 Snyk test omits backend execution identity'
not_contains results/s03/snyk/snyk-pip-sbom.json \
  'build-hook.json' \
  'S03 Snyk SBOM omits generated-file lineage'

# S04
contains results/baseline/maven-resolve-plugins.txt \
  'trace-route-payload' \
  'S04 Maven plugin resolution contains payload'
not_contains results/snyk/snyk-test.txt \
  'trace-route-payload' \
  'S04 Snyk Maven scan omits plugin payload'
not_contains results/snyk/snyk-sbom.json \
  'trace-route-payload' \
  'S04 Snyk SBOM omits plugin payload'
contains results/snyk/snyk-unmanaged-jar.txt \
  ' @ unknown' \
  'S04 final custom JAR is unknown to Snyk unmanaged scan'

# S05
contains results/s05/baseline/npm-pack-evidence.txt \
  'npm notice run trace-route-package@1.0.0 prepack' \
  'S05 npm pack records prepack execution'
contains results/s05/baseline/npm-pack-evidence.txt \
  'npm notice run node scripts/generate-dist.js' \
  'S05 npm pack records generator execution'
contains results/s05/baseline/tarball-prepack-evidence.json \
  '"generatedBy": "npm lifecycle prepack -> scripts/generate-dist.js"' \
  'S05 tarball carries generated evidence'
contains results/s05/snyk/snyk-source-test.txt \
  'trace-route-package @ 1.0.0' \
  'S05 Snyk identifies trace-route-package'
json_component results/s05/snyk/snyk-source-sbom.json \
  'trace-route-package' '1.0.0' \
  'S05 Snyk SBOM contains trace-route-package'
not_contains results/s05/snyk/snyk-source-test.json \
  'scripts/generate-dist.js' \
  'S05 Snyk dependency result omits generator'
not_contains results/s05/snyk/snyk-source-sbom.json \
  'prepack-evidence.json' \
  'S05 Snyk SBOM omits generated-file lineage'

echo
echo "Passed: $pass"
echo "Failed: $fail"

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
