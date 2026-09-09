#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE="payara-mvnpm-trace-lab:local"
mkdir -p trace-output

docker build -t "$IMAGE" .

docker image inspect "$IMAGE" \
  --format 'image={{.RepoTags}} id={{.Id}}'

if command -v syft >/dev/null 2>&1; then
  syft "$IMAGE" -o cyclonedx-json=trace-output/image.cdx.json
  echo
  jq -r '.components[] | [.name, .version] | @tsv' trace-output/image.cdx.json \
    | grep -E 'commons-lang3|lodash-es|payara-mvnpm-trace-lab|jakarta\.' || true
else
  echo "Syft is not installed; skipping image SBOM generation."
fi
