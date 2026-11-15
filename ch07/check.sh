#!/usr/bin/env bash
# Chapter 7 labs: keys and tokens with a real 200, the gateway's half of MCP
# sign-in, and the keyHash Your turn.
. "$(dirname "$0")/../lib/check-lib.sh"
check_header 7
require_free_ports 3000 4000 15000 8083 8090
company llm docs

llm() {  # extra curl args -> status code
  code http://localhost:4000/v1/chat/completions -H "Content-Type: application/json" \
    -d "$(chat_body gpt-5.6-luna "Hello!")" "$@"
}

step "ch07/apikeys.yaml: one key per agent"
gw_start ch07 apikeys.yaml 4000
expect_eq "no key gets 401" "401" "$(llm)"
expect_eq "an unknown key gets 401" "401" "$(llm -H 'Authorization: Bearer not-a-real-key')"
expect_eq "the body says only: authentication failed" "authentication failed" \
  "$(curl -s http://localhost:4000/v1/chat/completions -H 'Content-Type: application/json' -d "$(chat_body gpt-5.6-luna Hello!)")"
wait_log "invalid credentials" 3
expect_contains "the log says which: no API Key found" "api key authentication failure: no API Key found" "$(cat "$GW_LOG")"
expect_contains "the log says which: invalid credentials" "api key authentication failure: invalid credentials" "$(cat "$GW_LOG")"
expect_eq "the support agent's key gets 200" "200" "$(llm -H "Authorization: Bearer $SUPPORT_AGENT_KEY")"
expect_contains "the model saw the gateway's own provider key" "provider key seen: yes" "$(tail -1 company/.run/llm.log)"
gw_stop

step "ch07/jwt.yaml: the project's test key and token"
if [ ! -s ch07/pub-key ] || [ ! -s ch07/test-token.jwt ]; then ch07/get-test-keys.sh >/dev/null; fi
TOKEN="$(cat ch07/test-token.jwt)"
cp ch07/jwt.yaml ch07/.jwt-check.yaml
gw_start ch07 .jwt-check.yaml 4000
expect_eq "no token gets 401" "401" "$(llm)"
wait_log "no bearer token found" 3
expect_contains "the log says: no bearer token found" "no bearer token found" "$(cat "$GW_LOG")"
expect_eq "the test token gets 200" "200" "$(llm -H "Authorization: Bearer $TOKEN")"
sed -i.bak 's/audiences: \[test.agentgateway.dev\]/audiences: [agents.example.com]/' ch07/.jwt-check.yaml
sleep 3
expect_eq "change the audience, and the same token gets 401" "401" "$(llm -H "Authorization: Bearer $TOKEN")"
wait_log "InvalidAudience" 3
expect_contains "the log says why: InvalidAudience" "InvalidAudience" "$(cat "$GW_LOG")"
gw_stop
rm -f ch07/.jwt-check.yaml ch07/.jwt-check.yaml.bak

step "ch07/mcp-auth.yaml: the gateway's half of MCP sign-in"
gw_start ch07 mcp-auth.yaml 3000
out=$(python3 tools/mcp_client.py list 2>&1)
expect_contains "an MCP initialize with no token gets 401" "HTTP 401" "$out"
hdr=$(curl -s -D - -o /dev/null http://localhost:3000/mcp -X POST -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
expect_contains "with a www-authenticate header that points at the metadata" \
  'resource_metadata="http://localhost:3000/.well-known/oauth-protected-resource/mcp"' "$hdr"
meta=$(curl -s http://localhost:3000/.well-known/oauth-protected-resource/mcp)
printf '    %s\n' "$meta"
expect_contains "the metadata names the resource" '"resource":"http://localhost:3000/mcp"' "$meta"
expect_contains "and the authorization server" '"authorization_servers":["agentgateway.dev"]' "$meta"
out=$(python3 tools/mcp_client.py --token "$TOKEN" list 2>&1)
expect_contains "with the test token, the docs server's tools come back" "fetch_email" "$out"
gw_stop

step "Your turn: solutions/ch07-keyhash.yaml"
gw_start ch07 ../solutions/ch07-keyhash.yaml 4000
expect_eq "support-demo-key still gets 200" "200" "$(llm -H 'Authorization: Bearer support-demo-key')"
expect_eq "support-demo-key2 gets 401" "401" "$(llm -H 'Authorization: Bearer support-demo-key2')"
expect_not_contains "the file holds no key" "support-demo-key\"" "$(grep -v '^#' solutions/ch07-keyhash.yaml)"
finish
