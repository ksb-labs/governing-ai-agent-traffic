#!/usr/bin/env bash
# Start the example company's systems on your laptop.
#
#   company/start.sh                    # all four: accounts docs ledger llm
#   company/start.sh accounts docs      # just the ones you name
#   company/start.sh --reckless         # stand-in model asks for refunds it wasn't offered
#
# Logs and pid files go in company/.run/. Stop everything with company/stop.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$HERE/.run"
mkdir -p "$RUN"
PY="${PYTHON:-python3}"

RECKLESS=""
SERVICES=()
for arg in "$@"; do
  case "$arg" in
    --reckless) RECKLESS="--reckless" ;;
    accounts|docs|ledger|llm) SERVICES+=("$arg") ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown service: $arg (choose from accounts docs ledger llm)" >&2; exit 2 ;;
  esac
done
[ ${#SERVICES[@]} -eq 0 ] && SERVICES=(accounts docs ledger llm)

port_of() {
  case "$1" in accounts) echo 8081 ;; ledger) echo 8082 ;; docs) echo 8083 ;; llm) echo 8090 ;; esac
}
cmd_of() {
  case "$1" in
    accounts) echo "$PY $HERE/mcp_server.py --server accounts --port 8081" ;;
    docs)     echo "$PY $HERE/mcp_server.py --server docs --port 8083" ;;
    ledger)   echo "$PY $HERE/ledger.py --port 8082" ;;
    llm)      echo "$PY $HERE/llm.py --port 8090 $RECKLESS" ;;
  esac
}
is_up() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

for svc in "${SERVICES[@]}"; do
  port=$(port_of "$svc")
  pidfile="$RUN/$svc.pid"
  if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    if [ "$svc" = llm ] && [ -n "$RECKLESS" ] && ! grep -q reckless "$RUN/llm.cmd" 2>/dev/null; then
      kill "$(cat "$pidfile")"; sleep 0.5
    else
      echo "$svc already running on :$port"; continue
    fi
  fi
  if is_up "$port"; then
    echo "port $port is already in use; is something else running there?" >&2; exit 1
  fi
  cmd=$(cmd_of "$svc")
  echo "$cmd" > "$RUN/$svc.cmd"
  nohup $cmd >> "$RUN/$svc.log" 2>&1 &
  echo $! > "$pidfile"
  for _ in $(seq 1 50); do is_up "$port" && break; sleep 0.1; done
  if is_up "$port"; then
    extra=""; [ "$svc" = llm ] && [ -n "$RECKLESS" ] && extra=" (reckless mode)"
    echo "started $svc on :$port$extra  (log: company/.run/$svc.log)"
  else
    echo "$svc didn't start; see company/.run/$svc.log" >&2; exit 1
  fi
done
