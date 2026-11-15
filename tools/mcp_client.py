#!/usr/bin/env python3
"""A tiny MCP client for the terminal, like the Inspector without the browser.

It sends initialize, keeps the Mcp-Session-Id the gateway hands back, and
sends it on every later request.

  python3 tools/mcp_client.py list
  python3 tools/mcp_client.py call echo message=hello
  python3 tools/mcp_client.py call ledger_list_entries query.account=C123
  python3 tools/mcp_client.py --token "$SUPPORT_AGENT_KEY" list
  python3 tools/mcp_client.py --header "x-end-user: C456" call ...

Arguments are name=value pairs. Values that look like JSON (numbers, true,
false, lists) are sent as JSON; everything else is a string. Dotted names
build nested objects, so query.account=C123 becomes {"query": {"account": "C123"}}.
"""

import argparse
import itertools
import json
import os
import signal
import sys
import urllib.error
import urllib.request

DEFAULT_URL = os.environ.get("MCP_URL", "http://localhost:3000/mcp")
PROTOCOL_VERSION = "2025-06-18"


class McpError(Exception):
    pass


class McpSession:
    """One MCP session over Streamable HTTP."""

    def __init__(self, url=DEFAULT_URL, headers=None, timeout=30):
        self.url = url
        self.headers = dict(headers or {})
        self.timeout = timeout
        self.session_id = None
        self.ids = itertools.count(1)

    def _post(self, payload, extra_headers=None):
        data = json.dumps(payload).encode()
        req = urllib.request.Request(self.url, data=data, method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("Accept", "application/json, text/event-stream")
        req.add_header("MCP-Protocol-Version", PROTOCOL_VERSION)
        for k, v in self.headers.items():
            req.add_header(k, v)
        for k, v in (extra_headers or {}).items():
            req.add_header(k, v)
        if self.session_id:
            req.add_header("Mcp-Session-Id", self.session_id)
        try:
            resp = urllib.request.urlopen(req, timeout=self.timeout)
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace").strip()
            raise McpError(f"HTTP {e.code} {e.reason}: {body}") from None
        except urllib.error.URLError as e:
            raise McpError(f"can't reach {self.url}: {e.reason}") from None
        sid = resp.headers.get("Mcp-Session-Id")
        if sid:
            self.session_id = sid
        body = resp.read().decode(errors="replace")
        if resp.status == 202 or not body.strip():
            return None
        ctype = resp.headers.get("Content-Type", "")
        if "text/event-stream" in ctype:
            return self._from_sse(body, payload.get("id"))
        return json.loads(body)

    @staticmethod
    def _from_sse(body, want_id):
        last = None
        for event in body.replace("\r\n", "\n").split("\n\n"):
            data = "\n".join(line[5:].lstrip() for line in event.split("\n") if line.startswith("data:"))
            if not data:
                continue
            try:
                msg = json.loads(data)
            except json.JSONDecodeError:
                continue
            if isinstance(msg, dict) and ("result" in msg or "error" in msg):
                last = msg
                if msg.get("id") == want_id:
                    return msg
        return last

    def request(self, method, params=None, extra_headers=None):
        payload = {"jsonrpc": "2.0", "id": next(self.ids), "method": method, "params": params or {}}
        msg = self._post(payload, extra_headers)
        if msg is None:
            raise McpError(f"no response to {method}")
        if "error" in msg:
            raise McpError(json.dumps({"error": msg["error"]}))
        return msg.get("result", {})

    def notify(self, method, params=None, extra_headers=None):
        self._post({"jsonrpc": "2.0", "method": method, "params": params or {}}, extra_headers)

    def initialize(self, extra_headers=None):
        result = self.request("initialize", {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {},
            "clientInfo": {"name": "agentgateway-in-action", "version": "1.0"},
        }, extra_headers)
        self.notify("notifications/initialized", extra_headers=extra_headers)
        return result

    def list_tools(self, extra_headers=None):
        tools, cursor = [], None
        while True:
            result = self.request("tools/list", {"cursor": cursor} if cursor else {}, extra_headers)
            tools.extend(result.get("tools", []))
            cursor = result.get("nextCursor")
            if not cursor:
                return tools

    def call_tool(self, name, arguments, extra_headers=None):
        return self.request("tools/call", {"name": name, "arguments": arguments}, extra_headers)


def result_text(result):
    parts = []
    for c in result.get("content", []):
        if c.get("type") == "text":
            parts.append(c.get("text", ""))
        else:
            parts.append(json.dumps(c))
    if not parts and "structuredContent" in result:
        parts.append(json.dumps(result["structuredContent"]))
    return "\n".join(parts)


def parse_value(v):
    try:
        return json.loads(v)
    except json.JSONDecodeError:
        return v


def parse_args_list(pairs):
    out = {}
    for pair in pairs:
        if "=" not in pair:
            raise SystemExit(f"argument {pair!r} should look like name=value")
        name, value = pair.split("=", 1)
        target = out
        keys = name.split(".")
        for k in keys[:-1]:
            target = target.setdefault(k, {})
        target[keys[-1]] = parse_value(value)
    return out


def parse_headers(items):
    headers = {}
    for h in items or []:
        if ":" not in h:
            raise SystemExit(f"header {h!r} should look like 'name: value'")
        k, v = h.split(":", 1)
        headers[k.strip()] = v.strip()
    return headers


def short(text, width=48):
    text = " ".join((text or "").split())
    return text if len(text) <= width else text[:width - 4].rstrip() + " ..."


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default=DEFAULT_URL, help=f"MCP endpoint (default {DEFAULT_URL})")
    ap.add_argument("--token", help="sent as Authorization: Bearer <token>")
    ap.add_argument("--header", action="append", default=[], help="extra header, 'name: value'")
    ap.add_argument("--json", action="store_true", help="print raw JSON results")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list", help="list tools")
    c = sub.add_parser("call", help="call a tool")
    c.add_argument("tool")
    c.add_argument("args", nargs="*", help="name=value pairs")
    args = ap.parse_args()

    headers = parse_headers(args.header)
    if args.token:
        headers["Authorization"] = f"Bearer {args.token}"
    session = McpSession(args.url, headers)
    try:
        session.initialize()
        if args.cmd == "list":
            tools = session.list_tools()
            if args.json:
                print(json.dumps(tools, indent=2))
                return 0
            print(f"{len(tools)} tools")
            width = max([len(t["name"]) for t in tools] + [10]) + 3
            for t in tools:
                print(f"  {t['name']:<{width}}{short(t.get('description', ''))}")
        else:
            result = session.call_tool(args.tool, parse_args_list(args.args))
            if args.json:
                print(json.dumps(result, indent=2))
            else:
                print(result_text(result) or "(the tool returned no content)")
            if result.get("isError"):
                return 1
    except McpError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    if hasattr(signal, "SIGPIPE"):
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)  # quiet when piped into head
    sys.exit(main())
