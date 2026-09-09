#!/usr/bin/env bash
# Make the SBOM+ plugin resolvable up front, for example when building out
# a machine or a container image.
#
#   ./scripts/seed-plugin.sh                 # into ~/.m2
#   ./scripts/seed-plugin.sh /path/to/repo   # into a scenario-local repository
set -euo pipefail
source "$(dirname "$0")/common.sh"
need mvn
ensure_plugin "${1:-}"
