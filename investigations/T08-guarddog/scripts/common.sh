#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DEFAULT="$(cd "$ROOT/../.." 2>/dev/null && pwd || true)"
S05="${S05:-${REPO_DEFAULT}/scenarios/S05-node-prepack}"
S03="${S03:-${REPO_DEFAULT}/scenarios/S03-python-pep517}"

RESULTS="$ROOT/results"

# GuardDog cannot use its kernel sandbox on most laptops; the source-code
# heuristics run the same without it. Override to "" if your host supports it.
NO_SANDBOX="${NO_SANDBOX:---no-sandbox}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    echo "GuardDog: pipx install guarddog  (or)  pip install guarddog" >&2
    exit 1
  }
}

need guarddog
for cmd in tar grep; do need "$cmd"; done

mkdir -p "$RESULTS"
