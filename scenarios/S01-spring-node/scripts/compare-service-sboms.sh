#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

MAVEN_BOM="service/target/bom.json"
SYFT_BOM="trace-output/service-syft.cdx.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required to compare the SBOMs." >&2
  exit 1
fi

missing=0
for bom in "$MAVEN_BOM" "$SYFT_BOM"; do
  if [[ ! -f "$bom" ]]; then
    echo "ERROR: missing $bom" >&2
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  cat >&2 <<'MSG'

Generate both CycloneDX SBOMs first:

  mvn -pl service -am \
    org.cyclonedx:cyclonedx-maven-plugin:2.9.3:makeBom \
    -DoutputFormat=json

  mkdir -p trace-output
  syft service/target/service-1.0.0.jar \
    -o cyclonedx-json=trace-output/service-syft.cdx.json
MSG
  exit 1
fi

print_components() {
  local bom="$1"

  jq -r '
    [
      .components[]?
      | select(
          .name == "jackson-databind"
          or .name == "commons-codec"
          or .name == "normalizer"
          or .name == "lodash"
        )
      | [.name, (.version // "UNKNOWN"), (.purl // "")]
    ]
    | sort_by(.[0], .[1])
    | if length == 0 then
        "(no matching components)"
      else
        .[] | @tsv
      end
  ' "$bom"
}

echo "=== Maven-generated service SBOM ==="
print_components "$MAVEN_BOM"

echo
echo "=== Syft-generated service SBOM ==="
print_components "$SYFT_BOM"
