#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DEFAULT="$(cd "$ROOT/../.." 2>/dev/null && pwd || true)"
S01="${S01:-${REPO_DEFAULT}/scenarios/S01-spring-node}"

if [[ ! -d "$S01" ]]; then
  echo "Unable to find S01." >&2
  echo "Expected: $S01" >&2
  echo "Set S01=/path/to/scenarios/S01-spring-node and retry." >&2
  exit 1
fi

RESULTS="$ROOT/results/s01"

# Pinned, so a re-run months later is comparing the same tool. The lifecycle
# data behind it is a live service and will drift; the CLI should not.
HD_CLI_VERSION="${HD_CLI_VERSION:-2.0.8}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

for cmd in node npm jq; do
  need "$cmd"
done

# `hd` if it is installed, otherwise npx the pinned version. The first npx run
# downloads the CLI and its bundled SBOM generator, which is not quick.
if command -v hd >/dev/null 2>&1; then
  HD=(hd)
else
  HD=(npx -y "@herodevs/cli@${HD_CLI_VERSION}")
fi

hd_scan() {
  "${HD[@]}" scan eol "$@"
}

# The scan is a service call: it needs the network and an authenticated CLI
# (`hd auth login`, or a CI token). Say which of the two is missing rather
# than letting every probe fail with the same opaque line.
hd_preflight() {
  local probe_dir="$RESULTS/.preflight"
  rm -rf "$probe_dir"
  mkdir -p "$probe_dir"
  cat > "$probe_dir/package.json" <<'JSON'
{ "name": "t11-preflight", "version": "1.0.0", "private": true, "dependencies": {} }
JSON

  local out rc
  set +e
  out="$(hd_scan --dir "$probe_dir" --hideReportUrl 2>&1)"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    echo "The HeroDevs CLI could not complete a scan." >&2
    echo >&2
    printf '%s\n' "$out" | sed 's/^/  /' >&2
    echo >&2
    case "$out" in
      *token*|*auth*|*login*|*401*|*403*)
        echo "This is an authentication failure, not a scenario failure." >&2
        echo "  hd auth login                  interactive, opens a browser" >&2
        echo "  hd auth provision-ci-token     then export HD_TOKEN for headless use" >&2
        ;;
      *)
        echo "Check network reachability to the HeroDevs API and retry." >&2
        ;;
    esac
    return 1
  fi
  return 0
}

mkdir -p "$RESULTS"
