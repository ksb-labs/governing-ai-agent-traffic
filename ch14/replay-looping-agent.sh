#!/usr/bin/env bash
# Section 14.3: replay the looping hackathon agent against the finished gateway.
# Run it from ch14 while the gateway is running and logging to gateway.log.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
. "$HERE/env.sh"
LOG="${GATEWAY_LOG:-$HERE/gateway.log}"
AGENT="$REPO/company/hackathon_agent.py"

first=$(python3 "$AGENT" --key "$HACKATHON_AGENT_KEY" --times 6 --quiet-refusal)
support=$(python3 "$AGENT" --key "$SUPPORT_AGENT_KEY" --times 3 --quiet-refusal)
second=$(python3 "$AGENT" --key "$HACKATHON_AGENT_KEY" --times 6 --quiet-refusal)
echo "hackathon agent: $first $second"
echo "support agent, in the middle of it: $support"
sleep 1

echo
echo "== Listing 12.6: spend by agent"
python3 "$REPO/tools/logq.py" "$LOG" protocol=llm --sum agw.ai.usage.cost.total --by agent.id

echo
echo "== Refused model calls, by agent and status"
python3 "$REPO/tools/logq.py" "$LOG" protocol=llm http.status!=200 --count-by agent.id,http.status

echo
echo "== The cost metric, by agent"
curl -s http://localhost:15020/metrics | grep '^agentgateway_gen_ai_client_cost_usd_total' | \
  sed -E 's/.*gen_ai_request_model="([^"]*)".*agent="([^"]*)"\} (.*)/  agent=\2 model=\1 usd=\3/'
