#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
for cmd in snyk jq tar grep find; do require_command "$cmd"; done
S05="$(resolve_s05)" || { echo "Could not find S05-node-prepack." >&2; echo "Set S05_DIR=/path/to/S05-node-prepack" >&2; exit 1; }
BASE="$ROOT/results/s05/baseline"
OUT="$ROOT/results/s05/snyk"
mkdir -p "$OUT"
for f in tarball-path.txt installed-package-path.txt; do [[ -f "$BASE/$f" ]] || { echo "Run ./scripts/baseline-s05.sh first." >&2; exit 1; }; done
INSTALLED="$(cat "$BASE/installed-package-path.txt")"
UNPACKED="$BASE/tarball-unpacked"
snyk --version | tee "$OUT/snyk-version.txt"
echo; echo "S05: $S05"; echo "Output: $OUT"
( cd "$S05"; capture_command "1. Snyk npm source test" "$OUT/snyk-source-test.txt" snyk test --print-deps --json-file-output="$OUT/snyk-source-test.json" )
( cd "$S05"; capture_command "2. Snyk npm CycloneDX SBOM" "$OUT/snyk-source-sbom.txt" snyk sbom --format=cyclonedx1.6+json --json-file-output="$OUT/snyk-source-sbom.json" )
( cd "$S05/packages/trace-route-package"; capture_command "3. Snyk project scan of source trace-route-package" "$OUT/snyk-package-source.txt" snyk test --all-projects --json-file-output="$OUT/snyk-package-source.json" )
( cd "$UNPACKED"; capture_command "4. Snyk project scan of unpacked published tarball" "$OUT/snyk-tarball-unpacked.txt" snyk test --all-projects --json-file-output="$OUT/snyk-tarball-unpacked.json" )
( cd "$INSTALLED"; capture_command "5. Snyk project scan of installed package only" "$OUT/snyk-installed-package.txt" snyk test --all-projects --json-file-output="$OUT/snyk-installed-package.json" )
echo; echo "== Search actual Snyk outputs for lifecycle/build evidence =="
TOKENS=('trace-route-package' 'prepack' 'scripts/generate-dist.js' 'npm-prepack-generated' 'prepack-evidence.json' '/hidden/prepack-info')
for token in "${TOKENS[@]}"; do
  echo; echo "-- $token"; found=0
  for f in "$OUT"/*.txt "$OUT"/*.json; do
    [[ -s "$f" ]] || continue
    [[ "$(basename "$f")" == "evidence-token-search.txt" ]] && continue
    if grep -n -F "$token" "$f"; then found=1; fi
  done
  [[ "$found" -eq 1 ]] || echo "(no hits)"
done | tee "$OUT/evidence-token-search.txt"
echo; echo "S05 Snyk probes captured."; echo "Run:"; echo "  ./scripts/compare-s05.sh"
