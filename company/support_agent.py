#!/usr/bin/env python3
"""The company's support agent: a small agent loop (Figure P.1).

It asks the model what to do, runs the tool the model picks, feeds the result
back, and goes around again until the model answers in words.

  # Chapter 1: no gateway. Straight to the model and to each MCP server.
  python3 company/support_agent.py --direct "Customer C123 wrote in. Please read email E-881 and help them."

  # Through the gateway (model and tools on one port, 3000 by default)
  python3 company/support_agent.py --key "$SUPPORT_AGENT_KEY" --user C123 "..."

Through the gateway it starts a trace and sends a W3C traceparent header on
every call, so the gateway's spans join into one trace (Chapter 11).
"""

import argparse
import json
import os
import secrets
import signal
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
from mcp_client import McpError, McpSession, result_text  # noqa: E402

SYSTEM_PROMPT = ("You are the support agent for a card company. Help the customer. "
                 "Use the tools when you need them.")

DIRECT_MODEL_URL = "http://localhost:8090/v1/chat/completions"
DIRECT_MODEL = "gpt-5.6"
DIRECT_SERVERS = {"docs": "http://localhost:8083/mcp", "accounts": "http://localhost:8081/mcp"}


def say(who, text):
    lines = str(text).splitlines() or [""]
    print(f"{who}: {lines[0]}")
    pad = " " * (len(who) + 2)
    for line in lines[1:]:
        print(pad + line)
    sys.stdout.flush()


class Tracer:
    def __init__(self):
        self.trace_id = secrets.token_hex(16)

    def header(self):
        return {"traceparent": f"00-{self.trace_id}-{secrets.token_hex(8)}-01"}


class ToolBox:
    """Holds MCP sessions and knows which session owns each tool."""

    def __init__(self, servers, headers, tracer):
        self.tracer = tracer
        self.sessions = {}
        self.owner = {}
        self.tools = []
        for label, url in servers.items():
            s = McpSession(url, headers)
            s.initialize(self._h())
            for t in s.list_tools(self._h()):
                self.owner[t["name"]] = s
                self.tools.append(t)
            self.sessions[label] = s

    def _h(self):
        return self.tracer.header() if self.tracer else {}

    def call(self, name, args):
        # A model may ask for a tool it was never shown; send it to the
        # gateway session anyway and let the gateway decide.
        session = self.owner.get(name) or next(iter(self.sessions.values()))
        result = session.call_tool(name, args, self._h())
        return result_text(result)

    def openai_tools(self):
        return [{"type": "function", "function": {
            "name": t["name"], "description": t.get("description", ""),
            "parameters": t.get("inputSchema", {"type": "object"})}} for t in self.tools]


def chat(url, model, messages, tools, headers):
    body = {"model": model, "messages": messages}
    if tools:
        body["tools"] = tools
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    for k, v in headers.items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return 200, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace").strip()
    except urllib.error.URLError as e:
        return 0, f"can't reach {url}: {e.reason}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("prompt", help="what the customer needs")
    ap.add_argument("--direct", action="store_true",
                    help="skip the gateway: call the model and each MCP server directly (Chapter 1)")
    ap.add_argument("--gateway", default=os.environ.get("GATEWAY", "http://localhost:3000"),
                    help="gateway base URL (default http://localhost:3000)")
    ap.add_argument("--key", help="the agent's gateway key, sent as Authorization: Bearer")
    ap.add_argument("--user", help="the customer this agent is acting for, sent as x-end-user")
    ap.add_argument("--model", default="support-writer", help="model alias to ask for (default support-writer)")
    ap.add_argument("--max-steps", type=int, default=6)
    args = ap.parse_args()

    headers = {"User-Agent": "support-agent/1.0"}
    if args.key:
        headers["Authorization"] = f"Bearer {args.key}"
    if args.user:
        headers["x-end-user"] = args.user

    if args.direct:
        tracer = None
        model_url, model = DIRECT_MODEL_URL, DIRECT_MODEL
        servers = DIRECT_SERVERS
    else:
        tracer = Tracer()
        say("agent", f"trace {tracer.trace_id}")
        base = args.gateway.rstrip("/")
        model_url, model = base + "/v1/chat/completions", args.model
        servers = {"gateway": base + "/mcp"}

    try:
        box = ToolBox(servers, headers, tracer)
    except McpError as e:
        say("agent", f"couldn't list tools: {e}")
        say("agent", "stopping.")
        return 1

    names = sorted(t["name"] for t in box.tools)
    say("agent", f"I can see {len(names)} tools: {', '.join(names)}")

    messages = [{"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": args.prompt}]
    for _ in range(args.max_steps):
        h = dict(headers, **(tracer.header() if tracer else {}))
        status, reply = chat(model_url, model, messages, box.openai_tools(), h)
        if status != 200:
            say("agent", f"the model call failed with {status}: {reply}")
            say("agent", "stopping.")
            return 1
        msg = reply["choices"][0]["message"]
        calls = msg.get("tool_calls") or []
        if not calls:
            say("model", msg.get("content", ""))
            return 0
        messages.append({"role": "assistant", "content": msg.get("content"), "tool_calls": calls})
        for tc in calls:
            name = tc["function"]["name"]
            arg_text = tc["function"].get("arguments") or "{}"
            say("model", f"call {name} {arg_text}")
            try:
                out = box.call(name, json.loads(arg_text))
            except McpError as e:
                out = f"error: {e}"
            say("tool", out)
            messages.append({"role": "tool", "tool_call_id": tc.get("id", ""), "content": out})
    say("agent", "too many steps; stopping.")
    return 1


if __name__ == "__main__":
    if hasattr(signal, "SIGPIPE"):
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)  # quiet when piped into head
    sys.exit(main())
