#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/trace-output"
IMAGE=${IMAGE:-registry.example.com/checkout-service:release-123}
mkdir -p "$OUT"
cd "$ROOT"

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }

docker build -t "$IMAGE" .

echo
printf 'Local image: %s\n' "$IMAGE"
docker image inspect "$IMAGE" \
  --format '{{.Id}} {{json .RepoTags}} {{json .RepoDigests}}' \
  | tee "$OUT/local-image-identity.txt"

if command -v syft >/dev/null 2>&1; then
  syft "$IMAGE" -o cyclonedx-json="$OUT/image.cdx.json"
  jq '.components[] | select(.name == "jackson-databind" or .name == "normalizer" or .name == "commons-codec" or .name == "lodash") | {name,version,purl}' \
    "$OUT/image.cdx.json" || true
fi
