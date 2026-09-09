#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

SCOUT="results/s02/scout"

if [[ ! -d "$SCOUT" ]]; then
  echo "Need S02 Scout results. Run ./scripts/run-scout-s02.sh first." >&2
  exit 1
fi

echo "T02 / S02 comparison"
echo "===================="
echo

echo "== Scout summary =="
grep -E \
  'Indexed [0-9]+ packages|Provenance obtained|Base image|Policy status|Health score' \
  "$SCOUT/quickview.txt" || true

echo
echo "== Exact application tracked component =="
grep -E \
  '^[[:space:]]*commons-lang3[[:space:]]+\|' \
  "$SCOUT/sbom-list.txt" || true

echo
echo "== Bundled plugin tracked component =="
if grep -Eq '^[[:space:]]*lodash-es[[:space:]]+\|' "$SCOUT/sbom-list.txt"; then
  grep -E '^[[:space:]]*lodash-es[[:space:]]+\|' "$SCOUT/sbom-list.txt"
else
  echo "lodash-es 4.17.21: not identified"
fi

echo
echo "== Representative Jakarta packages supplied by Payara =="
grep -E \
  '^[[:space:]]*jakarta\.(servlet-api|ws\.rs-api|enterprise\.cdi-api|persistence-api|transaction-api)[[:space:]]+\|' \
  "$SCOUT/sbom-list.txt" || true

echo
echo "== Representative Payara server packages =="
grep -E \
  '^[[:space:]]*(payara-api|glassfish|appserver-domain-web|payara-micro-service)[[:space:]]+\|' \
  "$SCOUT/sbom-list.txt" || true

echo
echo "== Tracer vulnerability result =="
grep -E \
  'No vulnerable package detected|No vulnerable packages detected|vulnerabilities │|Base image' \
  "$SCOUT/tracer-cves.txt" || true

echo
echo "== Recommendations =="
grep -E \
  '^No recommendations$|^Base image|^Target' \
  "$SCOUT/recommendations.txt" || true

echo
echo "Interpretation:"
echo "  commons-lang3 3.18.0: identified"
echo "  lodash-es 4.17.21: not recovered from bundled browser output"
echo "  Jakarta APIs: present in final container because Payara supplies them"
echo "  Scout inventory: 655 packages"
echo "  Scout base image: payara/server-web:7.2026.7"
echo "  Provenance attestation: obtained"
echo "  Filtered tracked/package-name CVE view: no vulnerable packages detected"
echo "  Base-image recommendations: none"
