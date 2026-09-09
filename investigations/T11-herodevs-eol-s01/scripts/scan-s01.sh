#!/usr/bin/env bash
# T11 — the same lifecycle question asked at four different boundaries.
#
# S01 establishes that a component's identity survives some build boundaries
# and not others. This asks what that does to lifecycle data, which is not
# vulnerability data: every probe below asks "is anyone still maintaining
# this?", and the only thing that changes is what the tool is allowed to read.
set -euo pipefail
source "$(dirname "$0")/common.sh"

rm -rf "$RESULTS"
mkdir -p "$RESULTS"

echo "Node:       $(node --version)"
echo "HeroDevs:   ${HD[*]}"
echo "Scenario:   $S01"
echo

if [[ ! -d "$S01/frontend/node_modules" ]]; then
  echo "S01 is not built. Run its build first:" >&2
  echo "  (cd $S01 && ./scripts/build.sh)" >&2
  exit 1
fi

echo "== preflight: can the CLI reach the service at all? =="
if ! hd_preflight; then
  exit 1
fi
echo "ok"
echo

run_probe() {
  local name="$1"; shift
  local out="$RESULTS/$name"
  mkdir -p "$out"

  echo
  echo "== $name =="
  echo "hd scan eol $*"

  local rc
  set +e
  # --save is not optional here: --output on its own is ignored, and the CLI
  # says so in a warning rather than an error.
  hd_scan "$@" --save --hideReportUrl >"$out/report.txt" 2>"$out/stderr.txt"
  rc=$?
  set -e
  printf '%s\n' "$rc" >"$out/exit.txt"

  [[ -s "$out/stderr.txt" ]] && sed 's/^/  ! /' "$out/stderr.txt"
  [[ -s "$out/report.txt" ]] && cat "$out/report.txt"
  echo "exit=$rc"
}

# A. The declared model: package.json plus the installed tree. This is the
#    resolver boundary -- everything the project says it depends on,
#    including the build tooling it never ships.
run_probe "a-source-manifest" \
  --dir "$S01/frontend" \
  --output "$RESULTS/a-source-manifest/herodevs.report.json" \
  --saveSbom --sbomOutput "$RESULTS/a-source-manifest/herodevs.sbom.json"

# B. The artefact: Vite's output, which is what actually reaches a browser.
#    S01 has already established that lodash does not survive this boundary
#    as an identifiable component.
run_probe "b-built-artefact" \
  --dir "$S01/frontend/dist" \
  --output "$RESULTS/b-built-artefact/herodevs.report.json"

# C. Someone else's SBOM. The CLI will scan a CycloneDX file it did not
#    generate, so the lifecycle answer inherits that file's blind spots --
#    which is the whole point of the probe.
if [[ -f "$RESULTS/a-source-manifest/herodevs.sbom.json" ]]; then
  run_probe "c-sbom-file" \
    --file "$RESULTS/a-source-manifest/herodevs.sbom.json" \
    --output "$RESULTS/c-sbom-file/herodevs.report.json"
else
  echo
  echo "== c-sbom-file =="
  echo "skipped: probe A saved no SBOM"
fi

# D. Control. A package with a published, uncontested end-of-life date, so a
#    silent result in A-C can be read as "nothing to say" rather than "the
#    tool cannot say anything".
CONTROL="$RESULTS/d-control/workspace"
mkdir -p "$CONTROL"
cat > "$CONTROL/package.json" <<'JSON'
{
  "name": "t11-eol-control",
  "version": "1.0.0",
  "private": true,
  "description": "Known-EOL coordinates, to prove the scanner reports EOL at all",
  "dependencies": {
    "angular": "1.8.3",
    "request": "2.88.2"
  }
}
JSON
# cdxgen reads a lockfile or an installed tree, not a bare dependency list, so
# resolve the control before scanning it. --package-lock-only keeps it to a
# lockfile: no install, no lifecycle scripts.
(
  cd "$CONTROL"
  npm install --package-lock-only --ignore-scripts --no-audit --no-fund
) >"$RESULTS/d-control/npm-install.log" 2>&1 \
  || { echo "Unable to resolve the control workspace:" >&2
       cat "$RESULTS/d-control/npm-install.log" >&2; }

run_probe "d-control" \
  --dir "$CONTROL" \
  --output "$RESULTS/d-control/herodevs.report.json"

echo
echo "T11 lifecycle probes captured under:"
echo "  $RESULTS"
echo "Run:"
echo "  ./scripts/compare-s01.sh"
