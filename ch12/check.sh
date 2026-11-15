#!/usr/bin/env bash
# Chapter 12 lab: make some history, then run the four searches from section
# 12.5 with tools/logq.py, plus the refund-attempts Your turn.
. "$(dirname "$0")/../lib/check-lib.sh"
check_header 12
require_free_ports 3000 15000 8081 8082 8083 8090
company --reckless

step "Make some history"
gw_start ch12 config.yaml 3000
LOG="$GW_LOG"
python3 company/support_agent.py --key "$SUPPORT_AGENT_KEY" --user C123 \
  "Customer C123 wrote in. Please read email E-881 and help them." > "$CHECK_TMP/support.out" 2>&1
expect_contains "the reckless model asks for the refund anyway, and the gateway says no" \
  "unknown resource" "$(cat "$CHECK_TMP/support.out")"
out=$(python3 tools/mcp_client.py --token "$RECON_AGENT_KEY" --header "x-end-user: C456" \
  call accounts_issue_refund account_id=C456 amount=12 reason=duplicate-fee 2>&1)
expect_contains "the reconciliation agent issues a real refund for C456" "12.00 USD to C456" "$out"
out=$(python3 company/hackathon_agent.py --key "$HACKATHON_AGENT_KEY" --times 5)
expect_eq "the hackathon agent runs its loop" "200 200 200 200 200" "$out"
sleep 1

step "12.4 Every refund, and for whom"
out=$(python3 tools/logq.py "$LOG" gen_ai.tool.name=issue_refund http.status=200 \
  --table time,agent.id,enduser.id,mcp.target,trace.id)
printf '%s\n' "$out" | sed 's/^/    /'
expect_eq "exactly one row" "1" "$(printf '%s\n' "$out" | tail -n +2 | grep -c .)"
expect_match "reconciliation, for C456" "reconciliation +C456 +accounts" "$out"

step "12.5 Denials by agent"
out=$(python3 tools/logq.py "$LOG" reason=Authorization --since 24h --count-by agent.id,gen_ai.tool.name)
printf '%s\n' "$out" | sed 's/^/    /'
expect_match "the support agent's refund attempt" "support +issue_refund +1" "$out"

step "12.6 Spend by agent"
out=$(python3 tools/logq.py "$LOG" protocol=llm --sum agw.ai.usage.cost.total --by agent.id --per hour)
printf '%s\n' "$out" | sed 's/^/    /'
expect_contains "a row for the hackathon agent" "hackathon" "$out"
expect_contains "and one for support" "support" "$out"

step "12.7 One request, start to end"
trace=$(python3 tools/logq.py "$LOG" reason=Authorization | head -1 | \
  python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["trace.id"])')
out=$(python3 tools/logq.py "$LOG" "trace.id=$trace" \
  --table time,protocol,agent.id,gen_ai.request.model,gen_ai.tool.name,http.status,reason)
printf '%s\n' "$out" | sed 's/^/    /'
expect_match "the email fetch" "mcp +support +fetch_email +200" "$out"
expect_match "then the refused refund" "mcp +support +issue_refund +400 +Authorization" "$out"
fetch=$(printf '%s\n' "$out" | grep -n fetch_email | cut -d: -f1)
refund=$(printf '%s\n' "$out" | grep -n issue_refund | cut -d: -f1)
if [ -n "$fetch" ] && [ -n "$refund" ] && [ "$fetch" -lt "$refund" ]; then pass "in the order it happened"; else fail "in the order it happened"; fi

step "Your turn: every refund attempt (solutions/ch12-refund-attempts.md)"
out=$(python3 tools/logq.py "$LOG" gen_ai.tool.name=issue_refund --count-by agent.id,http.status)
printf '%s\n' "$out" | sed 's/^/    /'
expect_match "support 400" "support +400 +1" "$out"
expect_match "reconciliation 200" "reconciliation +200 +1" "$out"
finish
