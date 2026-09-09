#!/usr/bin/env bash
# Run the workshop container.
#
#   ./container/run.sh                 pull (if needed) and run the published
#                                      image, noregressions/ydnwys-workshop
#   WORKSHOP_IMAGE=shipping-workshop:latest ./container/run.sh
#                                      run a locally built image instead
#                                      (see ./container/build.sh)
#
#   - mounts the host Docker socket: docker/scout/syft-on-images inside the
#     container operate on YOUR daemon (this is required for S01/S02 and
#     T02-T04)
#   - passes SNYK_TOKEN and NVD_API_KEY through when set locally
set -euo pipefail

WORKSHOP_IMAGE="${WORKSHOP_IMAGE:-noregressions/ydnwys-workshop:0.0.1}"

exec docker run --rm -it \
  --name shipping-workshop \
  --pull missing \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ${SNYK_TOKEN:+-e SNYK_TOKEN} \
  ${NVD_API_KEY:+-e NVD_API_KEY} \
  "$WORKSHOP_IMAGE"
