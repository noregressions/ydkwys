#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "T07 / S05 — npm audit"
echo "====================="
echo

echo "== Ground truth: npm prepack transformation =="
grep -E 'trace-route-package@1.0.0 prepack|node scripts/generate-dist.js|generated dist/' \
  "$BASE/build.log" || true

echo
echo "== Ground truth: packed artefact files =="
cat "$BASE/tarball-files.txt"

echo
echo "== Ground truth: published package.json lifecycle declaration =="
grep -E '"name"|"version"|"main"|"prepack"' "$BASE/unpacked-package/package.json" || true

echo
echo "== Ground truth: generator/input absent from published package =="
if grep -Eq 'generate-dist.js|build-input/route.json' "$BASE/unpacked-package-files.txt"; then
  echo "unexpected: generator/input present"
else
  echo "generator absent: scripts/generate-dist.js"
  echo "input absent:     build-input/route.json"
fi

echo
echo "== Ground truth: generated runtime evidence survives =="
cat "$BASE/installed-prepack-evidence.json"

for name in \
  application \
  application-lock-only \
  source-package \
  source-package-no-lock \
  published-package \
  published-package-no-lock \
  public-vulnerable-control
do
  echo
  echo "== npm audit: $name =="
  if [[ -f "$AUDIT/$name/exit.txt" ]]; then
    echo "exit=$(cat "$AUDIT/$name/exit.txt")"
  else
    echo "exit=(not run)"
  fi

  if [[ -f "$AUDIT/$name/result.txt" ]]; then
    cat "$AUDIT/$name/result.txt"
  else
    echo "(no result)"
  fi
done

echo
echo "== Lifecycle/provenance strings in npm audit output =="
for term in \
  'scripts/generate-dist.js' \
  'npm-prepack-generated' \
  'prepack-evidence.json' \
  '/hidden/prepack-info'
do
  printf '%-28s ' "$term"
  if grep -R -F -q "$term" "$AUDIT" --include='audit.json' --include='audit.stderr'; then
    echo "FOUND"
  else
    echo "not found"
  fi
done

echo
echo "Interpretation questions:"
echo "  1. Does application npm audit identify trace-route-package or any vulnerability?"
echo "  2. Does --package-lock-only change the result when node_modules is ignored?"
echo "  3. What happens when npm audit is pointed at the source package without a lockfile?"
echo "  4. What happens with --no-package-lock, when npm rebuilds only from package.json?"
echo "  5. Does the published package produce a different audit result from its source package?"
echo "  6. Does any audit result expose prepack execution, the generator, generated evidence or route?"
echo "  7. Does the public lodash control prove the registry advisory path is functioning?"
echo "  8. Is npm audit inspecting shipped JavaScript bytes, or auditing dependency identities from npm metadata?"
