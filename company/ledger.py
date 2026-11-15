#!/usr/bin/env python3
"""The company's ledger REST API (port 8082). It has never heard of MCP.

  GET    /entries?account=C123   list one account's entries
  DELETE /entries/{id}           delete an entry

The same paths also answer under /api, so the Chapter 3 route can send
/api/entries straight through. Entries live in memory and reset on restart.
"""

import argparse
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

LOCK = threading.Lock()
ENTRIES = [
    {"id": "L-1", "account": "C123", "date": "2026-10-03", "description": "Card fee", "amount": "12.00"},
    {"id": "L-2", "account": "C123", "date": "2026-10-03", "description": "Card fee", "amount": "12.00"},
    {"id": "L-3", "account": "C456", "date": "2026-10-05", "description": "Card fee", "amount": "12.00"},
    {"id": "L-4", "account": "C456", "date": "2026-10-05", "description": "Card fee", "amount": "12.00"},
]


def log(text):
    print(f"{time.strftime('%H:%M:%S')} [ledger] {text}", flush=True)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, obj=None):
        body = json.dumps(obj).encode() if obj is not None else b""
        self.send_response(code)
        if body:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)
        log(f"{self.command} {self.path} -> {code}")

    def _path(self):
        parts = urlsplit(self.path)
        path = parts.path
        if path.startswith("/api/"):
            path = path[4:]
        return path.rstrip("/") or "/", parse_qs(parts.query)

    def do_GET(self):
        path, query = self._path()
        if path == "/healthz":
            return self._send(200, {"status": "ok"})
        if path == "/entries":
            account = (query.get("account") or [""])[0]
            if not account:
                return self._send(400, {"error": "account is required"})
            with LOCK:
                rows = [e for e in ENTRIES if e["account"] == account]
            return self._send(200, {"account": account, "entries": rows})
        self._send(404, {"error": "not found"})

    def do_DELETE(self):
        path, _ = self._path()
        if path.startswith("/entries/"):
            entry_id = path.split("/", 2)[2]
            with LOCK:
                for i, e in enumerate(ENTRIES):
                    if e["id"] == entry_id:
                        del ENTRIES[i]
                        return self._send(204)
            return self._send(404, {"error": f"no entry {entry_id}"})
        self._send(404, {"error": "not found"})


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=8082)
    ap.add_argument("--host", default="127.0.0.1")
    args = ap.parse_args()
    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    log(f"ledger API on http://{args.host}:{args.port}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
