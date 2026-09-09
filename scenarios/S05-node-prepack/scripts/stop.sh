#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PID_FILE=.runtime.pid
if [[ ! -f "$PID_FILE" ]]; then
  echo "No runtime PID file found."
  exit 0
fi
pid=$(cat "$PID_FILE" 2>/dev/null || true)
if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
  kill "$pid"
  echo "Stopped runtime PID $pid"
else
  echo "Runtime PID is not running."
fi
rm -f "$PID_FILE"
