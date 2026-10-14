#!/usr/bin/env python3
"""
Zero-dependency HTTP API for the Grounded Standards Assistant (stdlib only).

Serves the engine over HTTP so the frontend prototype is runnable without the
full BioMate stack:

    POST /api/grounded/answer   {"question": "...", "user": "alice"}  -> GroundedAnswer dict
    GET  /                      -> the self-contained demo page (demo.html)
    GET  /health                -> {"ok": true}

Run:
    python3 grounded-prototype/mcp_server/http_api.py          # port 7788
    PORT=9000 python3 grounded-prototype/mcp_server/http_api.py

Production mapping: this is the exact contract the real route should implement.
In BioMate, `POST /api/grounded/answer` is added to the Node frontend
(frontend/server/routes.ts) which proxies to a Galaxy backend handler that calls
the engine. The frontend component + API client below are already written
against this path, so wiring is drop-in. See the design doc for the manifest +
route steps.
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))

from engine import ask, to_dict  # noqa: E402

_DEMO_HTML = os.path.join(os.path.dirname(_HERE), "frontend", "demo.html")


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        payload = body if isinstance(body, bytes) else json.dumps(body, default=str).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(payload)))
        # Prototype runs on a different port than the host page during local dev.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(payload)

    def do_OPTIONS(self):
        self._send(204, b"", ctype="text/plain")

    def do_GET(self):
        if self.path in ("/", "/index.html", "/demo", "/demo.html"):
            try:
                with open(_DEMO_HTML, "rb") as fh:
                    self._send(200, fh.read(), ctype="text/html; charset=utf-8")
            except FileNotFoundError:
                self._send(404, {"error": "demo.html not found"})
            return
        if self.path == "/health":
            self._send(200, {"ok": True})
            return
        self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/api/grounded/answer":
            self._send(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._send(400, {"error": "invalid JSON body"})
            return
        question = data.get("question")
        if not question:
            self._send(400, {"error": "'question' is required"})
            return
        user = data.get("user") or "anonymous"
        domain = data.get("domain") or None
        try:
            answer = ask(question, user=user, domain=domain)
            self._send(200, to_dict(answer))
        except Exception as exc:  # pragma: no cover
            self._send(500, {"error": str(exc)})

    def log_message(self, *_args):  # quiet
        pass


def main():
    port = int(os.environ.get("PORT", "7788"))
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Grounded Standards Assistant API on http://127.0.0.1:{port}  "
          f"(demo page at http://127.0.0.1:{port}/)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.shutdown()


if __name__ == "__main__":
    main()
