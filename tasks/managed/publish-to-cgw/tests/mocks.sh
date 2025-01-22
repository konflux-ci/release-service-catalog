#!/usr/bin/env bash

MOCK_SERVER_SCRIPT="/tmp/mock_server.py"

cat << 'EOF' > "$MOCK_SERVER_SCRIPT"
import http.server
import logging
import socketserver
import json


class MockHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    all_files = [
        {
            "type": "FILE",
            "hidden": False,
            "invisible": False,
            "description": "Red Hat OpenShift Local Sandbox Test",
            "shortURL": "/pub/cgw/product_code_1/1.2/skip",
            "productVersionId": 4156076,
            "downloadURL": "/content/origin/files/sha256/78/786a963eabcce0ee12fa1d36030db869a20e87b5f37477d929fb49b54a555593/skip",
            "label": "skip",
        },
        {
            "type": "FILE",
            "hidden": False,
            "invisible": False,
            "description": "Red Hat OpenShift Local Sandbox Test",
            "shortURL": "/pub/cgw/product_code_1/1.2/skip-darwin-amd64.gz",
            "productVersionId": 4156076,
            "downloadURL": "/content/origin/files/sha256/dd/ddaa38ae71199c268580b50adaefab359db7b7bae6ba8318570af33e550170d2/skip-darwin-amd64.gz",
            "label": "skip-darwin-amd64.gz",
        },
        {
            "type": "FILE",
            "hidden": False,
            "invisible": False,
            "description": "Red Hat OpenShift Local Sandbox Test",
            "shortURL": "/pub/cgw/product_code_1/1.2/skip-darwin-arm64.gz",
            "productVersionId": 4156076,
            "downloadURL": "/content/origin/files/sha256/0a/0a2f78e827c2d24c96f3e964b196e96528404329076c8635d4542bbfd9674a8a/skip-darwin-arm64.gz",
            "label": "skip-darwin-arm64.gz",
        },
        {
            "type": "FILE",
            "hidden": False,
            "invisible": False,
            "description": "Red Hat OpenShift Local Sandbox Test",
            "shortURL": "/pub/cgw/product_code_1/1.2/skip-linux-amd64.gz",
            "productVersionId": 4156076,
            "downloadURL": "/content/origin/files/sha256/e9/e9b0965f5e76e6b9f784c96c87afc44f2d61434447bceacc669e776c8a8bad61/skip-linux-amd64.gz",
            "label": "skip-linux-amd64.gz",
        },
        {
            "type": "FILE",
            "hidden": False,
            "invisible": False,
            "description": "Red Hat OpenShift Local Sandbox Test",
            "shortURL": "/pub/cgw/product_code_1/1.2/skip-linux-arm64.gz",
            "productVersionId": 4156076,
            "downloadURL": "/content/origin/files/sha256/3c/3ceafc6b478a52c63c48ee5dfa08737b149c0a3b01035870b3be48098c9b4cf6/skip-linux-arm64.gz",
            "label": "skip-linux-arm64.gz",
        },
    ]

    logging.basicConfig(level=logging.INFO, format="Mock Call: %(message)s")

    def log_message(self, format, *args):
        logging.info(format % args)

    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode("utf-8"))

    def do_GET(self):
        """
        GET requests:
        /products
        /products/<product_id>/versions
        /products/<product_id>/versions/<version_id>/files
        Else return 404
        """
        if self.path == "/products":
            response = [
                {
                    "id": 4010399,
                    "name": "product_name_1",
                    "productCode": "product_code_1",
                },
                {
                    "id": 5010399,
                    "name": "product_name_2",
                    "productCode": "product_code_2",
                },
            ]
            self._send_json(response)

        elif self.path == "/products/4010399/versions":
            response = [
                {
                    "id": 4156075,
                    "productId": 4010399,
                    "versionName": "1.1",
                },
                {
                    "id": 4156076,
                    "productId": 5010399,
                    "versionName": "1.2",
                },
            ]
            self._send_json(response)

        elif self.path.startswith("/products/") and self.path.endswith("/files"):
            self._send_json(self.all_files)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        """
        POST requests:
        /products/<product_id>/versions/<version_id>/files
        Create a new file and return the new file ID
        if a short url or download url is present it returns an error
        """
        if "/versions/" in self.path and self.path.endswith("/files"):
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            file_metadata = json.loads(body.decode("utf-8"))

            for existing in self.all_files:
                if any(
                    file_metadata.get(key) == existing[key]
                    for key in ["shortURL", "downloadURL"]
                ):
                    self.send_response(409)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(
                        json.dumps({"File already exists!"}).encode("utf-8")
                    )
                    return

            file_id = len(self.all_files) + 100
            file_metadata["id"] = file_id
            self.all_files.append(file_metadata)
            self._send_json(file_id, status=201)
        else:
            self.send_response(404)
            self.end_headers()

    def do_DELETE(self):
        """
        DELETE requests:
        /products/<product_id>/versions/<version_id>/files/<file_id>
        Delete a file by id.
        """
        if "/versions/" in self.path and "/files/" in self.path:
            self.send_response(200)
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()


with socketserver.TCPServer(("0.0.0.0", 8080), MockHTTPRequestHandler) as httpd:
    httpd.serve_forever()
EOF

python3 "$MOCK_SERVER_SCRIPT" &
MOCK_SERVER_PID=$!
