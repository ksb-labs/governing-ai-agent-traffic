#!/usr/bin/env bash
# Chapter 2 labs: drive the gateway from the terminal, plus the Your turn answers.
. "$(dirname "$0")/../lib/check-lib.sh"
check_header 2
need npx
require_free_ports 3000 15000 8081

step "Listing 2.3 (config.yaml) validates"
expect_eq "agentgateway --validate-only" "Configuration is valid!" \
  "$(cd ch02 && agentgateway --validate-only -f config.yaml 2>&1 | tail -1)"

step "Listing 2.3: server-everything behind the gateway (first run downloads it with npx)"
gw_start ch02 config.yaml 3000
out=$(python3 tools/mcp_client.py list 2>&1)
printf '%s\n' "$out" | head -4 | sed 's/^/    /'
expect_match "tools/list through the gateway returns tools" '^[0-9]+ tools' "$out"
expect_contains "echo is one of them" "echo" "$out"
expect_contains "get-env is one of them (it comes back in Chapter 5)" "get-env" "$out"
out=$(python3 tools/mcp_client.py call echo message=hello 2>&1)
expect_eq "call echo message=hello" "Echo: hello" "$out"
wait_log 'gen_ai.tool.name=echo' 5
expect_match "the gateway log names the tool" \
  'http.status=200 protocol=mcp mcp.method.name=tools/call mcp.target=everything.*gen_ai.tool.name=echo' "$(cat "$GW_LOG")"
gw_stop

step "Your turn 1: one wrong space before stdio:"
sed 's/^    stdio:/     stdio:/' ch02/config.yaml > "$CHECK_TMP/broken.yaml"
out=$(agentgateway --validate-only -f "$CHECK_TMP/broken.yaml" 2>&1)
expect_contains "validate-only names the problem" "mapping values are not allowed in this context" "$out"

step "Your turn 2: solutions/ch02-remote-target.yaml"
company accounts
gw_start solutions ch02-remote-target.yaml 3000
out=$(python3 tools/mcp_client.py list 2>&1)
expect_contains "lookup_account is listed" "lookup_account" "$out"
expect_contains "issue_refund is listed" "issue_refund" "$out"
finish
