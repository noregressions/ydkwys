#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
BASE="results/s05/baseline"; SNYK="results/s05/snyk"
if [[ ! -d "$BASE" || ! -d "$SNYK" ]]; then echo "Need both S05 baseline and Snyk results." >&2; echo "Run ./scripts/baseline-s05.sh and ./scripts/run-snyk-s05.sh first." >&2; exit 1; fi
echo "T01 / S05 comparison"; echo "===================="; echo
echo "Tracer:"; echo "  trace-route-package 1.0.0"; echo; echo "Lifecycle evidence:"; echo "  prepack"; echo "  scripts/generate-dist.js"; echo "  dist/index.js"; echo "  dist/prepack-evidence.json"
echo; echo "== Baseline publication evidence =="
for f in "$BASE/application-package.json" "$BASE/source-package.json" "$BASE/source-package-files.txt" "$BASE/generator-relevant.txt" "$BASE/npm-pack-evidence.txt" "$BASE/tarball-files.txt" "$BASE/tarball-package.json" "$BASE/tarball-boundary.txt" "$BASE/tarball-prepack-evidence.json" "$BASE/npm-ls.txt" "$BASE/installed-package-files.txt" "$BASE/installed-package.json" "$BASE/installed-prepack-evidence.json" "$BASE/runtime-module.json" "$BASE/npm-sbom-tracers.txt"; do
  echo; echo "-- $f"; grep -E 'trace-route-package|prepack|generate-dist|npm-prepack-generated|prepack-evidence|/hidden/prepack-info|dist/index\.js' "$f" || echo "(no matching evidence)"
done
echo; echo "== Snyk command exit codes =="
for f in "$SNYK"/*.exit; do [[ -e "$f" ]] || continue; printf '%-52s %s\n' "$(basename "${f%.exit}")" "$(cat "$f")"; done
echo; echo "== Snyk package identity hits =="
for f in "$SNYK"/*.txt "$SNYK"/*.json; do [[ -s "$f" ]] || continue; [[ "$(basename "$f")" == "evidence-token-search.txt" ]] && continue; echo; echo "-- $f"; grep -E 'trace-route-package' "$f" || echo "(no package identity hits)"; done
echo; echo "== Snyk lifecycle/build evidence hits =="
for token in 'prepack' 'scripts/generate-dist.js' 'npm-prepack-generated' 'prepack-evidence.json' '/hidden/prepack-info'; do
  echo; echo "-- $token"; found=0
  for f in "$SNYK"/*.txt "$SNYK"/*.json; do [[ -s "$f" ]] || continue; [[ "$(basename "$f")" == "evidence-token-search.txt" ]] && continue; if grep -n -F "$token" "$f"; then found=1; fi; done
  [[ "$found" -eq 1 ]] || echo "(no hits)"
done
echo; echo "== Snyk SBOM tracked components =="
if [[ -s "$SNYK/snyk-source-sbom.json" ]]; then jq -r '.components[]? | [.name, .version, (.purl // "")] | @tsv' "$SNYK/snyk-source-sbom.json" | grep -E 'node-prepack-trace-lab|trace-route-package' || echo "(no tracked components)"; fi
echo; echo "== Snyk SBOM relationships involving tracked components =="
if [[ -s "$SNYK/snyk-source-sbom.json" ]]; then jq -r '.dependencies[]? | select((.ref // "" | test("trace-route-package|node-prepack-trace-lab"; "i")) or ((.dependsOn // []) | join(" ") | test("trace-route-package"; "i"))) | [.ref, ((.dependsOn // []) | join(","))] | @tsv' "$SNYK/snyk-source-sbom.json" || true; fi
echo; echo "Interpretation questions:"
echo "  1. Does Snyk identify trace-route-package from the application npm model?"
echo "  2. Does the Snyk SBOM preserve application -> trace-route-package?"
echo "  3. Does either Snyk view expose that npm prepack executed?"
echo "  4. Does either view identify scripts/generate-dist.js as the generator?"
echo "  5. Does either view explain that dist/index.js and prepack-evidence.json were generated?"
echo "  6. Can Snyk scan the source package on its own, and if so does it surface lifecycle scripts?"
echo "  7. Can Snyk scan the unpacked published tarball or installed package on its own?"
echo "  8. What publication history exists in npm pack evidence but is absent from Snyk's dependency inventory?"
