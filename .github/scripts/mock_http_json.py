#!/usr/bin/env python3
"""Minimal JSON HTTP/HTTPS mock for Tekton task tests (``http_json`` in mocks.yaml).

Started by bash emitted by ``render_python_task_mocks_from_yaml.py``. The renderer
copies this file into the task step script at merge time (the pod has no git
checkout).

Environment:
  TEKTON_ROUTES_B64: base64-encoded JSON list of route rules (see mocks.yaml).
  TEKTON_HTTP_BIND: listen address (default ``127.0.0.1``).
  TEKTON_MOCK_TLS: when set to ``1``, enable HTTPS with a self-signed certificate.
  TEKTON_MOCK_CA_CERT_PATH: path to write the generated CA cert (default
    ``/tmp/mock-ca.crt``).
  TEKTON_MOCK_HOSTNAME: additional SAN hostname for the certificate (optional).

Arguments:
  port: TCP port to bind (integer).
"""

from __future__ import annotations

import base64
import json
import os
import ssl
import subprocess
import sys
import tempfile
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse


def _routes_from_env() -> list[dict]:
    # Populated by render_python_task_mocks_from_yaml.py from mocks.yaml routes.
    raw = os.environ.get("TEKTON_ROUTES_B64", "")
    if not raw:
        msg = "TEKTON_ROUTES_B64 is required"
        raise SystemExit(msg)
    return json.loads(base64.standard_b64decode(raw))


def _match_route(routes: list[dict], method: str, path: str) -> bytes | None:
    """Return the response body for the first matching route, or None."""
    for rule in routes:
        rule_method = rule.get("method", "").upper()
        if rule_method and rule_method != method:
            continue
        suf = rule.get("path_suffix")
        if suf is not None:
            suf_stripped = suf.rstrip("/")
            if path.endswith(suf) or (suf_stripped and path.endswith(suf_stripped)):
                return rule["body"].encode("utf-8")
            continue
        sub = rule.get("path_contains")
        if sub is not None and sub in path:
            return rule["body"].encode("utf-8")
    return None


class _Handler(BaseHTTPRequestHandler):
    # Set on the class in main(): BaseHTTPRequestHandler builds a new instance per
    # request, so instance attributes would not be shared across connections.
    routes: list[dict]

    def log_message(self, *_args: object) -> None:
        return

    def _handle_request(self, method: str) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        body = _match_route(self.routes, method, path)
        if body is None:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        self._handle_request("GET")

    def do_POST(self) -> None:
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length:
            self.rfile.read(content_length)
        self._handle_request("POST")

    def do_PATCH(self) -> None:
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length:
            self.rfile.read(content_length)
        self._handle_request("PATCH")


class _ReuseHTTPServer(HTTPServer):
    allow_reuse_address = True


def _generate_self_signed_cert(
    bind: str, hostname: str | None
) -> tuple[str, str, str]:
    """Generate a self-signed cert via openssl. Return (cert_path, key_path, ca_path)."""
    cert_dir = tempfile.mkdtemp(prefix="mock-tls-")
    cert_path = os.path.join(cert_dir, "server.crt")
    key_path = os.path.join(cert_dir, "server.key")

    san_entries = [f"IP:{bind}"]
    if hostname:
        if hostname.replace(".", "").replace(":", "").isdigit() or ":" in hostname:
            san_entries.append(f"IP:{hostname}")
        else:
            san_entries.append(f"DNS:{hostname}")
    san_value = ",".join(san_entries)

    subprocess.run(
        [
            "openssl", "req", "-x509", "-newkey", "ec",
            "-pkeyopt", "ec_paramgen_curve:prime256v1",
            "-keyout", key_path, "-out", cert_path,
            "-days", "1", "-nodes",
            "-subj", "/CN=mock-server",
            "-addext", f"subjectAltName={san_value}",
        ],
        check=True,
        capture_output=True,
    )

    ca_cert_path = os.environ.get("TEKTON_MOCK_CA_CERT_PATH", "/tmp/mock-ca.crt")
    with open(cert_path, "r") as src, open(ca_cert_path, "w") as dst:
        dst.write(src.read())

    return cert_path, key_path, ca_cert_path


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: mock_http_json.py <port>", file=sys.stderr)
        raise SystemExit(2)
    port = int(sys.argv[1])
    bind = os.environ.get("TEKTON_HTTP_BIND", "127.0.0.1")
    routes = _routes_from_env()
    _Handler.routes = routes
    server = _ReuseHTTPServer((bind, port), _Handler)

    if os.environ.get("TEKTON_MOCK_TLS") == "1":
        hostname = os.environ.get("TEKTON_MOCK_HOSTNAME")
        cert_path, key_path, _ca = _generate_self_signed_cert(bind, hostname)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cert_path, key_path)
        server.socket = ctx.wrap_socket(server.socket, server_side=True)

    server.serve_forever()


if __name__ == "__main__":
    main()
