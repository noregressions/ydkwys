#!/usr/bin/env bash
# Remove every T11 probe output. The scans are service calls, so re-running
# after a clean can legitimately produce different lifecycle answers.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rm -rf "$ROOT/results"
echo "Cleaned: $ROOT/results"
