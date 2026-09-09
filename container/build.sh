#!/usr/bin/env bash
# Build the workshop images.
#
#   ./container/build.sh          build the code image (builds the base
#                                 first only if it doesn't exist yet)
#   ./container/build.sh --base   force-rebuild the tools/base image too
#                                 (it refreshes the scanner databases, so use
#                                 it when the image's data has gone stale)
set -euo pipefail
cd "$(dirname "$0")/.."

BASE_TAG=shipping-workshop-base:latest
CODE_TAG=shipping-workshop:latest

if [[ "${1:-}" == "--base" ]] || ! docker image inspect "$BASE_TAG" >/dev/null 2>&1; then
  echo "== Building tools/base image ($BASE_TAG) =="
  docker build -f container/Dockerfile.base -t "$BASE_TAG" container/
fi

echo "== Building workshop code image ($CODE_TAG) =="
exec docker build -f container/Dockerfile -t "$CODE_TAG" .
