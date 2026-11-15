#!/usr/bin/env python3
"""The hackathon agent from Chapter 1, stuck in its Sunday loop.

It sends the same long prompt over and over and ignores every 429, which is
exactly what a buggy retry loop does. Each call uses about 690 tokens.

  python3 company/hackathon_agent.py --key "$HACKATHON_AGENT_KEY" --times 8
  python3 company/hackathon_agent.py --gateway http://localhost:4000 --key ... --times 8

It prints one status code per call on a single line. If the last refusal had
a JSON body, it prints that too.
"""

import argparse
import json
import os
import signal
import sys
import urllib.error
import urllib.request

PARAGRAPH = (
    "You are the weekend summary bot the hackathon team built on a Saturday. "
    "Read the full export of this week's support tickets below and write a short summary "
    "for the Monday stand-up: the top three themes, any ticket that mentions a refund, "
    "and anything that looks like an outage. Keep it under one hundred words. "
)
TICKETS = [
    "Ticket {n}: Customer asks why the monthly card fee appeared twice on the October statement "
    "and whether the duplicate will be reversed before the next billing date. "
    for n in range(1000, 1100)
]
PROMPT_LENGTH = 2550   # characters; the stand-in model counts this as 645 prompt tokens


def build_prompt():
    text = PARAGRAPH + "".join(TICKETS)
    return text[:PROMPT_LENGTH]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gateway", default=os.environ.get("GATEWAY", "http://localhost:3000"))
    ap.add_argument("--key", help="the agent's gateway key")
    ap.add_argument("--times", type=int, default=5)
    ap.add_argument("--model", default="classifier")
    ap.add_argument("--quiet-refusal", action="store_true", help="don't print the last refusal body")
    args = ap.parse_args()

    url = args.gateway.rstrip("/") + "/v1/chat/completions"
    body = json.dumps({"model": args.model,
                       "messages": [{"role": "user", "content": build_prompt()}]}).encode()
    codes, last_refusal = [], None
    for _ in range(args.times):
        req = urllib.request.Request(url, data=body, method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("User-Agent", "hackathon-agent/0.1")
        if args.key:
            req.add_header("Authorization", f"Bearer {args.key}")
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                resp.read()
                codes.append(str(resp.status))
        except urllib.error.HTTPError as e:
            codes.append(str(e.code))
            last_refusal = e.read().decode(errors="replace").strip()
        except urllib.error.URLError as e:
            print(f"can't reach {url}: {e.reason}", file=sys.stderr)
            return 1
        # A real retry loop would sleep here. This one doesn't, which is the bug.
    print(" ".join(codes))
    if last_refusal and not args.quiet_refusal:
        try:
            json.loads(last_refusal)
            print(f"last refusal: {last_refusal}")
        except json.JSONDecodeError:
            pass
    return 0


if __name__ == "__main__":
    if hasattr(signal, "SIGPIPE"):
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)  # quiet when piped into head
    sys.exit(main())
