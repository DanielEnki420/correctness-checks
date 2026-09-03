#!/usr/bin/env python3
"""Stub monitoring endpoint for the test suite.

Accepts push requests and records them to a file instead of forwarding them to
a real Uptime Kuma instance.

This is not cosmetic. While developing these checks we copied one for testing
and left the REAL push token in it. The simulated failure went straight to the
production monitor and turned it red. Tests must not be able to touch
monitoring — that is now structural, not a habit.

Usage:  kuma-stub.py <port> <logfile>
Answers everything with {"ok":true}, like Kuma does.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

LOGFILE = sys.argv[2]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        entry = {
            "token": u.path.strip("/").split("/")[-1],
            "status": (q.get("status") or [""])[0],
            "msg": (q.get("msg") or [""])[0],
        }
        with open(LOGFILE, "a") as f:
            f.write(json.dumps(entry) + "\n")
        reply = b'{"ok":true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)

    def log_message(self, *a):
        pass            # stay quiet on stderr


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
