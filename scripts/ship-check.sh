#!/usr/bin/env bash
#
# ship-check.sh — the minimum practice, run against one project.
#
# Four questions, asked every release:
#
#   1. What does the resolver say we depend on?          (declared inventory)
#   2. What is identifiable in the thing we ship?        (shipped inventory)
#   3. Where do those two disagree?                      (the gap)
#   4. Is anyone upstream still maintaining any of it?   (lifecycle)
#
# Nothing here is clever. The point is that it is short enough to run on
# every build, and that it compares two evidence sources instead of trusting
# one. See workshop/06-minimum-practice.md.
#
# Usage: ./scripts/ship-check.sh [project-dir]        (default: S01)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="${1:-$REPO_ROOT/scenarios/S01-spring-node}"
OUT_DIR="${SHIP_CHECK_OUT:-$PROJECT_DIR/ship-check}"

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: no such directory: $PROJECT_DIR" >&2
  exit 1
fi

cd "$PROJECT_DIR"
mkdir -p "$OUT_DIR"

DECLARED="$OUT_DIR/declared.txt"
SHIPPED="$OUT_DIR/shipped.txt"
: > "$DECLARED"
: > "$SHIPPED"

have() { command -v "$1" >/dev/null 2>&1; }

rule() { printf '\n=== %s\n' "$1"; }

skip() { printf '  SKIPPED: %s\n' "$1"; }

# ---------------------------------------------------------------------------
# 1. Declared inventory — what the resolver thinks we asked for.
# ---------------------------------------------------------------------------
rule "1. Declared (resolver view)"

if [[ -f pom.xml ]]; then
  if have mvn; then
    # Runtime scope only: test dependencies are not in the shipped artefact,
    # and listing them would fill section 3 with false gaps.
    mvn -q -B dependency:list -DincludeScope=runtime \
        -DoutputFile=/dev/stdout -DappendOutput=true > "$OUT_DIR/mvn.raw" 2>&1
    mvn_status=$?
    grep -E '^[[:space:]]+[^:]+:[^:]+:jar:' "$OUT_DIR/mvn.raw" \
      | sed -E 's/^[[:space:]]+//; s/^[^:]+:([^:]+):jar:([^:]+).*$/\1 \2/' \
      | sort -u >> "$DECLARED"
    if [[ $mvn_status -ne 0 ]]; then
      skip "Maven resolution incomplete (build/install the project first) -- see $OUT_DIR/mvn.raw"
    fi
  else
    skip "mvn not installed; no Maven declared inventory"
  fi
fi

for pkg in package.json frontend/package.json; do
  [[ -f "$pkg" ]] || continue
  if have npm; then
    npm --prefix "$(dirname "$pkg")" ls --all --parseable --long 2>/dev/null \
      | grep '/node_modules/' \
      | sed -E 's#^.*/node_modules/##' \
      | sed -E 's/^(.+)@([^@]+)$/\1 \2/' \
      | sort -u >> "$DECLARED"
  else
    skip "npm not installed; no Node declared inventory"
  fi
done

if [[ -f pyproject.toml || -f requirements.txt ]]; then
  if [[ -x .venv/bin/pip ]]; then
    .venv/bin/pip freeze 2>/dev/null | sed -E 's/==/ /' | sort -u >> "$DECLARED"
  else
    skip "no .venv/bin/pip; no Python declared inventory"
  fi
fi

sort -u -o "$DECLARED" "$DECLARED"
printf '  %s components declared -> %s\n' "$(wc -l < "$DECLARED" | tr -d ' ')" "$DECLARED"

# ---------------------------------------------------------------------------
# 2. Shipped inventory — what is identifiable in the artefacts themselves.
# ---------------------------------------------------------------------------
rule "2. Shipped (artefact view)"

if ! have syft; then
  skip "syft not installed — this is the half of the check that matters most"
  echo "  install: https://github.com/anchore/syft"
else
  targets=()
  while IFS= read -r f; do targets+=("$f"); done < <(
    find . -maxdepth 3 \
      \( -name '*.jar' -o -name '*.war' -o -name '*.tgz' -o -name '*.whl' \) \
      -not -path './ship-check/*' 2>/dev/null | sort
  )
  for d in dist frontend/dist build; do
    [[ -d "$d" ]] && targets+=("$d")
  done

  if [[ ${#targets[@]} -eq 0 ]]; then
    skip "no built artefacts found — build the project first"
  fi

  for t in "${targets[@]}"; do
    printf '  scanning %s\n' "$t"
    syft -q -o json "$t" 2>/dev/null \
      | jq -r '.artifacts[]? | "\(.name) \(.version)"' >> "$SHIPPED"
  done
fi

sort -u -o "$SHIPPED" "$SHIPPED"
printf '  %s components identifiable -> %s\n' "$(wc -l < "$SHIPPED" | tr -d ' ')" "$SHIPPED"

# ---------------------------------------------------------------------------
# 3. The gap — where the two views disagree. This is the whole point.
# ---------------------------------------------------------------------------
rule "3. The gap"

if [[ ! -s "$DECLARED" || ! -s "$SHIPPED" ]]; then
  skip "need both inventories to diff them"
else
  echo
  echo "  Declared, but NOT identifiable in the artefact:"
  echo "  (shaded, relocated, bundled, minified — or simply not shipped)"
  comm -23 <(cut -d' ' -f1 "$DECLARED" | sort -u) \
           <(cut -d' ' -f1 "$SHIPPED"  | sort -u) | sed 's/^/    /'

  echo
  echo "  In the artefact, but NOT declared:"
  echo "  (generated at build time, vendored, or pulled in by a plugin)"
  comm -13 <(cut -d' ' -f1 "$DECLARED" | sort -u) \
           <(cut -d' ' -f1 "$SHIPPED"  | sort -u) | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
# 4. Lifecycle — is anyone upstream still fixing this?
# ---------------------------------------------------------------------------
rule "4. Lifecycle (EOL)"

if have npx; then
  echo "  running: npx @herodevs/cli scan eol --dir ."
  npx --yes @herodevs/cli scan eol --dir . 2>&1 | tail -40 \
    || skip "EOL scan failed (offline?) — record the result manually"
else
  skip "npx not available; run the EOL check by hand"
fi

# ---------------------------------------------------------------------------
# 5. Provenance — can this artefact say where it came from?
# ---------------------------------------------------------------------------
rule "5. Provenance"

found=0
if find . -maxdepth 4 -name 'git.properties' 2>/dev/null | grep -q .; then
  echo "  git.properties present (an internal claim — unsigned)"
  found=1
fi
if [[ -f Dockerfile ]] && grep -q 'org.opencontainers.image' Dockerfile 2>/dev/null; then
  echo "  OCI image labels declared (an unsigned claim)"
  found=1
fi
if find . -maxdepth 3 -name '*.att' -o -maxdepth 3 -name '*.sig' 2>/dev/null | grep -q .; then
  echo "  signature/attestation artefacts present"
  found=1
fi
[[ $found -eq 0 ]] && skip "no provenance evidence found — see scenarios/S07-provenance-s01"

rule "Done"
echo "  Inventories written to $OUT_DIR"
echo "  The gap in section 3 is the part your scanner will never mention."
