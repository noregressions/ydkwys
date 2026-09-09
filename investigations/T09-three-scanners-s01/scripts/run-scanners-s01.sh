#!/usr/bin/env bash
#
# T09: point Grype, Trivy and OSV-Scanner at the SAME six boundaries of S01
# and record, per tool per boundary, which tracked components it could name.
#
# Everything writes to results/s01/<tool>/<boundary>.*; compare-s01.sh turns
# that tree into the matrix.
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in jq docker; do
  require_command "$cmd"
done

S01="$(resolve_s01)" || {
  echo "Could not find S01-spring-node. Set S01_DIR=/path/to/S01-spring-node" >&2
  exit 1
}

BASE="$ROOT/results/s01/baseline"
[[ -f "$BASE/image-name.txt" ]] || {
  echo "Run ./scripts/baseline-s01.sh first." >&2
  exit 1
}
IMAGE="$(cat "$BASE/image-name.txt")"

STAGE="$ROOT/results/s01/staged"
mkdir -p "$STAGE"

# A JAR handed straight to a filesystem scanner is often treated as an opaque
# file. Staging it alone in a directory is what makes the Java analyser fire.
stage() {
  local label="$1" archive="$2"
  rm -rf "$STAGE/$label"; mkdir -p "$STAGE/$label"
  cp "$archive" "$STAGE/$label/"
  printf '%s' "$STAGE/$label"
}

NORMALIZER_JAR="$S01/normalizer/target/normalizer-1.0.0.jar"
STRIPPED_JAR="$S01/trace-output/normalizer-no-codec-metadata.jar"
SERVICE_JAR="$S01/service/target/service-1.0.0.jar"

# boundary label | kind | target
BOUNDARIES=(
  "service-pom|source|$S01/service/pom.xml"
  "frontend-lock|source|$S01/frontend/package-lock.json"
  "normalizer-jar|archive|$NORMALIZER_JAR"
  "normalizer-stripped-jar|archive|$STRIPPED_JAR"
  "service-jar|archive|$SERVICE_JAR"
  "frontend-dist|dir|$S01/frontend/dist"
  "container-image|image|$IMAGE"
)

# ---------------------------------------------------------------- grype -----
run_grype() {
  command -v grype >/dev/null 2>&1 || { echo "SKIP grype: not installed"; return; }
  local OUT="$ROOT/results/s01/grype"; mkdir -p "$OUT"
  grype version >"$OUT/version.txt" 2>&1 || true

  local entry label kind target src
  for entry in "${BOUNDARIES[@]}"; do
    IFS='|' read -r label kind target <<<"$entry"
    case "$kind" in
      image)   src="$target" ;;
      archive) src="dir:$(stage "$label" "$target")" ;;
      *)       src="dir:$target" ;;
    esac
    [[ "$kind" == "source" ]] && src="file:$target"

    echo "== grype / $label"
    set +e
    grype "$src" -o json --file "$OUT/$label.json" >/dev/null 2>"$OUT/$label.err"
    printf '%s\n' "$?" >"$OUT/$label.exit"
    # grype's JSON carries matches only — there is no package catalogue in it,
    # so identity has to come from a second pass in a format that has one.
    # Without this, grype appears unable to name anything it did not also
    # find a vulnerability for, which is a claim about the output format
    # rather than about the tool.
    grype "$src" -o cyclonedx-json --file "$OUT/$label.cdx.json" >/dev/null 2>>"$OUT/$label.err"
    set -e

    if [[ -s "$OUT/$label.cdx.json" ]]; then
      jq -r --arg re "$TRACER_RE" '
        .components[]?
        | select(.name // "" | test($re; "i"))
        | [.name, (.version // ""), (.purl // "")] | @tsv
      ' "$OUT/$label.cdx.json" 2>/dev/null | sort -u >"$OUT/$label.tracers.txt" || true
    fi

    if [[ -s "$OUT/$label.json" ]]; then
      # Findings: vulnerabilities matched against those components.
      jq -r --arg re "$TRACER_RE" '
        .matches[]?
        | select(.artifact.name // "" | test($re; "i"))
        | [.artifact.name, .artifact.version, .vulnerability.id, .vulnerability.severity]
        | @tsv
      ' "$OUT/$label.json" 2>/dev/null | sort -u >"$OUT/$label.vulns.txt" || true
    fi
  done
}

# ---------------------------------------------------------------- trivy -----
run_trivy() {
  command -v trivy >/dev/null 2>&1 || { echo "SKIP trivy: not installed"; return; }
  local OUT="$ROOT/results/s01/trivy"; mkdir -p "$OUT"
  trivy --version >"$OUT/version.txt" 2>&1 || true

  local entry label kind target
  for entry in "${BOUNDARIES[@]}"; do
    IFS='|' read -r label kind target <<<"$entry"
    echo "== trivy / $label"
    set +e
    case "$kind" in
      image)
        trivy image --image-src docker --scanners vuln --no-progress \
          --format json --output "$OUT/$label.json" "$target" >/dev/null 2>"$OUT/$label.err" ;;
      archive)
        trivy rootfs --scanners vuln --no-progress \
          --format json --output "$OUT/$label.json" "$(stage "$label" "$target")" >/dev/null 2>"$OUT/$label.err" ;;
      *)
        trivy fs --scanners vuln --no-progress \
          --format json --output "$OUT/$label.json" "$target" >/dev/null 2>"$OUT/$label.err" ;;
    esac
    printf '%s\n' "$?" >"$OUT/$label.exit"
    set -e

    if [[ -s "$OUT/$label.json" ]]; then
      jq -r --arg re "$TRACER_RE" '
        .Results[]? | .Packages[]?
        | select(.Name // "" | test($re; "i"))
        | [.Name, (.Version // ""), (.Identifier.PURL // "")] | @tsv
      ' "$OUT/$label.json" 2>/dev/null | sort -u >"$OUT/$label.tracers.txt" || true
      jq -r --arg re "$TRACER_RE" '
        .Results[]? | .Vulnerabilities[]?
        | select(.PkgName // "" | test($re; "i"))
        | [.PkgName, (.InstalledVersion // ""), .VulnerabilityID, (.Severity // "")] | @tsv
      ' "$OUT/$label.json" 2>/dev/null | sort -u >"$OUT/$label.vulns.txt" || true
    fi
  done
}

# ----------------------------------------------------------- osv-scanner ----
run_osv() {
  command -v osv-scanner >/dev/null 2>&1 || { echo "SKIP osv-scanner: not installed"; return; }
  local OUT="$ROOT/results/s01/osv"; mkdir -p "$OUT"
  osv-scanner --version >"$OUT/version.txt" 2>&1 || true
  osv_mode >"$OUT/cli-form.txt"

  local entry label kind target
  for entry in "${BOUNDARIES[@]}"; do
    IFS='|' read -r label kind target <<<"$entry"
    echo "== osv-scanner / $label"
    case "$kind" in
      image)   osv_scan_image  "$target" "$OUT/$label.json" ;;
      archive) osv_scan_source "$(stage "$label" "$target")" "$OUT/$label.json" ;;
      *)       osv_scan_source "$target" "$OUT/$label.json" ;;
    esac

    if [[ -s "$OUT/$label.json" ]]; then
      jq -r --arg re "$TRACER_RE" '
        .results[]? | .packages[]?
        | select(.package.name // "" | test($re; "i"))
        | [(.package.name), (.package.version // ""), (.package.ecosystem // "")] | @tsv
      ' "$OUT/$label.json" 2>/dev/null | sort -u >"$OUT/$label.tracers.txt" || true
      jq -r --arg re "$TRACER_RE" '
        .results[]? | .packages[]?
        | select(.package.name // "" | test($re; "i")) as $p
        | $p.vulnerabilities[]?
        | [$p.package.name, ($p.package.version // ""), .id,
           (.database_specific.severity // "")] | @tsv
      ' "$OUT/$label.json" 2>/dev/null | sort -u >"$OUT/$label.vulns.txt" || true
    fi
  done
}

# Run everything, or just the tools named on the command line — so a fix to
# one tool's probe does not cost a re-scan of the other two.
#   ./scripts/run-scanners-s01.sh            all three
#   ./scripts/run-scanners-s01.sh grype      grype only
WANTED=("$@")
wanted() {
  [[ ${#WANTED[@]} -eq 0 ]] && return 0
  local w; for w in "${WANTED[@]}"; do [[ "$w" == "$1" ]] && return 0; done
  return 1
}

wanted grype && run_grype
wanted trivy && run_trivy
wanted osv   && run_osv

echo
echo "T09 scanner probes captured. Next: ./scripts/compare-s01.sh"
