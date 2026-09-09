#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in docker jq; do
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
echo "== Build image using the scenario's existing image trace =="
(
  cd "$S01"
  IMAGE="$IMAGE" ./scripts/image-trace.sh
) | tee "$OUT/image-trace.txt"

echo
echo "== Local image identity =="
docker image inspect "$IMAGE" \
  --format '{{.Id}} {{json .RepoTags}} {{json .RepoDigests}}' \
  | tee "$OUT/image-identity.txt"

echo
echo "== Image labels / attestable metadata visible to Docker =="
docker image inspect "$IMAGE" \
  --format '{{json .Config.Labels}}' \
  | jq . \
  | tee "$OUT/image-labels.json"

printf '%s\n' "$IMAGE" >"$OUT/image-name.txt"

echo
echo "S01 Docker Scout baseline captured."
