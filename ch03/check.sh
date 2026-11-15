#!/usr/bin/env bash
# Chapter 3 lab: one port, three answers, plus the /healthz Your turn.
. "$(dirname "$0")/../lib/check-lib.sh"
check_header 3
need npx
require_free_ports 3000 15000 8082
company ledger

step "ch03/config.yaml: MCP and the ledger REST API on one port"
gw_start ch03 config.yaml 3000
expect_eq "/api/entries?account=C123 reaches the ledger" "200" "$(code 'http://localhost:3000/api/entries?account=C123')"
body=$(curl -s 'http://localhost:3000/api/entries?account=C123')
expect_contains "the ledger sends back C123's card-fee entries" '"id": "L-2"' "$body"
expect_eq "/hello matches no route" "404" "$(code http://localhost:3000/hello)"
expect_contains "the body says route not found" "route not found" "$(curl -s http://localhost:3000/hello)"
expect_eq "/mcp from a plain curl is refused" "406" "$(code http://localhost:3000/mcp)"
expect_contains "because it doesn't accept text/event-stream" "text/event-stream" "$(curl -s http://localhost:3000/mcp)"
gw_stop

step "Listing 3.1 as printed: a route to a backend that doesn't exist"
gw_start ch03 listing-3.1.yaml 3000
expect_eq "/api/entries gets 503" "503" "$(code http://localhost:3000/api/entries)"
gw_stop

step "Your turn: solutions/ch03-healthz.yaml"
gw_start solutions ch03-healthz.yaml 3000
expect_eq "curl /healthz prints gateway ok" "gateway ok" "$(curl -s http://localhost:3000/healthz)"
expect_eq "the ledger route still works" "200" "$(code 'http://localhost:3000/api/entries?account=C123')"
finish
