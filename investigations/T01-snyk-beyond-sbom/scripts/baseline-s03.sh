#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

for cmd in python3 jq unzip tar grep find; do
  require_command "$cmd"
done

S03="$(resolve_s03)" || {
  echo "Could not find S03-python-pep517." >&2
  echo "Set S03_DIR=/path/to/S03-python-pep517" >&2
  exit 1
}

OUT="$ROOT/results/s03/baseline"
mkdir -p "$OUT"

echo "S03: $S03"
echo "Output: $OUT"

echo
echo "== Build S03 from a fresh virtual environment =="
(
  cd "$S03"
  ./scripts/build.sh
) >"$OUT/build.log" 2>&1
cat "$OUT/build.log"

PY="$S03/.venv/bin/python"
[[ -x "$PY" ]] || {
  echo "Expected virtualenv Python not found: $PY" >&2
  exit 1
}

"$PY" -V | tee "$OUT/python-version.txt"

SITE_PACKAGES="$("$PY" - <<'PY'
import site
print(site.getsitepackages()[0])
PY
)"
printf '%s\n' "$SITE_PACKAGES" >"$OUT/site-packages-path.txt"

echo
echo "== Application declaration =="
cat "$S03/requirements.txt" | tee "$OUT/requirements.txt"

echo
echo "== Direct wheel metadata =="
unzip -p "$S03/python-repo/reportkit-1.0.0-py3-none-any.whl" \
  reportkit-1.0.0.dist-info/METADATA \
  | tee "$OUT/reportkit-metadata.txt"

echo
echo "== Transitive sdist contents =="
tar -tzf "$S03/python-repo/tracehook_demo-1.0.0.tar.gz" \
  | tee "$OUT/tracehook-sdist-files.txt"

echo
echo "== Generated runtime files are absent from the sdist =="
tar -tzf "$S03/python-repo/tracehook_demo-1.0.0.tar.gz" \
  | grep -E 'tracehook_demo/__init__\.py|build-hook\.json' \
  | tee "$OUT/sdist-generated-file-hits.txt" || true

echo
echo "== PEP 517 backend declaration =="
tar -xOzf "$S03/python-repo/tracehook_demo-1.0.0.tar.gz" \
  tracehook_demo-1.0.0/pyproject.toml \
  | tee "$OUT/tracehook-pyproject.toml"

echo
echo "== Build backend generation logic =="
tar -xOzf "$S03/python-repo/tracehook_demo-1.0.0.tar.gz" \
  tracehook_demo-1.0.0/tracehook_backend.py \
  | grep -nE 'def build_wheel|__init__\.py|build-hook\.json|pep517-build-backend-executed' \
  | tee "$OUT/tracehook-backend-relevant.txt" || true

echo
echo "== pip build/install evidence =="
grep -E \
  'Processing .*tracehook_demo|Getting requirements to build wheel|Building wheel for tracehook-demo|Created wheel for tracehook-demo|Successfully built tracehook-demo|Successfully installed' \
  "$S03/trace-output/pip-install.log" \
  | tee "$OUT/pip-build-evidence.txt" || true

echo
echo "== Installed package set =="
"$PY" -m pip freeze | tee "$OUT/pip-freeze.txt"

echo
echo "== Installed package metadata =="
"$PY" -m pip show reportkit tracehook-demo \
  | tee "$OUT/pip-show.txt"

echo
echo "== pip inspect metadata =="
"$PY" -m pip inspect >"$OUT/pip-inspect.json"
jq '
  .installed[]
  | select(
      (.metadata.name // "" | ascii_downcase) == "reportkit"
      or (.metadata.name // "" | ascii_downcase) == "tracehook-demo"
    )
  | {
      metadata: {
        name: .metadata.name,
        version: .metadata.version,
        requires_dist: .metadata.requires_dist
      },
      requested,
      installer,
      direct_url
    }
' "$OUT/pip-inspect.json" | tee "$OUT/pip-inspect-tracers.txt"

echo
echo "== Generated files in installed environment =="
find "$SITE_PACKAGES/tracehook_demo" -maxdepth 1 -type f -print \
  | sort \
  | tee "$OUT/installed-tracehook-files.txt"

echo
echo "== Generated marker =="
cat "$SITE_PACKAGES/tracehook_demo/build-hook.json" \
  | tee "$OUT/build-hook.json"

echo
echo "== Runtime import =="
"$PY" -c 'import reportkit; print(reportkit.runtime_trace())' \
  | tee "$OUT/runtime-trace.txt"

echo
echo "== Build and retain the generated tracehook wheel =="
rm -rf "$OUT/wheels" "$OUT/wheel-unpacked" "$OUT/sdist-unpacked"
mkdir -p "$OUT/wheels" "$OUT/wheel-unpacked" "$OUT/sdist-unpacked"

"$PY" -m pip wheel \
  --disable-pip-version-check \
  --no-deps \
  --no-cache-dir \
  --no-index \
  --find-links="$S03/python-repo" \
  --wheel-dir="$OUT/wheels" \
  tracehook-demo==1.0.0 \
  2>&1 | tee "$OUT/pip-wheel.log"

WHEEL="$(find "$OUT/wheels" -maxdepth 1 -type f -name 'tracehook_demo-1.0.0-*.whl' | head -1)"
[[ -n "${WHEEL:-}" && -f "$WHEEL" ]] || {
  echo "Generated tracehook wheel not found." >&2
  exit 1
}
printf '%s\n' "$WHEEL" >"$OUT/wheel-path.txt"

unzip -q "$WHEEL" -d "$OUT/wheel-unpacked"

echo
echo "Generated wheel contents:"
unzip -l "$WHEEL" \
  | grep -E 'tracehook_demo/__init__\.py|tracehook_demo/build-hook\.json|dist-info/(METADATA|RECORD)' \
  | tee "$OUT/generated-wheel-relevant-files.txt" || true

echo
echo "Generated wheel package metadata:"
unzip -p "$WHEEL" tracehook_demo-1.0.0.dist-info/METADATA \
  | tee "$OUT/generated-wheel-metadata.txt"

tar -xzf "$S03/python-repo/tracehook_demo-1.0.0.tar.gz" \
  -C "$OUT/sdist-unpacked" \
  --strip-components=1

if command -v syft >/dev/null 2>&1; then
  echo
  echo "== Syft generated wheel baseline =="
  syft "$WHEEL" | tee "$OUT/syft-wheel.txt"

  echo
  echo "== Syft installed site-packages baseline =="
  syft "dir:$SITE_PACKAGES" | tee "$OUT/syft-site-packages.txt"
else
  echo "Syft not installed." | tee "$OUT/syft-wheel.txt"
  echo "Syft not installed." | tee "$OUT/syft-site-packages.txt"
fi

echo
echo "S03 baseline captured in $OUT"
