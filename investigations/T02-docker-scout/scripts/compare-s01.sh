#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BASE="results/s01/baseline"
SCOUT="results/s01/scout"

if [[ ! -d "$BASE" || ! -d "$SCOUT" ]]; then
  echo "Need both S01 baseline and Scout results." >&2
  exit 1
fi

echo "T02 / S01 comparison"
echo "===================="
echo

echo "== Scout summary =="
grep -E \
  'Indexed [0-9]+ packages|Provenance obtained|Base image|Policy status|Health score|vulnerabilities|packages' \
  "$SCOUT/quickview.txt" || true

echo
echo "== Tracer identities from final image =="
cat "$SCOUT/tracer-packages.txt" || true

echo
echo "== Tracer vulnerability summary =="
grep -E \
  'Detected [0-9]+ vulnerable package|vulnerabilities|CRITICAL|HIGH|MEDIUM|LOW|jackson-databind|commons-codec|normalizer|lodash' \
  "$SCOUT/tracer-cves.txt" || true

echo
echo "Interpretation questions:"
echo "  1. Does Scout identify jackson-databind 2.19.4?"
echo "  2. Does Scout identify intact commons-codec 1.18.0?"
echo "  3. Does Scout identify shaded commons-codec 1.17.1?"
echo "  4. Does Scout identify normalizer 1.0.0?"
echo "  5. Does Scout recover lodash 4.17.21 from the Vite bundle?"
echo "  6. How many total packages does Scout index in the final image?"
echo "  7. What base image does Scout infer?"
echo "  8. Does Scout obtain provenance from an attestation?"
echo "  9. What vulnerability intelligence does Scout attach to the tracked packages?"
echo " 10. How does this final-image view differ from Maven/npm, Syft and Snyk?"
