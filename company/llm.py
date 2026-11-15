#!/usr/bin/env python3
"""The stand-in model (port 8090). It is not a real model.

It speaks the OpenAI chat completions API and follows a few fixed rules, so
every lab gives the same result every time:

  1. Asked to read an email (E-123) and given a fetch_email tool, it calls it.
  2. If a tool result tells it to "call issue_refund ...", it obeys, just as
     the support agent's model did in Chapter 1. With --reckless it asks for
     the refund even when it wasn't shown that tool (Chapters 12 and 14).
  3. Anything else, it echoes back what you sent, so guardrails that edit a
     response are easy to see.

It reports token usage the way a real provider does, so agentgateway prices
each call from its real catalog, keyed on the model name it was sent.

  python3 company/llm.py [--port 8090] [--reckless]
"""

import argparse
import json
import math
import re
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ECHO_PREFIX = "Stand-in model. I echo what you send, so every lab run matches. You said: "
ECHO_MAX = 100          # longer messages are cut to this many characters in the echo
RECKLESS = False
LOCK = threading.Lock()

REFUND_RE = re.compile(
    r"call\s+(?:the\s+)?(?P<tool>[\w-]*issue_refund)\s+for\s+account\s+(?P<account>\w+)"
    r"(?:,?\s*amount\s+(?P<amount>[\d.]+))?(?:,?\s*reason\s+(?P<reason>[\w-]+))?",
    re.IGNORECASE)
EMAIL_RE = re.compile(r"\bE-\d+\b")


def tokens(text):
    """A rough tokenizer: about four characters per token, like English text."""
    return max(1, math.ceil(len(text) / 4)) if text else 0


def text_of(content):
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    if isinstance(content, list):  # OpenAI content parts
        return " ".join(p.get("text", "") for p in content if isinstance(p, dict))
    return str(content)


def prompt_tokens(messages, tools):
    count = 3
    for m in messages:
        count += 4 + tokens(text_of(m.get("content")))
        for tc in m.get("tool_calls") or []:
            fn = tc.get("function", {})
            count += tokens(fn.get("name", "") + fn.get("arguments", ""))
    for t in tools or []:
        count += tokens(json.dumps(t))
    return count


def tool_names(tools):
    names = []
    for t in tools or []:
        fn = t.get("function", t)
        if fn.get("name"):
            names.append(fn["name"])
    return names


def find_tool(names, suffix):
    for n in names:
        if n == suffix or n.endswith("_" + suffix):
            return n
    return None


def decide(messages, tools):
    """Return ("text", reply) or ("tool", name, args)."""
    names = tool_names(tools)
    last = messages[-1] if messages else {"role": "user", "content": ""}
    role = last.get("role")
    content = text_of(last.get("content"))

    if role == "tool":
        m = REFUND_RE.search(content)
        if m:
            args = {"account_id": m.group("account")}
            if m.group("amount"):
                amt = float(m.group("amount"))
                args["amount"] = int(amt) if amt.is_integer() else amt
            if m.group("reason"):
                args["reason"] = m.group("reason")
            tool = find_tool(names, "issue_refund")
            if not tool and RECKLESS:
                # Guess the name the way the other tools are written.
                prefix = ""
                for n in names:
                    if "_" in n and n.split("_", 1)[0] in ("docs", "accounts", "ledger"):
                        prefix = "accounts_"
                        break
                tool = prefix + "issue_refund"
            if tool:
                return ("tool", tool, args)
            return ("text", "The email asks for a refund, but I have no refund tool. "
                            "A person should review it.")
        if content.startswith("Refund R-"):
            return ("text", f"Done. {content}")
        if content.lower().startswith("error") or "unknown resource" in content or "denied" in content:
            return ("text", "The refund didn't go through. A person should review this request.")
        return ("text", "Here is what I found: " + content[:ECHO_MAX])

    if role == "user":
        email = EMAIL_RE.search(content)
        fetch = find_tool(names, "fetch_email")
        if email and fetch:
            return ("tool", fetch, {"email_id": email.group(0)})

    quote = content if len(content) <= ECHO_MAX else content[:ECHO_MAX - 3] + "..."
    return ("text", ECHO_PREFIX + quote)


def log(text):
    print(f"{time.strftime('%H:%M:%S')} [llm] {text}", flush=True)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, obj, ctype="application/json"):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0].rstrip("/")
        if path.endswith("/models"):
            models = ["gpt-5.6", "gpt-5.6-luna", "gpt-5.6-mini", "llama3"]
            return self._send(200, {"object": "list", "data": [
                {"id": m, "object": "model", "owned_by": "stand-in"} for m in models]})
        if path in ("", "/healthz"):
            return self._send(200, {"status": "ok"})
        self._send(404, {"error": {"message": "not found"}})

    def do_POST(self):
        path = self.path.split("?")[0].rstrip("/")
        if not path.endswith("/chat/completions"):
            return self._send(404, {"error": {"message": f"stand-in model has no {path}"}})
        length = int(self.headers.get("Content-Length") or 0)
        try:
            req = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            return self._send(400, {"error": {"message": "invalid JSON"}})

        model = req.get("model", "stand-in")
        messages = req.get("messages") or []
        tools = req.get("tools") or []
        key_seen = "yes" if self.headers.get("Authorization") else "no"
        p_tokens = prompt_tokens(messages, tools)

        decision = decide(messages, tools)
        if decision[0] == "tool":
            _, name, args = decision
            arg_text = json.dumps(args)
            c_tokens = tokens(name + arg_text) + 4
            message = {"role": "assistant", "content": None, "tool_calls": [{
                "id": "call_" + uuid.uuid4().hex[:12], "type": "function",
                "function": {"name": name, "arguments": arg_text}}]}
            finish = "tool_calls"
            summary = f"call {name} {arg_text}"
        else:
            reply = decision[1]
            c_tokens = tokens(reply)
            message = {"role": "assistant", "content": reply}
            finish = "stop"
            summary = reply[:60] + ("..." if len(reply) > 60 else "")

        last = text_of(messages[-1].get("content")) if messages else ""
        log(f"model={model} messages={len(messages)} tools={len(tools)} "
            f"provider key seen: {key_seen} | last: {last[:50]!r} | -> {summary} "
            f"({p_tokens} in / {c_tokens} out)")

        usage = {"prompt_tokens": p_tokens, "completion_tokens": c_tokens,
                 "total_tokens": p_tokens + c_tokens}
        cid = "chatcmpl-" + uuid.uuid4().hex[:16]
        created = int(time.time())

        if req.get("stream"):
            return self._stream(cid, created, model, message, finish, usage)

        self._send(200, {
            "id": cid, "object": "chat.completion", "created": created, "model": model,
            "choices": [{"index": 0, "message": message, "finish_reason": finish}],
            "usage": usage,
        })

    def _stream(self, cid, created, model, message, finish, usage):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()

        def chunk(delta, finish_reason=None, with_usage=False):
            obj = {"id": cid, "object": "chat.completion.chunk", "created": created, "model": model,
                   "choices": [{"index": 0, "delta": delta, "finish_reason": finish_reason}]}
            if with_usage:
                obj["usage"] = usage
            self.wfile.write(f"data: {json.dumps(obj)}\n\n".encode())
            self.wfile.flush()

        chunk({"role": "assistant"})
        if message.get("tool_calls"):
            chunk({"tool_calls": [dict(message["tool_calls"][0], index=0)]})
        else:
            words = message["content"].split(" ")
            for i, w in enumerate(words):
                chunk({"content": w + (" " if i < len(words) - 1 else "")})
        chunk({}, finish, with_usage=True)
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()
        self.close_connection = True


def main():
    global RECKLESS
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8090)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--reckless", action="store_true",
                    help="ask for issue_refund even when that tool wasn't offered")
    args = ap.parse_args()
    RECKLESS = args.reckless
    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    log(f"stand-in model on http://{args.host}:{args.port}/v1" + (" (reckless mode)" if RECKLESS else ""))
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
