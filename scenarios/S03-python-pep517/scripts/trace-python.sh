#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== Direct declaration =="
cat requirements.txt
echo

echo "== reportkit wheel metadata =="
unzip -p python-repo/reportkit-1.0.0-py3-none-any.whl \
  reportkit-1.0.0.dist-info/METADATA
echo

echo "== transitive sdist contents =="
tar -tzf python-repo/tracehook_demo-1.0.0.tar.gz
echo

echo "== PEP 517 backend declaration =="
tar -xOzf python-repo/tracehook_demo-1.0.0.tar.gz \
  tracehook_demo-1.0.0/pyproject.toml
echo

echo "== installed generated marker =="
find .venv -path '*site-packages/tracehook_demo/build-hook.json' \
  -print -exec cat {} \; 2>/dev/null || true
echo

echo "== installed package metadata =="
.venv/bin/python -m pip show reportkit tracehook-demo 2>/dev/null || true
