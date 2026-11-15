#!/usr/bin/env bash
# Section 14.4's checklist as tests against the live gateway. Run it from
# ch14 while the gateway from config.yaml is running and logging to gateway.log.
# Put it in CI next to agentgateway --validate-only.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
. "$HERE/env.sh"
GW="${GATEWAY:-http://localhost:3000}"
LOG="${GATEWAY_LOG:-$HERE/gateway.log}"
CONFIG="${CONFIG:-$HERE/config.yaml}"
MCP="python3 $REPO/tools/mcp_client.py --url $GW/mcp"
passed=0; total=0

check() {  # description, then a command that succeeds when the item holds
  local desc="$1"; shift
  total=$((total + 1))
  if "$@" >/dev/null 2>&1; then echo "  [x] $desc"; passed=$((passed + 1)); else echo "  [ ] $desc"; fi
}
status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
body() { printf '{"model": "%s", "messages": [{"role": "user", "content": "Hello!"}]}' "$1"; }

# Each test captures output first and then greps it, so pipefail can't trip on grep -q.
has() { grep -qE -- "$2" <<< "$1"; }

no_key_model_call() {
  [ "$(status "$GW/v1/chat/completions" -H 'Content-Type: application/json' -d "$(body support-writer)")" = 401 ]
}
no_key_tool_call() { ! $MCP list; }
support_no_refund() {
  local tools; tools=$($MCP --token "$SUPPORT_AGENT_KEY" list) || return 1
  has "$tools" fetch_email && ! has "$tools" issue_refund
}
hackathon_kb_only() {
  local tools; tools=$($MCP --token "$HACKATHON_AGENT_KEY" list) || return 1
  [ "$(printf '%s\n' "$tools" | awk 'NR>1 {print $1}' | paste -sd, -)" = docs_search_kb_articles ]
}
model_not_given() {
  [ "$(status "$GW/v1/chat/completions" -H "Authorization: Bearer $HACKATHON_AGENT_KEY" \
       -H 'Content-Type: application/json' -d "$(body support-writer)")" = 403 ]
}
no_secrets_in_config() {
  local cfg; cfg=$(grep -vE '^\s*#' "$CONFIG")
  # every agent key and provider key must come from the environment ($NAME)...
  ! has "$(printf '%s\n' "$cfg" | grep -E '^\s*- key:|^\s*apiKey:\s*\S')" ':\s*"?[^"$ ]' || return 1
  # ...and no provider key or generated session key may sit in the file
  ! has "$cfg" 'sk-[A-Za-z0-9]{8,}' && ! has "$cfg" 'key:\s*[0-9a-f]{64}'
}
audit_names_agent_and_user() {
  python3 "$REPO/company/support_agent.py" --key "$SUPPORT_AGENT_KEY" --user C789 "Hello" >/dev/null 2>&1
  sleep 1
  [ -n "$(python3 "$REPO/tools/logq.py" "$LOG" agent.id=support enduser.id=C789)" ]
}
audit_has_trace_id() { [ -n "$(python3 "$REPO/tools/logq.py" "$LOG" enduser.id=C789 'trace.id=*')" ]; }
metrics_by_agent() { has "$(curl -s http://localhost:15020/metrics)" 'agent="support"'; }

check "A model call with no credential fails (401)" no_key_model_call
check "A tool call with no credential fails" no_key_tool_call
check "The support agent can't see the refund tool" support_no_refund
check "The hackathon agent sees only the knowledge base" hackathon_kb_only
check "An agent can't use a model it wasn't given (403)" model_not_given
check "No secrets in the config file" no_secrets_in_config
check "Audit records name the agent and the user" audit_names_agent_and_user
check "Audit records carry a trace ID" audit_has_trace_id
check "Metrics are labeled by agent" metrics_by_agent
echo "$passed of $total gateway-side items pass."
[ "$passed" -eq "$total" ]
