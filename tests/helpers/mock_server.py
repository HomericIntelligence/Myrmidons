#!/usr/bin/env python3
"""
Minimal mock HTTP server for Myrmidons test suite.

Reads response configuration from:
  1. Optional routes config file (second CLI arg)
  2. Environment variables (fallback):
     MOCK_STATUS  — HTTP status code to return (default: 200)
     MOCK_BODY    — Response body JSON string (default: {})

Usage:
  MOCK_STATUS=200 MOCK_BODY='[...]' python3 mock_server.py <PORT>
  python3 mock_server.py <PORT> <routes_config.json>
"""
import os
import sys
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

STATUS = int(os.environ.get("MOCK_STATUS", "200"))
BODY = os.environ.get("MOCK_BODY", "{}")
ROUTES_CONFIG = None

# Load routes config if provided
if len(sys.argv) > 2:
    config_path = sys.argv[2]
    try:
        with open(config_path, "r") as f:
            ROUTES_CONFIG = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"Error loading routes config: {e}", file=sys.stderr)
        sys.exit(1)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress request logging

    def do_GET(self):
        self._respond("GET")

    def do_POST(self):
        self._respond("POST")

    def do_PATCH(self):
        self._respond("PATCH")

    def do_DELETE(self):
        self._respond("DELETE")

    def _respond(self, method):
        status, body = self._get_response(method)
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _get_response(self, method):
        """Get response status and body for the given method and path.

        If routes config is available, match by method+path.
        Otherwise fall back to env vars.
        """
        if ROUTES_CONFIG is None:
            return STATUS, BODY

        # Try to find a matching route
        for route in ROUTES_CONFIG.get("routes", []):
            if route.get("method") == method and route.get("path") == self.path:
                return route.get("status", 200), route.get("body", "{}")

        # Fall back to default_status/default_body from config, or env vars
        default_status = ROUTES_CONFIG.get("default_status", STATUS)
        default_body = ROUTES_CONFIG.get("default_body", BODY)
        return default_status, default_body


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18080
    httpd = HTTPServer(("127.0.0.1", port), Handler)
    httpd.serve_forever()
