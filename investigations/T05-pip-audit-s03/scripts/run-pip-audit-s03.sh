#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in pip-audit jq python3; do
  require_command "$cmd"
done

S03="$(resolve_s03)" || {
  echo "Could not find S03-python-pep517. Set S03_DIR=/path/to/S03-python-pep517" >&2
  exit 1
}

BASE="$ROOT/results/s03/baseline"
IDX="$ROOT/results/s03/local-index"
OUT="$ROOT/results/s03/pip-audit"
mkdir -p "$OUT"

[[ -f "$BASE/site-packages.txt" ]] || {
  echo "Run ./scripts/baseline-s03.sh first." >&2
  exit 1
}

"$ROOT/scripts/prepare-local-index.sh"
INDEX_URL="$(cat "$IDX/index-url.txt")"
SITE="$(cat "$BASE/site-packages.txt")"

pip-audit --version | tee "$OUT/version.txt"

echo
echo "== A. requirements dry-run WITH dependency resolution =="
set +e
PIP_PROGRESS_BAR=off pip-audit \
  -vv \
  --progress-spinner off \
  --dry-run \
  -r "$S03/requirements.txt" \
  --index-url "$INDEX_URL" \
  >"$OUT/requirements-resolved-dry-run.txt" 2>&1
rc=$?
set -e
printf '%s\n' "$rc" >"$OUT/requirements-resolved-dry-run.exit"
cat "$OUT/requirements-resolved-dry-run.txt"

grep -Ei \
  'reportkit|tracehook|pep.?517|pyproject|metadata|wheel|would have audited|collected' \
  "$OUT/requirements-resolved-dry-run.txt" \
  | tee "$OUT/requirements-resolved-signals.txt" || true

echo
echo "== A2. controlled PEP 517 execution probe during audit resolution =="

PROBE="$OUT/pep517-probe"
rm -rf "$PROBE"
mkdir -p "$PROBE/src" "$PROBE/index/simple/reportkit" "$PROBE/index/simple/tracehook-demo"

cp "$S03/python-repo/reportkit-1.0.0-py3-none-any.whl" \
  "$PROBE/index/simple/reportkit/"

tar -xzf "$S03/python-repo/tracehook_demo-1.0.0.tar.gz" -C "$PROBE/src"

python3 - "$PROBE/src/tracehook_demo-1.0.0/tracehook_backend.py" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
probe = (
    'import os\n'
    'from pathlib import Path as _ProbePath\n'
    '_probe = os.environ.get("T05_AUDIT_MARKER")\n'
    'if _probe:\n'
    '    _ProbePath(_probe).write_text('
    '"tracehook_backend imported during pip-audit dependency resolution\\n", '
    'encoding="utf-8")\n'
)
path.write_text(probe + text, encoding="utf-8")
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

echo "Instrumented sdist contents:"
tar -tzf "$PROBE/index/simple/tracehook-demo/tracehook_demo-1.0.0.tar.gz" \
  | tee "$OUT/pep517-probe-sdist.txt"

grep -Fq 'tracehook_demo-1.0.0/pyproject.toml' "$OUT/pep517-probe-sdist.txt" || {
  echo "Probe sdist is missing pyproject.toml" >&2
  exit 1
}

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

PROBE_MARKER="$OUT/pep517-audit-executed.txt"
rm -f "$PROBE_MARKER"

set +e
T05_AUDIT_MARKER="$PROBE_MARKER" \
PIP_NO_CACHE_DIR=1 \
pip-audit \
  --progress-spinner off \
  --dry-run \
  -r "$S03/requirements.txt" \
  --index-url "$PROBE_INDEX" \
  >"$OUT/pep517-probe.txt" 2>&1
rc=$?
set -e
printf '%s\n' "$rc" >"$OUT/pep517-probe.exit"
cat "$OUT/pep517-probe.txt"

if [[ -f "$PROBE_MARKER" ]]; then
  echo "PEP 517 execution marker:"
  cat "$PROBE_MARKER"
else
  echo "PEP 517 execution marker: NOT CREATED"
fi

echo
echo "== B. requirements audit WITH dependency resolution =="
set +e
pip-audit \
  --progress-spinner off \
  -f json \
  -r "$S03/requirements.txt" \
  --index-url "$INDEX_URL" \
  >"$OUT/requirements-resolved.json" \
  2>"$OUT/requirements-resolved.log"
rc=$?
set -e
printf '%s\n' "$rc" >"$OUT/requirements-resolved.exit"
cat "$OUT/requirements-resolved.log"
cat "$OUT/requirements-resolved.json" | jq .

jq -r '
  .dependencies[]?
  | [
      .name,
      .version,
      (.skip_reason // ""),
      ((.vulns // []) | length | tostring)
    ]
  | @tsv
' "$OUT/requirements-resolved.json" \
  | tee "$OUT/requirements-resolved.tsv"

echo
echo "== C. requirements audit with --no-deps =="
set +e
pip-audit \
  --progress-spinner off \
  --no-deps \
  -f json \
  -r "$S03/requirements.txt" \
  --index-url "$INDEX_URL" \
  >"$OUT/requirements-no-deps.json" \
  2>"$OUT/requirements-no-deps.log"
rc=$?
set -e
printf '%s\n' "$rc" >"$OUT/requirements-no-deps.exit"
cat "$OUT/requirements-no-deps.log"
cat "$OUT/requirements-no-deps.json" | jq .

jq -r '
  .dependencies[]?
  | [
      .name,
      .version,
      (.skip_reason // ""),
      ((.vulns // []) | length | tostring)
    ]
  | @tsv
' "$OUT/requirements-no-deps.json" \
  | tee "$OUT/requirements-no-deps.tsv"

echo
echo "== C2. requirements audit with --no-deps --disable-pip =="

set +e
pip-audit \
  --progress-spinner off \
  --no-deps \
  --disable-pip \
  -f json \
  -r "$S03/requirements.txt" \
  >"$OUT/requirements-no-deps-disable-pip.json" \
  2>"$OUT/requirements-no-deps-disable-pip.log"
rc=$?
set -e
printf '%s\n' "$rc" >"$OUT/requirements-no-deps-disable-pip.exit"
cat "$OUT/requirements-no-deps-disable-pip.log"
cat "$OUT/requirements-no-deps-disable-pip.json" | jq .

jq -r '
  .dependencies[]?
  | [
      .name,
      .version,
      (.skip_reason // ""),
      ((.vulns // []) | length | tostring)
    ]
  | @tsv
' "$OUT/requirements-no-deps-disable-pip.json" \
  | tee "$OUT/requirements-no-deps-disable-pip.tsv"

echo
echo "== D. installed-environment audit =="
set +e
pip-audit \
  --progress-spinner off \
  --path "$SITE" \
  -f json \
  >"$OUT/installed.json" \
  2>"$OUT/installed.log"
rc=$?
set -e
printf '%s\n' "$rc" >"$OUT/installed.exit"
cat "$OUT/installed.log"
cat "$OUT/installed.json" | jq .

jq -r '
  .dependencies[]?
  | [
      .name,
      .version,
      (.skip_reason // ""),
      ((.vulns // []) | length | tostring)
    ]
  | @tsv
' "$OUT/installed.json" \
  | tee "$OUT/installed.tsv"

echo
echo "== E. pip-audit CycloneDX from installed environment =="
set +e
pip-audit \
  --progress-spinner off \
  --path "$SITE" \
  -f cyclonedx-json \
  >"$OUT/installed.cdx.json" \
  2>"$OUT/installed-cdx.log"
rc=$?
set -e
printf '%s\n' "$rc" >"$OUT/installed-cdx.exit"
cat "$OUT/installed-cdx.log"

if jq -e . "$OUT/installed.cdx.json" >/dev/null 2>&1; then
  jq -r '
    .components[]?
    | [.name, (.version // "")]
    | @tsv
  ' "$OUT/installed.cdx.json" \
    | tee "$OUT/installed-cdx-components.tsv"
fi

echo
echo "T05 pip-audit probes captured."
echo "Run:"
echo "  ./scripts/compare-s03.sh"
