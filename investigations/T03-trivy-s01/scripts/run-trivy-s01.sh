#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in trivy jq docker; do
  require_command "$cmd"
done

S01="$(resolve_s01)" || {
  echo "Could not find S01-spring-node. Set S01_DIR=/path/to/S01-spring-node" >&2
  exit 1
}

BASE="$ROOT/results/s01/baseline"
OUT="$ROOT/results/s01/trivy"
mkdir -p "$OUT"

[[ -f "$BASE/image-name.txt" ]] || {
  echo "Run ./scripts/baseline-s01.sh first." >&2
  exit 1
}

IMAGE="$(cat "$BASE/image-name.txt")"

trivy --version | tee "$OUT/trivy-version.txt"

scan_fs() {
  local label="$1"
  local target="$2"

  echo
  echo "== $label: CycloneDX inventory =="
  set +e
  trivy fs \
    --scanners vuln \
    --no-progress \
    --format cyclonedx \
    --output "$OUT/$label.cdx.json" \
    "$target"
  local cdx_rc=$?
  set -e
  printf '%s\n' "$cdx_rc" >"$OUT/$label.cdx.exit"

  if [[ -f "$OUT/$label.cdx.json" ]]; then
    jq -r '
      .components[]?
      | select(
          .name == "jackson-databind"
          or .name == "commons-codec"
          or .name == "normalizer"
          or .name == "lodash"
        )
      | [.name, (.version // ""), (.purl // "")]
      | @tsv
    ' "$OUT/$label.cdx.json" \
      | tee "$OUT/$label.tracers.txt"
  fi

  echo
  echo "== $label: vulnerability result =="
  set +e
  trivy fs \
    --scanners vuln \
    --no-progress \
    --format json \
    --output "$OUT/$label.vuln.json" \
    "$target"
  local vuln_rc=$?
  set -e
  printf '%s\n' "$vuln_rc" >"$OUT/$label.vuln.exit"

  if [[ -f "$OUT/$label.vuln.json" ]]; then
    jq -r '
      .Results[]?
      | .Vulnerabilities[]?
      | select(
          (.PkgName // "" | test("jackson-databind|commons-codec|normalizer|lodash"; "i"))
          or (.PkgIdentifier.PURL // "" | test("jackson-databind|commons-codec|normalizer|lodash"; "i"))
        )
      | [
          (.PkgName // ""),
          (.InstalledVersion // ""),
          (.VulnerabilityID // ""),
          (.Severity // ""),
          (.FixedVersion // "")
        ]
      | @tsv
    ' "$OUT/$label.vuln.json" \
      | tee "$OUT/$label.vulns.txt"
  fi
}


scan_archive() {
  local label="$1"
  local archive="$2"
  local stagedir="$OUT/staged/$label"

  rm -rf "$stagedir"
  mkdir -p "$stagedir"
  cp "$archive" "$stagedir/"

  echo
  echo "== $label: CycloneDX inventory =="
  set +e
  trivy rootfs \
    --scanners vuln \
    --no-progress \
    --format cyclonedx \
    --output "$OUT/$label.cdx.json" \
    "$stagedir"
  local cdx_rc=$?
  set -e
  printf '%s\n' "$cdx_rc" >"$OUT/$label.cdx.exit"

  if [[ -f "$OUT/$label.cdx.json" ]]; then
    jq -r '
      .components[]?
      | select(
          .name == "jackson-databind"
          or .name == "commons-codec"
          or .name == "normalizer"
          or .name == "lodash"
        )
      | [.name, (.version // ""), (.purl // "")]
      | @tsv
    ' "$OUT/$label.cdx.json" \
      | tee "$OUT/$label.tracers.txt"
  fi

  echo
  echo "== $label: vulnerability result =="
  set +e
  trivy rootfs \
    --scanners vuln \
    --no-progress \
    --format json \
    --output "$OUT/$label.vuln.json" \
    "$stagedir"
  local vuln_rc=$?
  set -e
  printf '%s\n' "$vuln_rc" >"$OUT/$label.vuln.exit"

  if [[ -f "$OUT/$label.vuln.json" ]]; then
    jq -r '
      .Results[]?
      | .Vulnerabilities[]?
      | select(
          (.PkgName // "" | test("jackson-databind|commons-codec|normalizer|lodash"; "i"))
          or (.PkgIdentifier.PURL // "" | test("jackson-databind|commons-codec|normalizer|lodash"; "i"))
        )
      | [
          (.PkgName // ""),
          (.InstalledVersion // ""),
          (.VulnerabilityID // ""),
          (.Severity // ""),
          (.FixedVersion // "")
        ]
      | @tsv
    ' "$OUT/$label.vuln.json" \
      | tee "$OUT/$label.vulns.txt"
  fi
}

scan_image() {
  local label="$1"
  local image="$2"

  echo
  echo "== $label: CycloneDX inventory =="
  set +e
  trivy image \
    --image-src docker \
    --scanners vuln \
    --no-progress \
    --format cyclonedx \
    --output "$OUT/$label.cdx.json" \
    "$image"
  local cdx_rc=$?
  set -e
  printf '%s\n' "$cdx_rc" >"$OUT/$label.cdx.exit"

  if [[ -f "$OUT/$label.cdx.json" ]]; then
    jq -r '
      .components[]?
      | select(
          .name == "jackson-databind"
          or .name == "commons-codec"
          or .name == "normalizer"
          or .name == "lodash"
        )
      | [.name, (.version // ""), (.purl // "")]
      | @tsv
    ' "$OUT/$label.cdx.json" \
      | tee "$OUT/$label.tracers.txt"
  fi

  echo
  echo "== $label: vulnerability result =="
  set +e
  trivy image \
    --image-src docker \
    --scanners vuln \
    --no-progress \
    --format json \
    --output "$OUT/$label.vuln.json" \
    "$image"
  local vuln_rc=$?
  set -e
  printf '%s\n' "$vuln_rc" >"$OUT/$label.vuln.exit"

  if [[ -f "$OUT/$label.vuln.json" ]]; then
    jq -r '
      .Results[]?
      | .Vulnerabilities[]?
      | select(
          (.PkgName // "" | test("jackson-databind|commons-codec|normalizer|lodash"; "i"))
          or (.PkgIdentifier.PURL // "" | test("jackson-databind|commons-codec|normalizer|lodash"; "i"))
        )
      | [
          (.PkgName // ""),
          (.InstalledVersion // ""),
          (.VulnerabilityID // ""),
          (.Severity // ""),
          (.FixedVersion // "")
        ]
      | @tsv
    ' "$OUT/$label.vuln.json" \
      | tee "$OUT/$label.vulns.txt"
  fi
}

scan_fs "normalizer-pom" \
  "$S01/normalizer/pom.xml"

scan_fs "service-pom" \
  "$S01/service/pom.xml"

scan_fs "frontend-lock" \
  "$S01/frontend/package-lock.json"

scan_archive "normalizer-jar" \
  "$S01/normalizer/target/normalizer-1.0.0.jar"

scan_archive "normalizer-stripped-jar" \
  "$S01/trace-output/normalizer-no-codec-metadata.jar"

scan_archive "service-jar" \
  "$S01/service/target/service-1.0.0.jar"

scan_fs "frontend-dist" \
  "$S01/frontend/dist"

scan_image "container-image" "$IMAGE"

echo
echo "T03 Trivy probes captured."
echo "Run:"
echo "  ./scripts/compare-s01.sh"
