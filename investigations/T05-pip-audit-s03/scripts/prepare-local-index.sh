#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

S03="$(resolve_s03)" || {
  echo "Could not find S03-python-pep517. Set S03_DIR=/path/to/S03-python-pep517" >&2
  exit 1
}

OUT="$ROOT/results/s03/local-index"
rm -rf "$OUT"
mkdir -p \
  "$OUT/simple/reportkit" \
  "$OUT/simple/tracehook-demo"

cp "$S03/python-repo/reportkit-1.0.0-py3-none-any.whl" \
  "$OUT/simple/reportkit/"
cp "$S03/python-repo/tracehook_demo-1.0.0.tar.gz" \
  "$OUT/simple/tracehook-demo/"

cat >"$OUT/simple/reportkit/index.html" <<'HTML'
<!doctype html>
<html><body>
<a href="reportkit-1.0.0-py3-none-any.whl">reportkit-1.0.0-py3-none-any.whl</a>
</body></html>
HTML

cat >"$OUT/simple/tracehook-demo/index.html" <<'HTML'
<!doctype html>
<html><body>
<a href="tracehook_demo-1.0.0.tar.gz">tracehook_demo-1.0.0.tar.gz</a>
</body></html>
HTML

python3 - "$OUT/simple" >"$OUT/index-url.txt" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve().as_uri())
PY

echo "Local PEP 503 index:"
cat "$OUT/index-url.txt"
