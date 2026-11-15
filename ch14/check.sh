#!/usr/bin/env bash
# Chapter 14 labs: replay both incidents, and the checklist as tests.
. "$(dirname "$0")/../lib/check-lib.sh"
check_header 14
require_free_ports 3000 15000 15020 8081 8082 8083 8090 9998
company --reckless
bg python3 company/disputes_agent.py > "$CHECK_TMP/disputes.log" 2>&1
rm -f ch14/agentgateway.db*
gw_start ch14 config.yaml 3000
export GATEWAY_LOG="$GW_LOG"

step "Replay the poisoned email (ch14/replay-poisoned-email.sh)"
out=$(ch14/replay-poisoned-email.sh 2>&1)
printf '%s\n' "$out" | sed 's/^/    /' | cut -c1-110
expect_contains "first run: the tool-output guard refuses the model call" \
  "agent: the model call failed with 400: The request was rejected due to inappropriate content" "$out"
expect_contains "second run: the model asks for the refund and the gateway says unknown resource" "unknown resource" "$out"
expect_match "the denial is on record for agent support and user C123" "support +C123 +issue_refund +1" "$out"
expect_match "the trace shows the email fetch" "mcp +support +C123 +fetch_email +200" "$out"
expect_match "just before the refused call" "mcp +support +C123 +issue_refund +400 +Authorization" "$out"
expect_contains "the accounts server never saw a refund request" "The accounts server never saw a refund request." "$out"

step "Replay the looping agent (ch14/replay-looping-agent.sh)"
out=$(ch14/replay-looping-agent.sh 2>&1)
printf '%s\n' "$out" | sed 's/^/    /' | cut -c1-110
expect_contains "the hackathon agent is cut off by its own bucket" \
  "hackathon agent: 200 200 200 200 200 200 200 200 429 429 429 429" "$out"
expect_contains "the support agent's three calls in the middle get 200" "support agent, in the middle of it: 200 200 200" "$out"
refusals=$(printf '%s\n' "$out" | sed -n '/Refused model calls/,/cost metric/p')
expect_match "refusals: the hackathon agent's four 429s" "hackathon +429 +4" "$refusals"
expect_match "and the support agent's one guardrail 400" "support +400 +1" "$refusals"
expect_eq "nothing else" "2" "$(printf '%s\n' "$refusals" | grep -cE '^(hackathon|support|reconciliation|coding) ')"

step "The checklist as tests (ch14/governance-check.sh)"
out=$(ch14/governance-check.sh 2>&1)
printf '%s\n' "$out" | sed 's/^/    /'
expect_contains "9 of 9 gateway-side items pass" "9 of 9 gateway-side items pass." "$out"

step "Your turn, part 1: break one item on purpose"
sed 's/^      mode: strict$/      mode: optional/' ch14/config.yaml > "$CHECK_TMP/broken.yaml"
python3 - "$CHECK_TMP/broken.yaml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
# only the MCP block's key policy goes optional; the LLM one stays strict
first = s.index("mode: optional"); s = s[:first] + "mode: strict" + s[first + len("mode: optional"):]
open(p, "w").write(s)
PY
gw_stop; rm -f ch14/agentgateway.db*
gw_start ch14 "$CHECK_TMP/broken.yaml" 3000
export GATEWAY_LOG="$GW_LOG"
out=$(CONFIG=ch14/config.yaml ch14/governance-check.sh 2>&1)
expect_contains "the tool-call item fails" "[ ] A tool call with no credential fails" "$out"

step "Your turn, part 2: solutions/ch14-a2a-user-test.sh"
gw_stop; rm -f ch14/agentgateway.db*
gw_start ch14 config.yaml 3000
export GATEWAY_LOG="$GW_LOG"
out=$(solutions/ch14-a2a-user-test.sh 2>&1)
printf '%s\n' "$out" | sed 's/^/    /'
expect_contains "the tenth test passes" "[x] The original user's identity is recorded on agent-to-agent calls" "$out"
rm -f ch14/agentgateway.db*
finish
