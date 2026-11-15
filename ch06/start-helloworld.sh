#!/usr/bin/env bash
# Listing 6.1 in one script: fetch the A2A project's Hello World agent, set up
# its virtual environment the first time, and run it on port 9999.
# Everything goes in .cache/ at the repo root. Needs Git and Python 3.10+.
#
#   ch06/start-helloworld.sh            # runs in the foreground
#   ch06/start-helloworld.sh --background
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$REPO/.cache"
DIR="$CACHE/a2a-samples/samples/python/agents/helloworld"
mkdir -p "$CACHE"
if [ ! -d "$CACHE/a2a-samples" ]; then
  git clone --depth 1 https://github.com/a2aproject/a2a-samples "$CACHE/a2a-samples"
fi
cd "$DIR"
if [ ! -x .venv/bin/python ]; then
  python3 -m venv .venv
  .venv/bin/pip install -q -r requirements.txt
fi
if [ "${1:-}" = "--background" ]; then
  nohup .venv/bin/python __main__.py > "$CACHE/helloworld.log" 2>&1 &
  echo $! > "$CACHE/helloworld.pid"
  for _ in $(seq 1 100); do (exec 3<>/dev/tcp/127.0.0.1/9999) 2>/dev/null && break; sleep 0.1; done
  echo "Hello World agent on :9999 (log: .cache/helloworld.log, pid in .cache/helloworld.pid)"
else
  exec .venv/bin/python __main__.py
fi
