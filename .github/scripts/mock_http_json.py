#!/usr/bin/env python3
"""Minimal JSON HTTP mock for Tekton task tests (``http_json`` in mocks.yaml).

Started by bash emitted by ``render_python_task_mocks_from_yaml.py``. The renderer
copies this file into the task step script at merge time (the pod has no git
checkout).

Environment:
  TEKTON_ROUTES_B64: base64-encoded JSON list of route rules (see mocks.yaml).
  TEKTON_HTTP_BIND: listen address (default ``127.0.0.1``).

Arguments:
  port: TCP port to bind (integer).
"""

from __future__ import annotations

import base64
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse


def _routes_from_env() -> list[dict]:
    # Populated by render_python_task_mocks_from_yaml.py from mocks.yaml routes.
    raw = os.environ.get("TEKTON_ROUTES_B64", "")
    if not raw:
        msg = "TEKTON_ROUTES_B64 is required"
        raise SystemExit(msg)
    return json.loads(base64.standard_b64decode(raw))


class _Handler(BaseHTTPRequestHandler):
    # Set on the class in main(): BaseHTTPRequestHandler builds a new instance per
    # request, so instance attributes would not be shared across connections.
    routes: list[dict]

    def log_message(self, *_args: object) -> None:
        # Keep Tekton step logs readable; every GET would otherwise print a line.
        return

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        body = None
        # Order in mocks.yaml matters: first matching rule wins (not most specific).
        for rule in self.routes:
            suf = rule.get("path_suffix")
            if suf is not None:
                # Match both "/auth/token" and "/auth/token/" style paths.
                if path.endswith(suf) or path.endswith(suf.rstrip("/")):
                    # mocks.yaml body values are strings, not pre-serialized bytes.
                    body = rule["body"].encode("utf-8")
                    break
                # path_suffix and path_contains are mutually exclusive per rule.
                continue
            sub = rule.get("path_contains")
            if sub is not None and sub in parsed.path:
                # Query string is ignored; only the path is checked.
                body = rule["body"].encode("utf-8")
                break
        if body is None:
            # Unmatched paths look like "service down" to callers, not empty JSON.
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class _ReuseHTTPServer(HTTPServer):
    # Lets the test step restart the mock without "Address already in use".
    allow_reuse_address = True


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: mock_http_json.py <port>", file=sys.stderr)
        raise SystemExit(2)
    port = int(sys.argv[1])
    bind = os.environ.get("TEKTON_HTTP_BIND", "127.0.0.1")
    routes = _routes_from_env()
    _Handler.routes = routes
    server = _ReuseHTTPServer((bind, port), _Handler)
    # Backgrounded by generated bash (&); runs until the step container exits.
    server.serve_forever()


if __name__ == "__main__":
    main()
