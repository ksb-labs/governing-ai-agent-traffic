#!/usr/bin/env python3
"""A tiny A2A 1.0 client that behaves like a real calling agent.

It fetches the Agent Card first, then sends its message to whatever address
the card gives. That makes the gateway's card rewrite (section 6.3) easy to see.

  python3 tools/a2a_client.py send http://localhost:3000 hi
  python3 tools/a2a_client.py send http://localhost:3000/disputes "dispute the 12 dollar fee" \\
      --header "x-end-user: C123"
  python3 tools/a2a_client.py card http://localhost:3000
"""

import argparse
import json
import signal
import sys
import urllib.error
import urllib.request
import uuid

CARD_PATHS = ["/.well-known/agent-card.json", "/.well-known/agent.json"]


def http(method, url, headers, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    for k, v in headers.items():
        req.add_header(k, v)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace").strip()
    except urllib.error.URLError as e:
        raise SystemExit(f"error: can't reach {url}: {e.reason}")


def fetch_card(base, headers):
    base = base.rstrip("/")
    for path in CARD_PATHS:
        status, body = http("GET", base + path, headers)
        if status == 200:
            return json.loads(body)
    raise SystemExit(f"error: no agent card at {base} (HTTP {status}: {body})")


def card_url(card):
    for iface in card.get("supportedInterfaces") or []:
        if iface.get("protocolBinding", "JSONRPC").upper() == "JSONRPC" and iface.get("url"):
            return iface["url"], iface.get("protocolVersion", "1.0")
    if card.get("url"):  # A2A 0.3
        return card["url"], card.get("protocolVersion", "0.3")
    raise SystemExit("error: the card doesn't say where to send messages")


def texts(parts):
    return [p["text"] for p in parts or [] if isinstance(p, dict) and p.get("text")]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--header", action="append", default=[], help="extra header, 'name: value'")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("send", help="fetch the card, then send one message")
    s.add_argument("url")
    s.add_argument("text")
    s.add_argument("--header", action="append", default=[], dest="header2")
    c = sub.add_parser("card", help="print the agent card")
    c.add_argument("url")
    args = ap.parse_args()

    headers = {}
    for h in args.header + (getattr(args, "header2", None) or []):
        k, _, v = h.partition(":")
        headers[k.strip()] = v.strip()

    card = fetch_card(args.url, headers)
    if args.cmd == "card":
        print(json.dumps(card, indent=2))
        return 0

    url, version = card_url(card)
    print(f"card says: send messages to {url}")
    if version.startswith("0."):
        method = "message/send"
        message = {"kind": "message", "messageId": str(uuid.uuid4()), "role": "user",
                   "parts": [{"kind": "text", "text": args.text}]}
    else:
        method = "SendMessage"
        headers["A2A-Version"] = "1.0"
        message = {"messageId": str(uuid.uuid4()), "role": "ROLE_USER", "parts": [{"text": args.text}]}
    status, body = http("POST", url, headers, {"jsonrpc": "2.0", "id": str(uuid.uuid4()),
                                               "method": method, "params": {"message": message}})
    if status != 200:
        print(f"error: HTTP {status}: {body}")
        return 1
    reply = json.loads(body)
    if "error" in reply:
        print(f"error: {json.dumps(reply['error'])}")
        return 1
    result = reply.get("result", {})
    task = result.get("task") or (result if result.get("kind") == "task" else None)
    message = result.get("message") or (result if result.get("kind") == "message" else None)
    if task:
        print(f"task state: {task.get('status', {}).get('state')}")
        answer = [t for a in task.get("artifacts") or [] for t in texts(a.get("parts"))]
        if not answer:
            answer = texts((task.get("status") or {}).get("message", {}).get("parts"))
    else:
        answer = texts((message or {}).get("parts"))
    for t in answer:
        print(f"agent: {t}")
    return 0


if __name__ == "__main__":
    if hasattr(signal, "SIGPIPE"):
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)  # quiet when piped into head
    sys.exit(main())
