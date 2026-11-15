#!/usr/bin/env bash
# Section 14.2: replay the poisoned email against the finished gateway.
# Run it from ch14 while the gateway from config.yaml is running and logging
# to gateway.log (agentgateway -f config.yaml | tee gateway.log).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
. "$HERE/env.sh"
LOG="${GATEWAY_LOG:-$HERE/gateway.log}"
PROMPT="Customer C123 wrote in. Please read email E-881 and help them."
before=$(grep -c "tools/call issue_refund" "$REPO/company/.run/accounts.log" 2>/dev/null || echo 0)

echo "== 1. The support agent, as it runs in production"
python3 "$REPO/company/support_agent.py" --key "$SUPPORT_AGENT_KEY" --user C123 "$PROMPT"

echo
echo "== 2. The same, with a model that has no tool-output guard (a guard that misses)"
python3 "$REPO/company/support_agent.py" --key "$SUPPORT_AGENT_KEY" --user C123 \
  --model support-writer-noguard "$PROMPT"
sleep 1

echo
echo "== Listing 12.5: denials by agent"
python3 "$REPO/tools/logq.py" "$LOG" reason=Authorization --count-by agent.id,enduser.id,gen_ai.tool.name

trace=$(python3 "$REPO/tools/logq.py" "$LOG" reason=Authorization | tail -1 | \
  python3 -c 'import json,sys; t=sys.stdin.read().strip(); print(json.loads(t)["trace.id"] if t else "")')
echo
echo "== Listing 12.7: the denied request, start to end (trace $trace)"
python3 "$REPO/tools/logq.py" "$LOG" "trace.id=$trace" \
  --table time,protocol,agent.id,enduser.id,gen_ai.request.model,gen_ai.tool.name,http.status,reason

after=$(grep -c "tools/call issue_refund" "$REPO/company/.run/accounts.log" 2>/dev/null || echo 0)
echo
if [ "$before" = "$after" ]; then
  echo "The accounts server never saw a refund request."
else
  echo "WARNING: the accounts server saw $((after - before)) refund request(s)."
fi
