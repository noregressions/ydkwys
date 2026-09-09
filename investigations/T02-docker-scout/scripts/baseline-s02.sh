#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in docker jq; do
  require_command "$cmd"
done

S02="$(resolve_s02)" || {
  echo "Could not find S02-payara-mvnpm. Set S02_DIR=/path/to/S02-payara-mvnpm" >&2
  exit 1
}

OUT="$ROOT/results/s02/baseline"
mkdir -p "$OUT"

IMAGE="${S02_IMAGE:-payara-mvnpm-trace-lab:local}"

echo "S02: $S02"
echo "Image: $IMAGE"
echo "Output: $OUT"

echo
echo "== Build image using the scenario's existing image trace =="
(
  cd "$S02"
  ./scripts/image-trace.sh
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
echo "S02 Docker Scout baseline captured."
