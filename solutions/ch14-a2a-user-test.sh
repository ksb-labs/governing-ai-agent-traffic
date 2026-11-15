#!/usr/bin/env bash
# Chapter 14, Your turn: a tenth test for governance-check.sh. The original
# user's identity is recorded on agent-to-agent calls.
#
# It needs the disputes agent (python3 company/disputes_agent.py) and the
# Chapter 14 gateway, whose disputes route refuses messages with no x-end-user.
# Paste the function and the check line into ch14/governance-check.sh, or run
# this on its own from the repo root or ch14.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
GW="${GATEWAY:-http://localhost:3000}"
LOG="${GATEWAY_LOG:-$REPO/ch14/gateway.log}"

a2a_records_user() {
  local out
  # A message with no user must be refused...
  out=$(python3 "$REPO/tools/a2a_client.py" send "$GW/disputes" "dispute the 12 dollar fee")
  grep -q "HTTP 403" <<< "$out" || return 1
  # ...and one that names a user must reach the agent and be recorded with that user.
  out=$(python3 "$REPO/tools/a2a_client.py" send "$GW/disputes" "dispute the 12 dollar fee" \
    --header "x-end-user: C321")
  grep -q "for customer C321" <<< "$out" || return 1
  sleep 1
  [ -n "$(python3 "$REPO/tools/logq.py" "$LOG" protocol=a2a enduser.id=C321 http.status=200)" ]
}

if a2a_records_user >/dev/null 2>&1; then
  echo "  [x] The original user's identity is recorded on agent-to-agent calls"
else
  echo "  [ ] The original user's identity is recorded on agent-to-agent calls"
  exit 1
fi
