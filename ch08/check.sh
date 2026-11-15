#!/usr/bin/env bash
# Chapter 8 labs: least privilege for three agents, the refund replay by hand,
# the silent typo, and the coding-agent Your turn.
. "$(dirname "$0")/../lib/check-lib.sh"
check_header 8
require_free_ports 3000 15000 8081 8083
company accounts docs

tools_for() {  # key -> sorted, comma-separated tool names
  python3 tools/mcp_client.py --token "$1" list 2>&1 | awk 'NR>1 {print $1}' | sort | paste -sd, -
}

step "ch08/config.yaml: what each agent can see"
cp ch08/config.yaml "$CHECK_TMP/ch08.yaml"
gw_start ch08 "$CHECK_TMP/ch08.yaml" 3000
expect_eq "support" "accounts_lookup_account,docs_fetch_email,docs_search_kb_articles" "$(tools_for "$SUPPORT_AGENT_KEY")"
expect_eq "reconciliation" "accounts_issue_refund,docs_fetch_email,docs_search_kb_articles" "$(tools_for "$RECON_AGENT_KEY")"
expect_eq "coding" "docs_fetch_email,docs_search_kb_articles" "$(tools_for "$CODING_AGENT_KEY")"
expect_contains "no key at all gets 401" "HTTP 401" "$(python3 tools/mcp_client.py list 2>&1)"

step "Replay the attack by hand"
before=$(grep -c "tools/call issue_refund" company/.run/accounts.log)
out=$(python3 tools/mcp_client.py --token "$SUPPORT_AGENT_KEY" call accounts_issue_refund account_id=C123 amount=250 2>&1)
printf '    %s\n' "$out"
expect_contains "the support agent's refund call gets 400" "HTTP 400" "$out"
expect_contains "as if the tool didn't exist" '"message":"unknown resource"' "$out"
wait_log "authorization denied for tool" 3
expect_contains "the log has the real reason" "mcp: authorization denied for tool: accounts_issue_refund" "$(cat "$GW_LOG")"
expect_eq "the accounts server saw nothing" "$before" "$(grep -c "tools/call issue_refund" company/.run/accounts.log)"
out=$(python3 tools/mcp_client.py --token "$RECON_AGENT_KEY" call accounts_issue_refund account_id=C123 amount=250 2>&1)
expect_match "the reconciliation key issues the refund" "Refund R-[0-9]+ issued: 250.00 USD to C123" "$out"

step "The typo from section 8.1"
sed 's/apiKey.agent == "support"/apiKey.agnet == "support"/' "$CHECK_TMP/ch08.yaml" > "$CHECK_TMP/typo.yaml"
expect_eq "--validate-only accepts the misspelling" "Configuration is valid!" \
  "$(cd ch08 && agentgateway --validate-only -f "$CHECK_TMP/typo.yaml" 2>&1 | tail -1)"
cp "$CHECK_TMP/typo.yaml" "$CHECK_TMP/ch08.yaml"; sleep 3
expect_eq "and support quietly loses accounts_lookup_account" "docs_fetch_email,docs_search_kb_articles" "$(tools_for "$SUPPORT_AGENT_KEY")"
gw_stop

step "Your turn: solutions/ch08-coding-agent.yaml"
gw_start solutions ch08-coding-agent.yaml 3000
expect_eq "coding sees exactly one tool" "docs_search_kb_articles" "$(tools_for "$CODING_AGENT_KEY")"
expect_eq "support keeps the inbox" "accounts_lookup_account,docs_fetch_email,docs_search_kb_articles" "$(tools_for "$SUPPORT_AGENT_KEY")"
expect_eq "reconciliation loses the inbox" "accounts_issue_refund,docs_search_kb_articles" "$(tools_for "$RECON_AGENT_KEY")"
expect_contains "a key with no agent gets nothing" "0 tools" "$(python3 tools/mcp_client.py --token legacy-demo-key list 2>&1)"
finish
