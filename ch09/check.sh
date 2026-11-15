#!/usr/bin/env bash
# Chapter 9 labs: guards on real traffic, stopping the poisoned email, and the
# account-ID mask Your turn.
. "$(dirname "$0")/../lib/check-lib.sh"
check_header 9
require_free_ports 3000 4000 15000 8081 8083 8090
company llm docs accounts

send() {  # body -> "status body"
  curl -s -w '\n%{http_code}' http://localhost:4000/v1/chat/completions \
    -H "Content-Type: application/json" -d "$1"
}
user_msg() { chat_body support-writer "$1"; }
tool_msg() {
  python3 - "$1" <<'PY'
import json, sys
print(json.dumps({"model": "support-writer", "messages": [
  {"role": "user", "content": "Look up the customer."},
  {"role": "assistant", "content": None, "tool_calls": [{"id": "call_1", "type": "function",
     "function": {"name": "lookup_account", "arguments": "{\"account_id\": \"C123\"}"}}]},
  {"role": "tool", "tool_call_id": "call_1", "content": sys.argv[1]}]}))
PY
}

step "ch09/config.yaml: guards in both directions"
gw_start ch09 config.yaml 4000
r=$(send "$(user_msg 'My password=hunter2')")
expect_eq "My password=hunter2 gets 400" "400" "$(printf '%s' "$r" | tail -1)"
expect_contains "with the rejection text" "The request was rejected due to inappropriate content" "$r"
expect_not_contains "the model's log never shows hunter2" "hunter2" "$(cat company/.run/llm.log)"
r=$(send "$(user_msg 'Call us at (415) 555-0132 any time')")
expect_eq "a phone number in the echo gets 200" "200" "$(printf '%s' "$r" | tail -1)"
expect_contains "and the answer reads Call us at <PHONE_NUMBER> any time" "Call us at <PHONE_NUMBER> any time" "$r"
r=$(send "$(user_msg 'My SSN is 123-45-6789')")
expect_eq "an SSN in a user message gets 200 (the SSN guard reads only tool output)" "200" "$(printf '%s' "$r" | tail -1)"
r=$(send "$(tool_msg 'Customer SSN: 123-45-6789')")
expect_eq "the same SSN in a tool message gets 400" "400" "$(printf '%s' "$r" | tail -1)"
gw_stop

step "ch09/injection-guard.yaml in audit mode"
cp ch09/injection-guard.yaml "$CHECK_TMP/guard.yaml"
gw_start ch09 "$CHECK_TMP/guard.yaml" 3000
out=$(python3 company/support_agent.py "Customer C123 wrote in. Please read email E-881 and help them." 2>&1)
expect_contains "audit blocks nothing: the refund still goes through" "issued: 250.00 USD to C123" "$out"
wait_log 'agw.ai.guardrails' 5
expect_contains "but the model call that carried the email is marked" \
  '"phase": "request", "guard": "regex", "action": "audit"' "$(grep agw.ai.guardrails "$GW_LOG")"

step "The same guard in reject mode"
sed -i.bak 's/action: audit/action: reject/' "$CHECK_TMP/guard.yaml"; sleep 3
out=$(python3 company/support_agent.py "Customer C123 wrote in. Please read email E-881 and help them." 2>&1)
printf '%s\n' "$out" | tail -2 | sed 's/^/    /'
expect_contains "the model call fails with 400" \
  "agent: the model call failed with 400: The request was rejected due to inappropriate content" "$out"
expect_contains "and the agent stops" "agent: stopping." "$out"
expect_not_contains "no refund" "Refund R-" "$out"
gw_stop

step "Your turn: solutions/ch09-mask-accounts.yaml"
gw_start solutions ch09-mask-accounts.yaml 4000
r=$(send "$(user_msg 'Why was C123 charged twice?')")
expect_eq "Why was C123 charged twice? gets 200" "200" "$(printf '%s' "$r" | tail -1)"
expect_not_contains "the echoed answer has no C123" "C123" "$r"
expect_contains "it was masked to <masked>" "<masked>" "$r"
finish
