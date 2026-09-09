#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in docker syft jq mvn jar; do
  require_command "$cmd"
done

S02="$(resolve_s02)" || {
  echo "Could not find S02-payara-mvnpm. Set S02_DIR=/path/to/S02-payara-mvnpm" >&2
  exit 1
}

OUT="$ROOT/results/s02/baseline"
mkdir -p "$OUT"

IMAGE="${S02_IMAGE:-payara-mvnpm-trace-lab:local}"
WAR="$S02/target/payara-mvnpm-trace-lab-1.0.0.war"

echo "S02: $S02"
echo "Image: $IMAGE"
echo "Output: $OUT"

echo
echo "== Build S02 =="
(
  cd "$S02"
  ./scripts/build.sh
) | tee "$OUT/build.txt"

echo
echo "== Maven application dependency model =="
(
  cd "$S02"
  mvn dependency:tree \
    -Dverbose \
    -Dincludes=org.apache.commons:commons-lang3,jakarta.platform:jakarta.jakartaee-web-api
) | tee "$OUT/maven-app-tree.txt"

echo
echo "== Maven plugin realm evidence =="
(
  cd "$S02"
  mvn -X generate-resources
) >"$OUT/maven-generate-resources-debug.txt" 2>&1

grep -E \
  'io\.mvnpm:esbuild-maven-plugin|org\.mvnpm:lodash-es|ClassRealm|Included:' \
  "$OUT/maven-generate-resources-debug.txt" \
  | tee "$OUT/maven-plugin-tracers.txt" || true

echo
echo "== WAR physical boundary =="
jar tf "$WAR" \
  | grep -E \
    'WEB-INF/lib/commons-lang3|lodash-es|jakarta\.jakartaee|app\.js|app\.js\.map|assets/' \
  | tee "$OUT/war-tracers.txt" || true

echo
echo "== Build final image and generate scenario CycloneDX SBOM =="
(
  cd "$S02"
  ./scripts/image-trace.sh
) | tee "$OUT/image-trace.txt"

docker image inspect "$IMAGE" \
  --format '{{.Id}} {{json .RepoTags}} {{json .RepoDigests}}' \
  | tee "$OUT/image-identity.txt"

printf '%s\n' "$IMAGE" >"$OUT/image-name.txt"

cp "$S02/trace-output/image.cdx.json" "$OUT/image.cdx.json"

echo
echo "== Generate Syft JSON from the same image =="
syft "$IMAGE" -o syft-json="$OUT/image.syft.json"

echo
echo "== Inventory counts =="
jq '.artifacts | length' "$OUT/image.syft.json" \
  | tee "$OUT/syft-json-package-count.txt"
jq '.components | length' "$OUT/image.cdx.json" \
  | tee "$OUT/cdx-component-count.txt"

echo
echo "== Syft JSON tracked components =="
jq -r '
  .artifacts[]?
  | select(
      .name == "commons-lang3"
      or .name == "lodash-es"
      or .name == "payara-mvnpm-trace-lab"
      or (.name | startswith("jakarta."))
    )
  | [.name, (.version // ""), (.purl // "")]
  | @tsv
' "$OUT/image.syft.json" \
  | tee "$OUT/syft-json-tracers.txt"

echo
echo "== CycloneDX tracked components =="
jq -r '
  .components[]?
  | select(
      .name == "commons-lang3"
      or .name == "lodash-es"
      or .name == "payara-mvnpm-trace-lab"
      or (.name | startswith("jakarta."))
    )
  | [.name, (.version // ""), (.purl // "")]
  | @tsv
' "$OUT/image.cdx.json" \
  | tee "$OUT/cdx-tracers.txt"

echo
echo "T04 / S02 baseline captured."
