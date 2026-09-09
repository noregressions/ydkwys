#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PYTHON="${PYTHON:-python3}"

rm -rf .venv trace-output
mkdir -p trace-output

"$PYTHON" -m venv .venv

.venv/bin/python -m pip install \
  --disable-pip-version-check \
  --no-cache-dir \
  --no-index \
  --find-links=python-repo \
  -r requirements.txt \
  2>&1 | tee trace-output/pip-install.log

echo
echo "Installed packages:"
.venv/bin/python -m pip freeze
