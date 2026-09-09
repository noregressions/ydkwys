from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os

import reportkit


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            self._send(
                200,
                "text/plain; charset=utf-8",
                "Python PEP 517 trace lab\nGET /trace\n",
            )
            return

        if self.path == "/trace":
            payload = reportkit.runtime_trace()
            self._send(
                200,
                "application/json; charset=utf-8",
                json.dumps(payload, indent=2, sort_keys=True) + "\n",
            )
            return

        self._send(404, "text/plain; charset=utf-8", "Not found\n")

    def log_message(self, fmt, *args):
        pass

    def _send(self, status, content_type, body):
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    port = int(os.environ.get("PORT", "8080"))
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Python PEP 517 trace lab listening on http://localhost:{port}/", flush=True)
    print(f"Trace endpoint: http://localhost:{port}/trace", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
