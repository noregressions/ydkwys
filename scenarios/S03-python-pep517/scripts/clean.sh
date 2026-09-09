#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PID_FILE=".runtime.pid"
LOG_FILE=".runtime.log"

echo "Cleaning S03 Python trace lab..."

if [[ -f "$PID_FILE" ]]; then
  pid=$(cat "$PID_FILE" 2>/dev/null || true)

  if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true

    for _ in $(seq 1 20); do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done

    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
    fi

    echo "Stopped Python runtime PID $pid"
  else
    echo "No live Python runtime found for recorded PID."
  fi
fi

rm -f "$PID_FILE" "$LOG_FILE"
rm -rf .venv trace-output

find . \
  -type d -name '__pycache__' \
  -not -path './python-repo/*' \
  -prune -exec rm -rf {} + 2>/dev/null || true

find . \
  -type f \( -name '*.pyc' -o -name '*.pyo' \) \
  -delete 2>/dev/null || true

echo "S03 clean."
echo
echo "Removed:"
echo "  .venv/"
echo "  trace-output/"
echo "  .runtime.pid"
echo "  .runtime.log"
echo "  Python cache files"
echo
echo "Kept:"
echo "  requirements.txt"
echo "  src/"
echo "  python-sources/"
echo "  python-repo/"
