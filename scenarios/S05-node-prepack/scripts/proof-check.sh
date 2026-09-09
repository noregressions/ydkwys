#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")/.."

TARBALL="npm-repo/trace-route-package-1.0.0.tgz"
PACKAGE_DIR="packages/trace-route-package"
INSTALLED_DIR="node_modules/trace-route-package"
PROOF_PORT="${PROOF_PORT:-18085}"

PASS=0
FAIL=0
WARN=0

pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1" >&2; }
warn() { WARN=$((WARN + 1)); printf 'WARN: %s\n' "$1"; }

need() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "required command available: $1"
  else
    fail "required command missing: $1"
  fi
}

cleanup_runtime() {
  ./scripts/stop.sh >/dev/null 2>&1 || true
}
trap cleanup_runtime EXIT

echo "S05 proof check"
echo "==============="
echo

for cmd in node npm tar curl grep find; do
  need "$cmd"
done

if (( FAIL > 0 )); then
  echo
  echo "Cannot continue without required tools."
  exit 1
fi

cleanup_runtime
./scripts/clean.sh >/dev/null 2>&1 || true

echo
echo "Checking clean package source..."

if [[ ! -d "$PACKAGE_DIR/dist" ]]; then
  pass "generated dist directory is absent before npm pack"
else
  fail "generated dist directory already exists before npm pack"
fi

if [[ -f "$PACKAGE_DIR/scripts/generate-dist.js" ]] \
   && [[ -f "$PACKAGE_DIR/build-input/route.json" ]]; then
  pass "generator and build input exist in package source"
else
  fail "generator or build input is missing from package source"
fi

if node -e '
  const p = require("./packages/trace-route-package/package.json");
  process.exit(
    p.scripts?.prepack === "node scripts/generate-dist.js" &&
    p.main === "dist/index.js" &&
    Array.isArray(p.files) &&
    p.files.length === 1 &&
    p.files[0] === "dist" ? 0 : 1
  );
'; then
  pass "package metadata binds prepack to generator and publishes only dist"
else
  fail "package lifecycle/publication metadata has changed"
fi

echo
echo "Packing and installing..."

mkdir -p trace-output
PROOF_BUILD_TMP=".proof-build.log"
rm -f "$PROOF_BUILD_TMP"

if ./scripts/build.sh >"$PROOF_BUILD_TMP" 2>&1; then
  pass "npm pack and application install complete"
else
  fail "build failed; see $PROOF_BUILD_TMP"
fi

mkdir -p trace-output
cp "$PROOF_BUILD_TMP" trace-output/proof-build.log 2>/dev/null || true
rm -f "$PROOF_BUILD_TMP"

if grep -q 'trace-route-package@1.0.0 prepack' trace-output/proof-build.log \
   && grep -q 'node scripts/generate-dist.js' trace-output/proof-build.log \
   && grep -q 'generated dist/index.js for /hidden/prepack-info' trace-output/proof-build.log \
   && grep -q 'generated dist/prepack-evidence.json' trace-output/proof-build.log; then
  pass "build log proves prepack executed the generator"
else
  fail "prepack execution evidence is missing from build log"
fi

if [[ -f "$TARBALL" ]]; then
  pass "npm tarball exists"
else
  fail "npm tarball is missing"
fi

echo
echo "Checking packed artefact..."

tar -tzf "$TARBALL" >trace-output/proof-tarball-list.txt 2>&1 || true

if grep -qx 'package/dist/index.js' trace-output/proof-tarball-list.txt \
   && grep -qx 'package/dist/prepack-evidence.json' trace-output/proof-tarball-list.txt \
   && grep -qx 'package/package.json' trace-output/proof-tarball-list.txt; then
  pass "tarball contains generated runtime files and package metadata"
else
  fail "expected generated files are missing from tarball"
fi

if ! grep -q 'generate-dist.js' trace-output/proof-tarball-list.txt \
   && ! grep -q 'build-input/route.json' trace-output/proof-tarball-list.txt; then
  pass "tarball excludes generator and original build input"
else
  fail "generator or build input unexpectedly ships in tarball"
fi

TARBALL_COUNT="$(wc -l <trace-output/proof-tarball-list.txt | tr -d ' ')"
if [[ "$TARBALL_COUNT" == "3" ]]; then
  pass "tarball contains exactly the three expected files"
else
  fail "tarball file count changed: expected 3, found ${TARBALL_COUNT}"
fi

tar -xOzf "$TARBALL" package/dist/prepack-evidence.json \
  >trace-output/proof-packed-evidence.json 2>/dev/null || true

if node -e '
  const fs = require("fs");
  const e = JSON.parse(fs.readFileSync("trace-output/proof-packed-evidence.json", "utf8"));
  process.exit(
    e.event === "npm-prepack-generated" &&
    e.package === "trace-route-package" &&
    e.version === "1.0.0" &&
    e.generatedBy === "npm lifecycle prepack -> scripts/generate-dist.js" &&
    e.origin === "trace-route-package build input" &&
    e.route === "/hidden/prepack-info" ? 0 : 1
  );
'; then
  pass "tarball provenance marker records lifecycle generator and route"
else
  fail "tarball provenance marker is missing or incorrect"
fi

echo
echo "Checking installed package..."

find "$INSTALLED_DIR" -maxdepth 3 -type f -print | sort \
  >trace-output/proof-installed-files.txt 2>/dev/null || true

if grep -qx 'node_modules/trace-route-package/dist/index.js' trace-output/proof-installed-files.txt \
   && grep -qx 'node_modules/trace-route-package/dist/prepack-evidence.json' trace-output/proof-installed-files.txt \
   && grep -qx 'node_modules/trace-route-package/package.json' trace-output/proof-installed-files.txt; then
  pass "installed package contains generated runtime files"
else
  fail "installed generated files are missing"
fi

if ! grep -q 'generate-dist.js' trace-output/proof-installed-files.txt \
   && ! grep -q 'build-input/route.json' trace-output/proof-installed-files.txt; then
  pass "installed package excludes generator and build input"
else
  fail "installed package unexpectedly contains generator or build input"
fi

if node -e '
  const e = require("./node_modules/trace-route-package/dist/prepack-evidence.json");
  process.exit(
    e.generatedBy === "npm lifecycle prepack -> scripts/generate-dist.js" &&
    e.route === "/hidden/prepack-info" ? 0 : 1
  );
'; then
  pass "installed provenance marker survives packaging and installation"
else
  fail "installed provenance marker is incorrect"
fi

echo
echo "Checking npm evidence views..."

if npm ls --all >trace-output/proof-npm-ls.txt 2>&1; then
  pass "npm dependency tree resolves"
else
  fail "npm dependency tree failed"
fi

if grep -q 'trace-route-package@1.0.0' trace-output/proof-npm-ls.txt; then
  pass "npm dependency view identifies trace-route-package@1.0.0"
else
  fail "npm dependency view does not identify trace-route-package"
fi

if npm sbom --sbom-format cyclonedx >trace-output/proof-npm-sbom.json 2>trace-output/proof-npm-sbom.err; then
  pass "npm CycloneDX SBOM generation completes"

  if node -e '
    const fs = require("fs");
    const bom = JSON.parse(fs.readFileSync("trace-output/proof-npm-sbom.json", "utf8"));
    const components = bom.components || [];
    process.exit(components.some(c => c.name === "trace-route-package" && c.version === "1.0.0") ? 0 : 1);
  '; then
    pass "npm CycloneDX SBOM identifies trace-route-package@1.0.0"
  else
    fail "npm CycloneDX SBOM does not identify trace-route-package@1.0.0"
  fi
else
  fail "npm CycloneDX SBOM generation failed"
fi

echo
echo "Checking Syft evidence views..."

if command -v syft >/dev/null 2>&1; then
  if syft "dir:${INSTALLED_DIR}" -o json >trace-output/proof-syft-isolated.json 2>trace-output/proof-syft-isolated.err; then
    pass "Syft isolated-package scan completes"

    if node -e '
      const fs = require("fs");
      const r = JSON.parse(fs.readFileSync("trace-output/proof-syft-isolated.json", "utf8"));
      process.exit((r.artifacts || []).length === 0 ? 0 : 1);
    '; then
      pass "Syft isolated installed package identifies zero packages"
    else
      fail "Syft isolated-package result changed from the walkthrough"
    fi
  else
    fail "Syft isolated-package scan failed"
  fi

  if syft dir:. -o json >trace-output/proof-syft-project.json 2>trace-output/proof-syft-project.err; then
    pass "Syft whole-project scan completes"

    if node -e '
      const fs = require("fs");
      const r = JSON.parse(fs.readFileSync("trace-output/proof-syft-project.json", "utf8"));
      const names = new Set((r.artifacts || []).map(a => `${a.name}@${a.version}`));
      process.exit(
        names.has("node-prepack-trace-lab@1.0.0") &&
        names.has("trace-route-package@1.0.0") ? 0 : 1
      );
    '; then
      pass "Syft whole-project view identifies application and dependency"
    else
      fail "Syft whole-project view does not contain both expected npm packages"
    fi
  else
    fail "Syft whole-project scan failed"
  fi
else
  warn "Syft not installed; scanner-specific checks skipped"
fi

echo
echo "Checking runtime behaviour..."

if curl -fsS --max-time 1 "http://127.0.0.1:${PROOF_PORT}/health" >/dev/null 2>&1; then
  fail "proof port ${PROOF_PORT} is already serving HTTP"
else
  if PORT="$PROOF_PORT" ./scripts/run.sh >trace-output/proof-runtime-start.log 2>&1; then
    pass "application starts on isolated proof port ${PROOF_PORT}"
  else
    fail "application failed to start; see trace-output/proof-runtime-start.log"
  fi

  HEALTH="$(curl -fsS --max-time 3 "http://127.0.0.1:${PROOF_PORT}/health" 2>/dev/null || true)"
  if [[ "$HEALTH" == *'"application": "node-prepack-trace-lab"'* ]] \
     && [[ "$HEALTH" == *'"status": "UP"'* ]]; then
    pass "source-defined health endpoint responds"
  else
    fail "health endpoint response is incorrect"
  fi

  HIDDEN="$(curl -fsS --max-time 3 "http://127.0.0.1:${PROOF_PORT}/hidden/prepack-info" 2>/dev/null || true)"
  if [[ "$HIDDEN" == *'"event": "npm-prepack-generated"'* ]] \
     && [[ "$HIDDEN" == *'"generatedBy": "npm lifecycle prepack -> scripts/generate-dist.js"'* ]] \
     && [[ "$HIDDEN" == *'"origin": "trace-route-package build input"'* ]] \
     && [[ "$HIDDEN" == *'"route": "/hidden/prepack-info"'* ]]; then
    pass "lifecycle-generated runtime endpoint returns expected provenance"
  else
    fail "hidden runtime endpoint response is incorrect"
  fi

  cleanup_runtime
fi

echo
echo "S05 proof result: ${PASS} passed, ${FAIL} failed, ${WARN} warnings"

if (( FAIL > 0 )); then
  echo "RESULT: FAIL — one or more demonstrated outcomes are no longer true."
  exit 1
fi

echo "RESULT: PASS — the demonstrated S05 outcomes are still true."
