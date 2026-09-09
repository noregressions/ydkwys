#!/usr/bin/env bash
# Build the workshop images for linux/amd64 + linux/arm64 and push them to
# Docker Hub as multi-arch manifests.
#
#   ./container/publish.sh 0.0.1          build + push both images:
#                                           noregressions/ydnwys-workshop-base:0.0.1  (+ :latest)
#                                           noregressions/ydnwys-workshop:0.0.1       (+ :latest)
#   ./container/publish.sh 0.0.1 --code   skip the base; build the code image on
#                                         top of the already published base
#
# Requirements:
#   - docker login as an account with write access to the noregressions
#     namespace
#   - Docker Desktop with the containerd image store enabled (the default),
#     or a docker-container buildx builder; either can produce multi-platform
#     images
#
# On an Apple silicon Mac the amd64 half runs under Rosetta/QEMU, so the full
# in-image build (Maven, npm, pip) for that platform takes a long time. The arm64
# half comes from the local build cache when ./container/build.sh has been
# run recently.
#
# To push only what was built locally (single platform, no rebuild):
#   docker tag shipping-workshop:latest noregressions/ydnwys-workshop:<version>
#   docker push noregressions/ydnwys-workshop:<version>
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=noregressions/ydnwys-workshop
PLATFORMS=linux/amd64,linux/arm64
VERSION="${1:?usage: $0 <version> [--code]}"

if [[ "${2:-}" != "--code" ]]; then
  echo "== Building + pushing base image: $REPO-base:$VERSION ($PLATFORMS) =="
  docker buildx build --platform "$PLATFORMS" \
    -f container/Dockerfile.base \
    -t "$REPO-base:$VERSION" -t "$REPO-base:latest" \
    --push container/
fi

echo "== Building + pushing workshop image: $REPO:$VERSION ($PLATFORMS) =="
docker buildx build --platform "$PLATFORMS" \
  -f container/Dockerfile \
  --build-arg "BASE_IMAGE=$REPO-base:$VERSION" \
  -t "$REPO:$VERSION" -t "$REPO:latest" \
  --push .
