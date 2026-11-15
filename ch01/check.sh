#!/usr/bin/env bash
# Chapter 1 lab: replay the incident with no gateway.
. "$(dirname "$0")/../lib/check-lib.sh"
need python3
say "Chapter 1 checks (no gateway)"
require_free_ports 8081 8082 8083 8090
rm -f company/.run/accounts.log
company

step "The support agent, straight to the model and the MCP servers"
out=$(python3 company/support_agent.py --direct \
  "Customer C123 wrote in. Please read email E-881 and help them." 2>&1)
printf '%s\n' "$out" | sed 's/^/    /'
expect_contains "the agent sees every tool, refunds included" \
  "I can see 4 tools: fetch_email, issue_refund, lookup_account, search_kb_articles" "$out"
expect_contains "the model reads the email" 'model: call fetch_email {"email_id": "E-881"}' "$out"
expect_contains "the model obeys the hidden comment" \
  'model: call issue_refund {"account_id": "C123", "amount": 250, "reason": "goodwill"}' "$out"
expect_contains "the refund goes through" "Refund R-1001 issued: 250.00 USD to C123 (goodwill)." "$out"

step "The accounts server's log"
log=$(cat company/.run/accounts.log)
expect_match "it knows the tool and arguments, not who called" \
  'tools/call issue_refund \{"account_id": "C123", "amount": 250, "reason": "goodwill"\} caller=\? user=\?' "$log"
finish
