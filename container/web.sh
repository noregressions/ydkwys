#!/usr/bin/env bash
# Run the workshop container with the browser view: a terminal into the
# container on one side, copy-ready instructions on the other.
#
#   ./container/web.sh                  run the published image
#   WORKSHOP_IMAGE=shipping-workshop:latest ./container/web.sh
#                                       run a locally built image
#   WEB_PORT=9000 ./container/web.sh    move the ports if they clash
#
# Same container as ./container/run.sh -- host Docker socket, SNYK_TOKEN and
# NVD_API_KEY passed through -- but with the two view ports published and
# the view, rather than a bare shell, as the command. The shell you get in
# the browser is a shell in this container, so every cheatsheet command
# behaves exactly as it does under run.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

WORKSHOP_IMAGE="${WORKSHOP_IMAGE:-noregressions/ydnwys-workshop:0.0.1}"
WEB_PORT="${WEB_PORT:-7680}"
TTYD_PORT="${TTYD_PORT:-7681}"
CONTAINER_NAME="${CONTAINER_NAME:-shipping-workshop-web}"

# The labs already claim 3000, 5000, 8080-8083 and 8208; 7680/7681 are clear
# of those, but say so plainly if something else on this machine has them.
for port in "$WEB_PORT" "$TTYD_PORT"; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "error: port $port is already in use on this machine." >&2
    echo "       lsof -nP -iTCP:$port -sTCP:LISTEN     # who has it" >&2
    echo "       WEB_PORT=9000 TTYD_PORT=9001 $0       # or move both" >&2
    exit 1
  fi
done

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "error: a container named $CONTAINER_NAME already exists." >&2
  echo "       docker rm -f $CONTAINER_NAME" >&2
  exit 1
fi

# Open the browser once the page actually answers, in the background, so the
# container can hold the foreground and Ctrl-C still stops it.
open_when_ready() {
  local url="http://localhost:${WEB_PORT}"
  for _ in $(seq 1 60); do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then
      case "$(uname -s)" in
        Darwin) open "$url" ;;
        Linux)  command -v xdg-open >/dev/null && xdg-open "$url" >/dev/null 2>&1 ;;
      esac
      return
    fi
    sleep 0.5
  done
  echo "note: $url did not come up in 30s; open it by hand once it does." >&2
}

[[ "${NO_BROWSER:-}" == "1" ]] || open_when_ready &

exec docker run --rm -it \
  --name "$CONTAINER_NAME" \
  --pull missing \
  -p "${WEB_PORT}:${WEB_PORT}" \
  -p "${TTYD_PORT}:${TTYD_PORT}" \
  -e WEB_PORT="$WEB_PORT" \
  -e TTYD_PORT="$TTYD_PORT" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ${SNYK_TOKEN:+-e SNYK_TOKEN} \
  ${NVD_API_KEY:+-e NVD_API_KEY} \
  "$WORKSHOP_IMAGE" \
  /workshop/container/web/start.sh
