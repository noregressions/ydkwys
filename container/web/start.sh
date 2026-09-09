#!/usr/bin/env bash
# Start the browser workshop view INSIDE the container.
#
# Two processes, two ports:
#   ttyd      the terminal half  (default 7681) -- xterm.js, served by ttyd
#   serve.py  the instructions   (default 7680) -- the page you open
#
# The host-side wrapper is container/web.sh; it publishes both ports and
# opens a browser. Run this directly only if you are already in a shell in
# the container and want the view alongside it.
set -euo pipefail

WEB_PORT="${WEB_PORT:-7680}"
TTYD_PORT="${TTYD_PORT:-7681}"
export WEB_PORT TTYD_PORT

WEB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSHOP_DIR="$(cd "$WEB_DIR/../.." && pwd)"

if ! command -v ttyd >/dev/null 2>&1; then
  echo "error: ttyd is not in this image." >&2
  echo "       Rebuild it: ./container/build.sh   (container/Dockerfile installs ttyd)" >&2
  exit 1
fi

# One process group, so closing the view takes both halves down together and
# does not leave a shell server listening on a published port.
cleanup() { trap - EXIT; kill 0 2>/dev/null || true; }
trap cleanup EXIT INT TERM

cd "$WORKSHOP_DIR"

# -W  writable: without it the terminal is read-only, which is not a workshop
# -t  xterm.js client options, themed to match the instructions pane
ttyd \
  --writable \
  --port "$TTYD_PORT" \
  --interface 0.0.0.0 \
  --cwd "$WORKSHOP_DIR" \
  -t fontSize=13 \
  -t 'fontFamily=SFMono-Regular,Menlo,Consolas,Liberation Mono,monospace' \
  -t scrollback=10000 \
  -t titleFixed="workshop shell" \
  -t 'theme={"background":"#010409","foreground":"#e6edf3","cursor":"#4ea1ff","selectionBackground":"#1f4a7a"}' \
  bash &

python3 "$WEB_DIR/serve.py" &

cat <<BANNER

  Workshop view up:

    split view                http://localhost:${WEB_PORT}
      a page on the left, a shell on the right; the picker lists every
      generated lesson, cheat sheet and part

    browse the book           http://localhost:${WEB_PORT}/site/index.html
      read it normally, then hit "Open with terminal" on any page to get
      that page in the split view

    terminal only             http://localhost:${TTYD_PORT}
      a second tab here is a second, independent shell

  Ctrl-C stops both.

BANNER

# Either half dying should stop the other rather than leave half a view up.
wait -n
