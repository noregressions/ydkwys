#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

NORMALIZER_BOM="normalizer/target/bom.json"
SERVICE_BOM="service/target/bom.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required to compare the SBOMs." >&2
  exit 1
fi

missing=0
for bom in "$NORMALIZER_BOM" "$SERVICE_BOM"; do
  if [[ ! -f "$bom" ]]; then
    echo "ERROR: missing $bom" >&2
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  cat >&2 <<'MSG'

Generate the Maven/CycloneDX SBOMs first:

  mvn -pl service -am \
    org.cyclonedx:cyclonedx-maven-plugin:2.9.3:makeBom \
    -DoutputFormat=json
MSG
  exit 1
fi

print_components() {
  local bom="$1"
  shift

  jq -r --argjson names "$(printf '%s\n' "$@" | jq -R . | jq -s .)" '
    [
      .components[]?
      | select(.name as $name | $names | index($name))
      | [.name, (.version // "UNKNOWN"), (.purl // "")]
    ]
    | if length == 0 then
        "(no matching components)"
      else
        .[] | @tsv
      end
  ' "$bom"
}

echo "=== normalizer BOM ==="
print_components "$NORMALIZER_BOM" \
  commons-codec

echo
echo "=== service BOM ==="
print_components "$SERVICE_BOM" \
  jackson-databind \
  commons-codec \
  normalizer \
  lodash
