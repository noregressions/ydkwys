#!/usr/bin/env bash
set -euo pipefail

docker rm -f payara-mvnpm-trace-lab >/dev/null 2>&1 || true
