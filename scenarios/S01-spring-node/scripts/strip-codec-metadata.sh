#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE="$ROOT/normalizer/target/normalizer-1.0.0.jar"
OUTDIR="$ROOT/trace-output"
TARGET="$OUTDIR/normalizer-no-codec-metadata.jar"
mkdir -p "$OUTDIR"

if [[ ! -f "$SOURCE" ]]; then
  echo "Build the project first: scripts/build.sh" >&2
  exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
  echo "This experiment requires the zip command." >&2
  exit 1
fi

cp "$SOURCE" "$TARGET"

echo "Before:"
jar tf "$TARGET" | grep 'META-INF/maven/commons-codec/commons-codec/' || true

zip -qd "$TARGET" 'META-INF/maven/commons-codec/commons-codec/*' || true

echo "After:"
jar tf "$TARGET" | grep 'META-INF/maven/commons-codec/commons-codec/' || true

echo
printf 'Controlled artifact written to %s\n' "$TARGET"
printf 'The relocated codec bytecode is unchanged; only identifying Maven metadata was removed.\n'

if command -v syft >/dev/null 2>&1; then
  echo
  echo "Original Syft result:"
  syft "$SOURCE" | grep -E 'commons-codec|normalizer' || true
  echo
  echo "Metadata-stripped Syft result:"
  syft "$TARGET" | grep -E 'commons-codec|normalizer' || true
fi
