#!/usr/bin/env bash
# Chapter 5 labs: the whole company on one endpoint, one server down, and
# what a stdio server can read.
. "$(dirname "$0")/../lib/check-lib.sh"
check_header 5
require_free_ports 3000 15000 8081 8082 8083
company accounts docs ledger

step "ch05/config.yaml: docs, accounts, and the ledger behind one endpoint"
cp ch05/config.yaml "$CHECK_TMP/ch05.yaml"
gw_start ch05 "$CHECK_TMP/ch05.yaml" 3000
out=$(python3 tools/mcp_client.py list 2>&1)
printf '%s\n' "$out" | sed 's/^/    /'
expect_contains "6 tools" "6 tools" "$out"
for t in docs_search_kb_articles docs_fetch_email accounts_lookup_account accounts_issue_refund \
         ledger_list_entries ledger_delete_entry; do
  expect_contains "  $t" "$t" "$out"
done
out=$(python3 tools/mcp_client.py call ledger_list_entries query.account=C123 2>&1)
expect_contains "ledger_list_entries query.account=C123 returns L-2" '"L-2"' "$out"
python3 tools/mcp_client.py call ledger_delete_entry path.id=L-2 >/dev/null 2>&1
log=$(cat company/.run/ledger.log)
expect_contains "the ledger saw a plain GET" "GET /entries?account=C123" "$log"
expect_contains "and then a DELETE" "DELETE /entries/L-2" "$log"
out=$(python3 tools/mcp_client.py call ledger_list_entries query.account=C123 2>&1)
expect_not_contains "L-2 is gone" '"L-2"' "$out"

step "One server down"
kill "$(cat company/.run/accounts.pid)"; sleep 0.5
out=$(python3 tools/mcp_client.py list 2>&1)
expect_contains "with failClosed (the default), the whole session fails with HTTP 500" "HTTP 500" "$out"
sed -i.bak 's/^mcp:$/mcp:\n  failureMode: failOpen/' "$CHECK_TMP/ch05.yaml"
sleep 3
out=$(python3 tools/mcp_client.py list 2>&1)
expect_contains "after adding failureMode: failOpen, 4 tools" "4 tools" "$out"
expect_not_contains "and the accounts tools have dropped out" "accounts_" "$out"
gw_stop

step "Your turn: ch05/stdio-leak.yaml"
OPENAI_API_KEY=sk-pretend-this-is-real gw_start ch05 stdio-leak.yaml 3000
out=$(python3 tools/mcp_client.py call debug_env 2>&1)
expect_contains "debug_env shows the provider key" "OPENAI_API_KEY=sk-pretend-this-is-real" "$out"
expect_contains "and the session key" "SESSION_KEY=" "$out"
gw_stop

step "Your turn answer: solutions/ch05-stdio-clear-env.yaml"
OPENAI_API_KEY=sk-pretend-this-is-real gw_start ch05 ../solutions/ch05-stdio-clear-env.yaml 3000
out=$(python3 tools/mcp_client.py call debug_env 2>&1)
printf '%s\n' "$out" | cut -c1-70 | sed 's/^/    /'
n=$(printf '%s' "$out" | sed -n 's/^\([0-9]*\) environment variables.*/\1/p')
if [ -n "$n" ] && [ "$n" -le 2 ]; then pass "debug_env shows only PATH (and the locale Python adds)"; else fail "debug_env shows two variables" "$out"; fi
expect_contains "PATH came through" "PATH=" "$out"
expect_not_contains "and no provider key" "OPENAI_API_KEY" "$out"
expect_not_contains "and no session key" "SESSION_KEY" "$out"
finish
