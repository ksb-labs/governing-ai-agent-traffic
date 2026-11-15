#!/usr/bin/env bash
# Chapter 4 labs: same prompt, different price; kill the provider; the canary Your turn.
. "$(dirname "$0")/../lib/check-lib.sh"
check_header 4
require_free_ports 4000 15000 8090
company llm

hello() {  # model -> status code
  code http://localhost:4000/v1/chat/completions -H "Content-Type: application/json" \
    -d "$(chat_body "$1" "Hello!")"
}
field() {  # log line, field name
  printf '%s' "$1" | grep -oE "$2=[^ ]+" | head -1 | cut -d= -f2 | tr -d '"'
}

step "ch04/config.yaml: three aliases, one stand-in model"
gw_start ch04 config.yaml 4000
models=$(curl -s http://localhost:4000/v1/models)
for m in support-writer classifier local-private; do
  expect_contains "/v1/models lists $m" "\"$m\"" "$models"
done
expect_not_contains "and nothing about the real model names" "gpt-5.6" "$models"

for row in "support-writer gpt-5.6 0.000436" "classifier gpt-5.6-luna 0.0000258" "local-private llama3 -"; do
  set -- $row
  expect_eq "Hello! to $1 gets 200" "200" "$(hello "$1")"
  wait_log "gen_ai.request.model=$2 " 5
  line=$(grep "gen_ai.request.model=$2 " "$GW_LOG" | tail -1)
  expect_eq "  sent as $2, 9 tokens in, 20 out" "9/20" "$(field "$line" gen_ai.usage.input_tokens)/$(field "$line" gen_ai.usage.output_tokens)"
  if [ "$3" = "-" ]; then
    expect_eq "  no cost, because llama3 isn't in the price catalog" "" "$(field "$line" agw.ai.usage.cost.total)"
  else
    expect_eq "  costs $3 USD" "$3" "$(field "$line" agw.ai.usage.cost.total)"
  fi
done
gw_stop

step "ch04/failover.yaml: the primary is dead"
gw_start ch04 failover.yaml 4000
codes="$(hello support-writer) $(hello support-writer) $(hello support-writer)"
expect_eq "three requests for support-writer" "503 200 200" "$codes"
expect_contains "the first failure is logged" "reason=UpstreamFailure" "$(cat "$GW_LOG")"
expect_eq "writer-backup by name is hidden" "404" "$(hello writer-backup)"
gw_stop

step "Your turn: solutions/ch04-canary.yaml"
gw_start solutions ch04-canary.yaml 4000
for i in $(seq 1 40); do hello classifier >/dev/null; done
sleep 1
mini=$(grep -c "gen_ai.request.model=gpt-5.6-mini " "$GW_LOG")
say "    $mini of 40 went to gpt-5.6-mini"
if [ "$mini" -ge 2 ] && [ "$mini" -le 16 ]; then pass "about 8 of 40 requests go to the canary"; else fail "about 8 of 40 requests go to the canary" "got $mini"; fi
finish
