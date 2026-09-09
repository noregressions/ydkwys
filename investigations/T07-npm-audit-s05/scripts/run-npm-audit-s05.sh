#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

rm -rf "$AUDIT"
mkdir -p "$AUDIT"

if [[ ! -f "$BASE/application-package-lock.json" ]]; then
  echo "Baseline not found. Run ./scripts/baseline-s05.sh first." >&2
  exit 1
fi

run_audit() {
  local name="$1"
  local dir="$2"
  shift 2

  local out="$AUDIT/$name"
  mkdir -p "$out"

  echo
  echo "== $name =="
  echo "Directory: $dir"

  set +e
  (
    cd "$dir"
    npm audit "$@" --json
  ) >"$out/audit.json" 2>"$out/audit.stderr"
  local rc=$?
  set -e

  printf '%s\n' "$rc" > "$out/exit.txt"

  if [[ -s "$out/audit.stderr" ]]; then
    cat "$out/audit.stderr"
  fi
  if [[ -s "$out/audit.json" ]]; then
    node "$ROOT/scripts/normalise-audit.js" "$out/audit.json" \
      | tee "$out/result.txt"
  else
    echo "(no JSON output)" | tee "$out/result.txt"
  fi
  echo "exit=$rc"
}

echo "Node:     $(node --version)"
echo "npm:      $(npm --version)"
echo "Registry: $(npm config get registry)"

# A. Normal application audit: package-lock + installed node_modules are present.
run_audit "application" "$S05"

# B. Lock-only view: explicitly ignore node_modules.
run_audit "application-lock-only" "$S05" --package-lock-only

# C. Source package has package.json + generator + build input + generated output,
#    but no package-lock of its own.
run_audit "source-package" "$S05/packages/trace-route-package"

# D. Ask npm to rebuild the source package dependency model from package.json
#    rather than requiring a lockfile.
run_audit "source-package-no-lock" "$S05/packages/trace-route-package" --no-package-lock

# E. The published package contains generated dist + package.json, but not the
#    generator/input. It also has no package-lock.
run_audit "published-package" "$BASE/unpacked-package"

# F. Rebuild the published package model from its package.json.
run_audit "published-package-no-lock" "$BASE/unpacked-package" --no-package-lock

echo
echo "== public-vulnerable-control =="
CONTROL="$AUDIT/public-vulnerable-control/workspace"
rm -rf "$CONTROL"
mkdir -p "$CONTROL"

cat > "$CONTROL/package.json" <<'JSON'
{
  "name": "t07-public-vulnerability-control",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "lodash": "4.17.21"
  }
}
JSON

set +e
(
  cd "$CONTROL"
  npm install --package-lock-only --ignore-scripts --no-audit --no-fund
) >"$AUDIT/public-vulnerable-control/install.log" 2>&1
install_rc=$?
set -e
printf '%s\n' "$install_rc" > "$AUDIT/public-vulnerable-control/install-exit.txt"

if [[ "$install_rc" -eq 0 ]]; then
  run_audit "public-vulnerable-control" "$CONTROL" --package-lock-only
else
  echo "Unable to prepare public control."
  cat "$AUDIT/public-vulnerable-control/install.log"
fi

echo
echo "== Search audit outputs for S05 lifecycle/provenance strings =="
for term in \
  'scripts/generate-dist.js' \
  'npm-prepack-generated' \
  'prepack-evidence.json' \
  '/hidden/prepack-info'
do
  echo "-- $term"
  grep -R -F "$term" "$AUDIT" --include='audit.json' --include='audit.stderr' \
    || echo "(no hits)"
done

echo
echo "T07 npm audit probes captured."
echo "Run:"
echo "  ./scripts/compare-s05.sh"
