#!/usr/bin/env bash
# Chapter 11 labs: one trace across every hop, spend by agent, and the
# errors-only Your turn. Trace checks need Jaeger from ch11/docker-compose.yml;
# without it they're skipped and the metrics checks still run.
. "$(dirname "$0")/../lib/check-lib.sh"
check_header 11
require_free_ports 3000 15000 15020 8081 8083 8090
company llm docs accounts

JAEGER=0
if curl -sf -o /dev/null http://localhost:16686/api/v3/services; then JAEGER=1
elif command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  step "Starting Jaeger and Prometheus with docker compose"
  docker compose -f ch11/docker-compose.yml up -d >/dev/null 2>&1 && \
    for i in $(seq 1 60); do curl -sf -o /dev/null http://localhost:16686/api/v3/services && JAEGER=1 && break; sleep 1; done
fi

# Spans of one trace from Jaeger's API, one per line: name<TAB>agent.id<TAB>enduser.id
spans_of() {
  curl -s "http://localhost:16686/api/v3/traces/$1" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
for rs in d.get("result", {}).get("resourceSpans", []):
    for ss in rs.get("scopeSpans", []):
        for sp in ss.get("spans", []):
            a = {x["key"]: list(x["value"].values())[0] for x in sp.get("attributes", [])}
            print("\t".join([sp["name"], str(a.get("agent.id", "")), str(a.get("enduser.id", ""))]))
'
}

step "ch11/config.yaml: the support agent for customer C123"
gw_start ch11 config.yaml 3000
out=$(python3 company/support_agent.py --key "$SUPPORT_AGENT_KEY" --user C123 \
  "Customer C123 wrote in. Please read email E-881 and help them." 2>&1)
printf '%s\n' "$out" | head -1 | sed 's/^/    /'
trace=$(printf '%s' "$out" | sed -n 's/^agent: trace \([0-9a-f]\{32\}\)$/\1/p')
expect_match "the first line is the trace ID it started" '^[0-9a-f]{32}$' "$trace"
if [ $JAEGER -eq 1 ]; then
  sleep 8
  spans=$(spans_of "$trace")
  n=$(printf '%s\n' "$spans" | grep -c .)
  say "    Jaeger has $n spans for that trace"
  if [ "$n" -ge 12 ]; then pass "one trace holds every hop"; else fail "one trace holds every hop" "only $n spans"; fi
  for name in "tools/call docs_fetch_email" "tools/call accounts_issue_refund" "POST /v1/chat/completions"; do
    expect_contains "  it has a span for $name" "$name" "$spans"
  done
  expect_contains "  the agent's spans carry agent.id support and enduser.id C123" "$(printf 'tools/call\tsupport\tC123')" "$spans"
else
  skip "trace checks (start Jaeger with: docker compose -f ch11/docker-compose.yml up -d)"
fi

step "Spend by agent"
python3 company/hackathon_agent.py --key "$HACKATHON_AGENT_KEY" --times 3 >/dev/null
sleep 1
m=$(curl -s http://localhost:15020/metrics | grep '^agentgateway_gen_ai_client_cost_usd_total')
printf '%s\n' "$m" | sed 's/^/    /' | cut -c1-120
expect_contains "a cost series for the support agent" 'agent="support"' "$m"
expect_contains "and one for the hackathon agent" 'agent="hackathon"' "$m"
gw_stop

step "Your turn: solutions/ch11-errors-only.yaml"
if [ $JAEGER -eq 1 ]; then
  gw_start ch11 ../solutions/ch11-errors-only.yaml 3000
  good=$(openssl rand -hex 16); bad=$(openssl rand -hex 16)
  for pair in "$good:$SUPPORT_AGENT_KEY" "$bad:wrong-key"; do
    t=${pair%%:*}; k=${pair#*:}
    curl -s -o /dev/null http://localhost:3000/v1/chat/completions -H "Authorization: Bearer $k" \
      -H "traceparent: 00-$t-$(openssl rand -hex 8)-01" -H 'Content-Type: application/json' \
      -d "$(chat_body support-writer Hello!)"
  done
  sleep 8
  expect_eq "the good request isn't in Jaeger" "" "$(spans_of "$good")"
  expect_contains "the 401 is, as POST /*" "POST /*" "$(spans_of "$bad")"
else
  skip "needs Jaeger"
fi
finish
