#!/usr/bin/env python3
"""
Minimal mock HTTP server for Myrmidons test suite.

Reads response configuration from environment variables:
  MOCK_STATUS  — HTTP status code to return (default: 200)
  MOCK_BODY    — Response body JSON string (default: {})

Usage:
  MOCK_STATUS=200 MOCK_BODY='[...]' python3 mock_server.py <PORT>
"""
import os
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

STATUS = int(os.environ.get("MOCK_STATUS", "200"))
BODY = os.environ.get("MOCK_BODY", "{}")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress request logging

    def do_GET(self):
        self._respond()

    def do_POST(self):
        self._respond()

    def do_PATCH(self):
        self._respond()

    def do_DELETE(self):
        self._respond()

    def _respond(self):
        encoded = BODY.encode("utf-8")
        self.send_response(STATUS)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18080
    httpd = HTTPServer(("127.0.0.1", port), Handler)
    httpd.serve_forever()
