#!/usr/bin/env bash
# Stop everything company/start.sh started.
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$HERE/.run"
shopt -s nullglob
stopped=0
for pidfile in "$RUN"/*.pid; do
  svc=$(basename "$pidfile" .pid)
  pid=$(cat "$pidfile")
  if kill "$pid" 2>/dev/null; then echo "stopped $svc"; stopped=1; fi
  rm -f "$pidfile"
done
[ $stopped -eq 0 ] && echo "nothing was running"
exit 0
