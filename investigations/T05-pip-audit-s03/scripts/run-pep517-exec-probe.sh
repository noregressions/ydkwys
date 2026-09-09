#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in pip-audit python3 tar; do
  require_command "$cmd"
done

S03="$(resolve_s03)" || {
  echo "Could not find S03-python-pep517. Set S03_DIR=/path/to/S03-python-pep517" >&2
  exit 1
}

OUT="$ROOT/results/s03/pip-audit"
PROBE="$OUT/pep517-probe-corrected"

rm -rf "$PROBE"
mkdir -p \
  "$PROBE/src" \
  "$PROBE/index/simple/reportkit" \
  "$PROBE/index/simple/tracehook-demo"

cp "$S03/python-repo/reportkit-1.0.0-py3-none-any.whl" \
  "$PROBE/index/simple/reportkit/"

tar -xzf "$S03/python-repo/tracehook_demo-1.0.0.tar.gz" -C "$PROBE/src"

python3 - "$PROBE/src/tracehook_demo-1.0.0/tracehook_backend.py" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines(True)

probe = [
    "import os\n",
    "from pathlib import Path as _T05ProbePath\n",
    "_t05_probe = os.environ.get('T05_AUDIT_MARKER')\n",
    "if _t05_probe:\n",
    "    _T05ProbePath(_t05_probe).write_text(\n",
    "        'tracehook_backend imported during pip-audit dependency resolution\\n',\n",
    "        encoding='utf-8',\n",
    "    )\n",
    "\n",
]

insert_at = 0
while insert_at < len(lines):
    line = lines[insert_at]
    if line.startswith("from __future__ import "):
        insert_at += 1
        continue
    if line.strip() == "":
        insert_at += 1
        continue
    break

lines[insert_at:insert_at] = probe
path.write_text("".join(lines), encoding="utf-8")
PY

python3 - "$PROBE/src" "$PROBE/index/simple/tracehook-demo/tracehook_demo-1.0.0.tar.gz" <<'PY'
from pathlib import Path
import sys
import tarfile

src_root = Path(sys.argv[1])
archive = Path(sys.argv[2])
project = src_root / "tracehook_demo-1.0.0"

with tarfile.open(archive, "w:gz", format=tarfile.PAX_FORMAT) as tf:
    for path in sorted(project.rglob("*")):
        tf.add(path, arcname=str(Path(project.name) / path.relative_to(project)))
PY

cat >"$PROBE/index/simple/reportkit/index.html" <<'HTML'
<!doctype html>
<html><body>
<a href="reportkit-1.0.0-py3-none-any.whl">reportkit-1.0.0-py3-none-any.whl</a>
</body></html>
HTML

cat >"$PROBE/index/simple/tracehook-demo/index.html" <<'HTML'
<!doctype html>
<html><body>
<a href="tracehook_demo-1.0.0.tar.gz">tracehook_demo-1.0.0.tar.gz</a>
</body></html>
HTML

PROBE_INDEX="$(python3 - "$PROBE/index/simple" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve().as_uri())
PY
)"

MARKER="$OUT/pep517-audit-executed.txt"
rm -f "$MARKER"

set +e
T05_AUDIT_MARKER="$MARKER" \
PIP_NO_CACHE_DIR=1 \
pip-audit \
  --progress-spinner off \
  --dry-run \
  -r "$S03/requirements.txt" \
  --index-url "$PROBE_INDEX" \
  >"$OUT/pep517-probe-corrected.txt" 2>&1
rc=$?
set -e
printf '%s\n' "$rc" >"$OUT/pep517-probe-corrected.exit"

cat "$OUT/pep517-probe-corrected.txt"

echo
if [[ -f "$MARKER" ]]; then
  echo "PEP 517 execution marker:"
  cat "$MARKER"
else
  echo "PEP 517 execution marker: NOT CREATED"
fi
