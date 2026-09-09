#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
for cmd in npm node jq tar grep find; do require_command "$cmd"; done
S05="$(resolve_s05)" || { echo "Could not find S05-node-prepack." >&2; echo "Set S05_DIR=/path/to/S05-node-prepack" >&2; exit 1; }
OUT="$ROOT/results/s05/baseline"
mkdir -p "$OUT"
echo "S05: $S05"
echo "Output: $OUT"

echo
echo "== Source package files before build/prepack =="
find "$S05/packages/trace-route-package" \
  -maxdepth 3 -type f \
  -print \
  | sort \
  | tee "$OUT/source-package-files-prepack.txt"

echo
echo "== Build S05 from clean state =="
( cd "$S05"; ./scripts/build.sh ) >"$OUT/build.log" 2>&1
cat "$OUT/build.log"
TGZ="$S05/npm-repo/trace-route-package-1.0.0.tgz"
INSTALLED="$S05/node_modules/trace-route-package"
[[ -f "$TGZ" ]] || { echo "Expected tarball not found: $TGZ" >&2; exit 1; }
[[ -d "$INSTALLED" ]] || { echo "Expected installed package not found: $INSTALLED" >&2; exit 1; }
printf '%s\n' "$TGZ" >"$OUT/tarball-path.txt"
printf '%s\n' "$INSTALLED" >"$OUT/installed-package-path.txt"
echo; echo "== Application dependency declaration =="
cat "$S05/package.json" | tee "$OUT/application-package.json"
echo; echo "== Source package manifest =="
cat "$S05/packages/trace-route-package/package.json" | tee "$OUT/source-package.json"
echo; echo "== Source package files after pack =="
find "$S05/packages/trace-route-package" -maxdepth 3 -type f -print | sort | tee "$OUT/source-package-files.txt"
echo; echo "== Build input =="
cat "$S05/packages/trace-route-package/build-input/route.json" | tee "$OUT/route.json"
echo; echo "== Generator logic =="
grep -nE 'prepack|generate|npm-prepack-generated|dist/index\.js|prepack-evidence\.json|generatedBy' "$S05/packages/trace-route-package/scripts/generate-dist.js" | tee "$OUT/generator-relevant.txt" || true
echo; echo "== npm pack lifecycle evidence =="
grep -E 'prepack|generate-dist|generated dist|npm notice|trace-route-package-1\.0\.0\.tgz' "$S05/trace-output/npm-pack.log" | tee "$OUT/npm-pack-evidence.txt" || true
echo; echo "== Packed tarball contents =="
tar -tzf "$TGZ" | tee "$OUT/tarball-files.txt"
echo; echo "== Packed package.json =="
tar -xOzf "$TGZ" package/package.json | tee "$OUT/tarball-package.json"
echo; echo "== Tarball lifecycle/generator presence =="
{
  echo "prepack declaration:"; tar -xOzf "$TGZ" package/package.json | jq -r '.scripts.prepack // "(none)"'
  echo; echo "generator file in tarball:"; tar -tzf "$TGZ" | grep 'package/scripts/generate-dist.js' || true
  echo; echo "build input in tarball:"; tar -tzf "$TGZ" | grep 'package/build-input/route.json' || true
  echo; echo "generated files in tarball:"; tar -tzf "$TGZ" | grep -E 'package/dist/(index\.js|prepack-evidence\.json)' || true
} | tee "$OUT/tarball-boundary.txt"
echo; echo "== Generated evidence inside tarball =="
tar -xOzf "$TGZ" package/dist/prepack-evidence.json | tee "$OUT/tarball-prepack-evidence.json"
echo; echo "== Installed dependency tree =="
( cd "$S05"; npm ls --all ) | tee "$OUT/npm-ls.txt"
echo; echo "== Installed package files =="
find "$INSTALLED" -maxdepth 3 -type f -print | sort | tee "$OUT/installed-package-files.txt"
echo; echo "== Installed package manifest =="
cat "$INSTALLED/package.json" | tee "$OUT/installed-package.json"
echo; echo "== Installed generated evidence =="
cat "$INSTALLED/dist/prepack-evidence.json" | tee "$OUT/installed-prepack-evidence.json"
echo; echo "== Installed package boundary check =="
{
  echo "generator file:"; find "$INSTALLED" -path '*/scripts/generate-dist.js' -print
  echo "build input:"; find "$INSTALLED" -path '*/build-input/route.json' -print
  echo "generated runtime files:"; find "$INSTALLED/dist" -maxdepth 1 -type f -print | sort
} | tee "$OUT/installed-boundary.txt"
echo; echo "== Runtime module output =="
( cd "$S05"; node - <<'NODE'
const route = require('trace-route-package');
console.log(JSON.stringify(route, null, 2));
NODE
) | tee "$OUT/runtime-module.json"
echo; echo "== npm SBOM baseline =="
( cd "$S05"; npm sbom --sbom-format cyclonedx >"$OUT/npm-sbom.json" )
jq -r '.components[]? | [.name, .version, (.purl // "")] | @tsv' "$OUT/npm-sbom.json" | grep -E 'node-prepack-trace-lab|trace-route-package' | tee "$OUT/npm-sbom-tracers.txt" || true
rm -rf "$OUT/tarball-unpacked"; mkdir -p "$OUT/tarball-unpacked"
tar -xzf "$TGZ" -C "$OUT/tarball-unpacked" --strip-components=1
if command -v syft >/dev/null 2>&1; then
  echo; echo "== Syft isolated installed package baseline =="; syft "dir:$INSTALLED" | tee "$OUT/syft-installed-package.txt"
  echo; echo "== Syft whole project baseline =="; syft "dir:$S05" | tee "$OUT/syft-project.txt"
else
  echo "Syft not installed." | tee "$OUT/syft-installed-package.txt"
  echo "Syft not installed." | tee "$OUT/syft-project.txt"
fi
echo; echo "S05 baseline captured in $OUT"
