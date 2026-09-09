#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in mvn npm jar docker jq zip; do
  require_command "$cmd"
done

S01="$(resolve_s01)" || {
  echo "Could not find S01-spring-node. Set S01_DIR=/path/to/S01-spring-node" >&2
  exit 1
}

OUT="$ROOT/results/s01/baseline"
mkdir -p "$OUT"

IMAGE="${S01_IMAGE:-registry.example.com/checkout-service:release-123}"

echo "S01: $S01"
echo "Image: $IMAGE"
echo "Output: $OUT"

echo
echo "== Build S01 from clean state =="
(
  cd "$S01"
  ./scripts/build.sh
) | tee "$OUT/build.txt"

echo
echo "== Create controlled metadata-stripped normalizer =="
(
  cd "$S01"
  ./scripts/strip-codec-metadata.sh
) | tee "$OUT/strip-codec-metadata.txt"

echo
echo "== Maven ground truth: normalizer =="
(
  cd "$S01"
  mvn -pl normalizer dependency:tree \
    -Dverbose \
    -Dincludes=commons-codec:commons-codec
) | tee "$OUT/maven-normalizer.txt"

echo
echo "== Maven ground truth: service =="
(
  cd "$S01"
  mvn -pl service -am dependency:tree \
    -Dverbose \
    -Dincludes=commons-codec:commons-codec,com.fasterxml.jackson.core:jackson-databind,dev.noregressions.trace:normalizer
) | tee "$OUT/maven-service.txt"

echo
echo "== npm ground truth =="
(
  cd "$S01/frontend"
  npm ls lodash --all
) | tee "$OUT/npm-lodash.txt"

echo
echo "== Original shaded normalizer evidence =="
{
  echo "Relocated codec classes:"
  jar tf "$S01/normalizer/target/normalizer-1.0.0.jar" \
    | grep '^com/acme/internal/codec/' \
    | head -20 || true

  echo
  echo "Codec Maven metadata:"
  jar tf "$S01/normalizer/target/normalizer-1.0.0.jar" \
    | grep 'META-INF/maven/commons-codec/commons-codec/' || true
} | tee "$OUT/normalizer-original.txt"

echo
echo "== Metadata-stripped normalizer evidence =="
{
  echo "Relocated codec classes:"
  jar tf "$S01/trace-output/normalizer-no-codec-metadata.jar" \
    | grep '^com/acme/internal/codec/' \
    | head -20 || true

  echo
  echo "Codec Maven metadata:"
  jar tf "$S01/trace-output/normalizer-no-codec-metadata.jar" \
    | grep 'META-INF/maven/commons-codec/commons-codec/' || true
} | tee "$OUT/normalizer-stripped.txt"

echo
echo "== Service JAR physical evidence =="
jar tf "$S01/service/target/service-1.0.0.jar" \
  | grep -E \
    'BOOT-INF/lib/(jackson-databind|commons-codec|normalizer)|BOOT-INF/classes/static/' \
  | tee "$OUT/service-jar-tracers.txt" || true

echo
echo "== Frontend deployable boundary =="
find "$S01/frontend/dist" -maxdepth 3 -type f -print \
  | sort \
  | tee "$OUT/frontend-dist-files.txt"

echo
echo "== Build local container image =="
(
  cd "$S01"
  docker build -t "$IMAGE" .
) | tee "$OUT/docker-build.txt"

docker image inspect "$IMAGE" \
  --format '{{.Id}} {{json .RepoTags}} {{json .RepoDigests}}' \
  | tee "$OUT/image-identity.txt"

printf '%s\n' "$IMAGE" >"$OUT/image-name.txt"

echo
echo "T03 / S01 baseline captured."
