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

echo "T03 Trivy proof check"
echo "====================="

contains results/s01/baseline/maven-normalizer.txt \
  'commons-codec:commons-codec:jar:1.17.1:compile' \
  'Maven normalizer model contains codec 1.17.1'

contains results/s01/baseline/maven-service.txt \
  'commons-codec:commons-codec:jar:1.18.0:compile (version managed from 1.17.1)' \
  'Maven service model resolves codec to 1.18.0'

contains results/s01/baseline/npm-lodash.txt \
  'lodash@4.17.21' \
  'npm model contains lodash 4.17.21'

contains results/s01/trivy/normalizer-pom.tracers.txt \
  $'commons-codec\t1.17.1' \
  'Trivy identifies codec 1.17.1 from normalizer POM'

contains results/s01/trivy/frontend-lock.tracers.txt \
  $'lodash\t4.17.21' \
  'Trivy identifies lodash from package-lock'

contains results/s01/trivy/frontend-lock.vulns.txt \
  'CVE-2026-4800' \
  'Trivy reports lodash vulnerability from package-lock'

contains results/s01/trivy/normalizer-jar.tracers.txt \
  $'commons-codec\t1.17.1' \
  'Trivy identifies codec from shaded normalizer JAR'

not_contains results/s01/trivy/normalizer-stripped-jar.tracers.txt \
  'commons-codec' \
  'Trivy loses codec identity after Maven metadata removal'

contains results/s01/trivy/normalizer-stripped-jar.tracers.txt \
  $'normalizer\t1.0.0' \
  'Trivy still identifies normalizer after codec metadata removal'

contains results/s01/trivy/service-jar.tracers.txt \
  $'commons-codec\t1.17.1' \
  'Trivy sees embedded codec 1.17.1 in service JAR'

contains results/s01/trivy/service-jar.tracers.txt \
  $'commons-codec\t1.18.0' \
  'Trivy sees intact codec 1.18.0 in service JAR'

contains results/s01/trivy/service-jar.tracers.txt \
  $'jackson-databind\t2.19.4' \
  'Trivy sees Jackson 2.19.4 in service JAR'

contains results/s01/trivy/service-jar.vulns.txt \
  'CVE-2026-54512' \
  'Trivy reports Jackson CVEs from service JAR'

not_contains results/s01/trivy/frontend-dist.tracers.txt \
  'lodash' \
  'Trivy does not recover lodash from Vite bundle'

contains results/s01/trivy/container-image.tracers.txt \
  $'commons-codec\t1.17.1' \
  'Trivy sees codec 1.17.1 in final image'

contains results/s01/trivy/container-image.tracers.txt \
  $'commons-codec\t1.18.0' \
  'Trivy sees codec 1.18.0 in final image'

contains results/s01/trivy/container-image.tracers.txt \
  $'jackson-databind\t2.19.4' \
  'Trivy sees Jackson in final image'

not_contains results/s01/trivy/container-image.tracers.txt \
  'lodash' \
  'Trivy does not recover lodash from final image'

contains results/s01/trivy/container-image.vulns.txt \
  'CVE-2026-59888' \
  'Trivy reports Jackson CVEs from final image'

echo
echo "Passed: $pass"
echo "Failed: $fail"

[[ "$fail" -eq 0 ]]
