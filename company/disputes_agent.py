#!/usr/bin/env python3
"""The disputes team's agent (port 9998). It speaks A2A 1.0.

It opens a case for each message and says whose behalf it's acting on, from
the x-end-user header. With no user, it falls back to its own permissions,
which cover every customer: the confused deputy from section 6.4.

  python3 company/disputes_agent.py [--port 9998]
"""

import argparse
import json
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOCK = threading.Lock()
NEXT_CASE = [4101]


def card(port):
    return {
        "name": "Disputes Agent",
        "description": "Opens card dispute cases for the disputes team",
        "supportedInterfaces": [{"url": f"http://127.0.0.1:{port}", "protocolBinding": "JSONRPC",
                                 "protocolVersion": "1.0"}],
        "version": "1.0.0",
        "capabilities": {"streaming": False},
        "defaultInputModes": ["text/plain"],
        "defaultOutputModes": ["text/plain"],
        "skills": [{"id": "open_case", "name": "Open dispute case",
                    "description": "Opens a dispute case for a card charge",
                    "tags": ["disputes"], "examples": ["dispute the 12 dollar fee"]}],
    }


def log(text):
    print(f"{time.strftime('%H:%M:%S')} [disputes] {text}", flush=True)


def make_handler(port):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *a):
            pass

        def _send(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path.rstrip("/").endswith(("/.well-known/agent-card.json", "/.well-known/agent.json")):
                log("GET agent card")
                return self._send(200, card(port))
            self._send(404, {"error": "not found"})

        def do_POST(self):
            length = int(self.headers.get("Content-Length") or 0)
            try:
                req = json.loads(self.rfile.read(length) or b"{}")
            except json.JSONDecodeError:
                return self._send(400, {"jsonrpc": "2.0", "id": None,
                                        "error": {"code": -32700, "message": "Parse error"}})
            rid = req.get("id")
            method = req.get("method")
            if method not in ("SendMessage", "message/send"):
                return self._send(200, {"jsonrpc": "2.0", "id": rid,
                                        "error": {"code": -32601, "message": f"Method not found: {method}"}})
            msg = (req.get("params") or {}).get("message") or {}
            text = " ".join(p.get("text", "") for p in msg.get("parts", []) if isinstance(p, dict))
            user = self.headers.get("x-end-user")
            with LOCK:
                case = f"DSP-{NEXT_CASE[0]}"
                NEXT_CASE[0] += 1
            if user:
                answer = f"Opened case {case} for customer {user}."
            else:
                answer = (f"Opened case {case}. No end user was passed, so I acted with my own "
                          f"permissions, which cover every customer.")
            log(f"{method} user={user or '?'} text={text!r} -> {case}")
            context = msg.get("contextId") or str(uuid.uuid4())
            reply = {"messageId": str(uuid.uuid4()), "contextId": context, "role": "ROLE_AGENT",
                     "parts": [{"text": answer}]}
            self._send(200, {"jsonrpc": "2.0", "id": rid, "result": {"message": reply}})

    return Handler


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=9998)
    ap.add_argument("--host", default="127.0.0.1")
    args = ap.parse_args()
    httpd = ThreadingHTTPServer((args.host, args.port), make_handler(args.port))
    log(f"disputes agent (A2A 1.0) on http://{args.host}:{args.port}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
