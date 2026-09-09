#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in python3 tar unzip jq; do
  require_command "$cmd"
done

S03="$(resolve_s03)" || {
  echo "Could not find S03-python-pep517. Set S03_DIR=/path/to/S03-python-pep517" >&2
  exit 1
}

OUT="$ROOT/results/s03/baseline"
mkdir -p "$OUT"

echo "S03: $S03"
echo "Output: $OUT"

echo
echo "== Build/install S03 =="
(
  cd "$S03"
  ./scripts/build.sh
) | tee "$OUT/build.txt"

echo
echo "== Direct declaration =="
cat "$S03/requirements.txt" | tee "$OUT/requirements.txt"

echo
echo "== reportkit wheel dependency metadata =="
unzip -p \
  "$S03/python-repo/reportkit-1.0.0-py3-none-any.whl" \
  reportkit-1.0.0.dist-info/METADATA \
  | tee "$OUT/reportkit-metadata.txt"

echo
echo "== tracehook-demo sdist contents =="
tar -tzf "$S03/python-repo/tracehook_demo-1.0.0.tar.gz" \
  | tee "$OUT/tracehook-sdist.txt"

echo
echo "== tracehook-demo PEP 517 declaration =="
tar -xOzf \
  "$S03/python-repo/tracehook_demo-1.0.0.tar.gz" \
  tracehook_demo-1.0.0/pyproject.toml \
  | tee "$OUT/tracehook-pyproject.toml"

echo
echo "== Source distribution generated-file check =="
if tar -tzf "$S03/python-repo/tracehook_demo-1.0.0.tar.gz" \
    | grep -E 'tracehook_demo/__init__\.py|tracehook_demo/build-hook\.json' \
    | tee "$OUT/sdist-generated-files.txt"
then
  :
else
  : >"$OUT/sdist-generated-files.txt"
  echo "(generated runtime files absent from sdist)"
fi

echo
echo "== Installed package list =="
"$S03/.venv/bin/python" -m pip list --format=json \
  | tee "$OUT/pip-list.json" \
  | jq -r '.[] | [.name,.version] | @tsv' \
  | tee "$OUT/pip-list.tsv"

echo
echo "== Installed generated marker =="
SITE=$("$S03/.venv/bin/python" - <<'PY'
import sysconfig
print(sysconfig.get_paths()["purelib"])
PY
)
printf '%s\n' "$SITE" >"$OUT/site-packages.txt"

MARKER="$SITE/tracehook_demo/build-hook.json"
if [[ -f "$MARKER" ]]; then
  cat "$MARKER" | tee "$OUT/build-hook.json"
else
  echo "marker not found" | tee "$OUT/build-hook.json"
fi

echo
echo "== Installed tracehook files =="
find "$SITE/tracehook_demo" -maxdepth 1 -type f -print \
  | sort \
  | tee "$OUT/installed-tracehook-files.txt"

echo
echo "== Relevant pip install log =="
grep -E \
  'reportkit|tracehook|Preparing metadata|Building wheel|pyproject' \
  "$S03/trace-output/pip-install.log" \
  | tee "$OUT/pip-install-relevant.txt" || true

echo
echo "T05 / S03 baseline captured."
