#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${PORT:-8083}"
PID_FILE=.runtime.pid
LOG_FILE=.runtime.log

if [[ ! -d node_modules/trace-route-package ]]; then
  echo "Missing installed package. Run ./scripts/build.sh first." >&2
  exit 1
fi

if [[ -f "$PID_FILE" ]]; then
  old_pid=$(cat "$PID_FILE" 2>/dev/null || true)
  if [[ -n "${old_pid:-}" ]] && kill -0 "$old_pid" 2>/dev/null; then
    echo "Runtime already running as PID $old_pid" >&2
    exit 1
  fi
  rm -f "$PID_FILE"
fi

if curl -fsS --max-time 1 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
  echo "Port ${PORT} is already serving HTTP. Choose another port." >&2
  exit 1
fi

: > "$LOG_FILE"
PORT="$PORT" nohup node src/server.js >"$LOG_FILE" 2>&1 &
pid=$!
echo "$pid" > "$PID_FILE"

for _ in $(seq 1 30); do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "Runtime exited before becoming ready." >&2
    cat "$LOG_FILE" >&2 || true
    rm -f "$PID_FILE"
    exit 1
  fi

  body=$(curl -fsS --max-time 1 "http://127.0.0.1:${PORT}/health" 2>/dev/null || true)
  if [[ "$body" == *'"application": "node-prepack-trace-lab"'* ]] \
     && [[ "$body" == *'"status": "UP"'* ]]; then
    echo "Runtime started as PID $pid"
    echo "Open:   http://localhost:${PORT}/"
    echo "Health: http://localhost:${PORT}/health"
    echo "Trace:  http://localhost:${PORT}/hidden/prepack-info"
    exit 0
  fi
  sleep 1
done

echo "Runtime did not become ready." >&2
cat "$LOG_FILE" >&2 || true
kill "$pid" 2>/dev/null || true
rm -f "$PID_FILE"
exit 1
