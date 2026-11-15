#!/usr/bin/env bash
# Chapter 10 labs: hit the limit on purpose (Listing 10.4), per-agent buckets,
# a budget in real dollars, and the audit-mode Your turn.
. "$(dirname "$0")/../lib/check-lib.sh"
check_header 10
require_free_ports 4000 15000 8090
company llm
rm -f ch10/agentgateway.db* ch10/requests.db*

step "Listing 10.4: three requests a minute, and a password guard"
gw_start ch10 listing-10.4.yaml 4000
codes=""
for i in 1 2 3 4 5 6; do
  codes="$codes $(code http://localhost:4000/v1/chat/completions -H 'User-Agent: support-agent/1.0' \
    -H 'Content-Type: application/json' -d "$(chat_body support-writer 'My password=hunter2')")"
done
expect_eq "six identical requests" "403 403 403 429 429 429" "${codes# }"
hdr=$(curl -s -D - -o /dev/null http://localhost:4000/v1/chat/completions \
  -H 'Content-Type: application/json' -d "$(chat_body support-writer 'My password=hunter2')")
expect_contains "the 429 says how many are allowed" "x-ratelimit-limit: 3" "$hdr"
expect_match "and when to try again" "retry-after: [0-9]+" "$hdr"
gw_stop
rm -f ch10/requests.db*

step "ch10/limits.yaml: one bucket per agent"
gw_start ch10 limits.yaml 4000
out=$(python3 company/hackathon_agent.py --gateway http://localhost:4000 --key "$HACKATHON_AGENT_KEY" --times 8 --quiet-refusal)
expect_eq "the looping hackathon agent" "200 200 200 200 200 429 429 429" "$out"
out=$(python3 company/hackathon_agent.py --gateway http://localhost:4000 --key "$SUPPORT_AGENT_KEY" --times 2 --quiet-refusal)
expect_eq "the support agent never notices" "200 200" "$out"
line=$(grep "gen_ai.request.model=gpt-5.6-luna" "$GW_LOG" | head -1)
in=$(printf '%s' "$line" | grep -oE 'gen_ai.usage.input_tokens=[0-9]+' | cut -d= -f2)
outt=$(printf '%s' "$line" | grep -oE 'gen_ai.usage.output_tokens=[0-9]+' | cut -d= -f2)
expect_eq "each looping call uses about 690 tokens" "689" "$((in + outt))"
gw_stop

step "ch10/budgets.yaml: a tenth of a cent for the hackathon agent"
gw_start ch10 budgets.yaml 4000
out=$(python3 company/hackathon_agent.py --gateway http://localhost:4000 --key "$HACKATHON_AGENT_KEY" --times 10)
printf '%s\n' "$out" | sed 's/^/    /'
expect_eq "six calls fit, then refusals" "200 200 200 200 200 200 429 429 429 429" "$(printf '%s' "$out" | head -1)"
expect_contains "the refusal says budget_exceeded" '"code":"budget_exceeded"' "$out"
expect_contains "each call costs 0.0001818 USD" "agw.ai.usage.cost.total=0.0001818" "$(cat "$GW_LOG")"
gw_stop
gw_start ch10 budgets.yaml 4000
out=$(python3 company/hackathon_agent.py --gateway http://localhost:4000 --key "$HACKATHON_AGENT_KEY" --times 1 --quiet-refusal)
expect_eq "after a restart it's still refused (the total is in agentgateway.db)" "429" "$out"
out=$(python3 company/hackathon_agent.py --gateway http://localhost:4000 --key "$SUPPORT_AGENT_KEY" --times 1 --quiet-refusal)
expect_eq "the support agent's budget is untouched" "200" "$out"
gw_stop

step "Your turn: solutions/ch10-audit-budget.yaml"
rm -f ch10/agentgateway.db*
gw_start ch10 ../solutions/ch10-audit-budget.yaml 4000
out=$(python3 company/hackathon_agent.py --gateway http://localhost:4000 --key "$HACKATHON_AGENT_KEY" --times 10)
expect_eq "in Audit mode all ten get 200" "200 200 200 200 200 200 200 200 200 200" "$out"
body=$(curl -s http://localhost:4000/v1/chat/completions -H "Authorization: Bearer $HACKATHON_AGENT_KEY" \
  -H 'Content-Type: application/json' -d "$(chat_body support-writer Hello!)")
expect_contains "the hackathon key still can't use another model (allowedModels)" "model_not_allowed" "$body"
gw_stop
rm -f ch10/agentgateway.db*
finish
