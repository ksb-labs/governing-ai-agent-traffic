#!/usr/bin/env bash
# Chapter 13 lab: the accounts server and its rules in a cluster.
# Runs the whole lab, including the install, against the cluster in your
# current kubectl context. For a throwaway cluster: kind create cluster --name agw-book
# Set SKIP_INSTALL=1 if agentgateway is already installed.
. "$(dirname "$0")/../lib/check-lib.sh"
need kubectl python3 curl
say "Chapter 13 checks (cluster: $(kubectl config current-context 2>/dev/null || echo none))"
kubectl cluster-info >/dev/null 2>&1 || { say "kubectl can't reach a cluster. Try: kind create cluster --name agw-book"; exit 2; }
require_free_ports 3000
NS=agentgateway-system

if [ "${SKIP_INSTALL:-0}" != 1 ]; then
  need helm
  step "Install the Gateway API CRDs and agentgateway 1.7.0 (section 13.2)"
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.3/standard-install.yaml >/dev/null
  helm upgrade -i --create-namespace --namespace $NS --version v1.7.0 agentgateway-crds \
    oci://cr.agentgateway.dev/charts/agentgateway-crds >/dev/null
  helm upgrade -i --namespace $NS --version v1.7.0 agentgateway \
    oci://cr.agentgateway.dev/charts/agentgateway --wait >/dev/null
fi
kubectl get gatewayclass agentgateway >/dev/null 2>&1 && pass "the agentgateway GatewayClass is registered" \
  || { fail "the agentgateway GatewayClass is registered"; finish; }

step "Be the accounts team (10-accounts.yaml) and apply Listing 13.2 (20-gateway.yaml)"
kubectl create namespace accounts --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create configmap accounts-mcp-code -n accounts --from-file=company/mcp_server.py \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f ch13/10-accounts.yaml -f ch13/20-gateway.yaml >/dev/null
kubectl rollout status deploy/accounts-mcp -n accounts --timeout=180s >/dev/null \
  && pass "the accounts MCP server is running" || fail "the accounts MCP server is running"
kubectl wait --for=condition=Programmed gateway/agentgateway -n $NS --timeout=180s >/dev/null \
  && pass "the Gateway is programmed" || fail "the Gateway is programmed"

SVC=$(kubectl get svc -n $NS -l gateway.networking.k8s.io/gateway-name=agentgateway -o name | head -1)
[ -n "$SVC" ] || SVC=svc/agentgateway
kubectl port-forward -n $NS "$SVC" 3000:80 > "$CHECK_TMP/pf.log" 2>&1 &
BG_PIDS+=("$!")
wait_port 3000 20 || { fail "port-forward to $SVC" "$(cat "$CHECK_TMP/pf.log")"; finish; }

list_as() {  # key (or empty) -> tool list output, retried while config settles
  local out i
  for i in $(seq 1 30); do
    if [ -n "$1" ]; then out=$(python3 tools/mcp_client.py --token "$1" list 2>&1)
    else out=$(python3 tools/mcp_client.py list 2>&1); fi
    [ -n "${2:-}" ] && grep -qF -- "$2" <<< "$out" && break
    [ -z "${2:-}" ] && break
    sleep 2
  done
  printf '%s' "$out"
}

out=$(list_as "" "issue_refund")
expect_contains "tools/list through the cluster gateway shows lookup_account" "lookup_account" "$out"
expect_contains "and issue_refund" "issue_refund" "$out"

step "Bring Chapter 8 into the cluster (30-agent-keys.yaml, 40-mcp-policy.yaml)"
kubectl apply -f ch13/30-agent-keys.yaml -f ch13/40-mcp-policy.yaml >/dev/null
out=$(list_as "" "HTTP 401")
expect_contains "no key gets 401" "HTTP 401" "$out"
out=$(list_as support-demo-key "1 tools")
expect_contains "support sees one tool" "1 tools" "$out"
expect_contains "  lookup_account" "lookup_account" "$out"
out=$(list_as recon-demo-key "1 tools")
expect_contains "reconciliation sees one tool" "1 tools" "$out"
expect_contains "  issue_refund" "issue_refund" "$out"

step "Your turn: 41-typo-policy.yaml"
kubectl apply -f ch13/41-typo-policy.yaml >/dev/null && pass "kubectl apply accepts the typo"
sleep 5
kubectl get agentgatewaypolicy -n $NS | sed 's/^/    /'
attached=$(kubectl get agentgatewaypolicy deny-everything -n $NS \
  -o jsonpath='{.status.ancestors[*].conditions[?(@.type=="Attached")].status}' 2>/dev/null)
good=$(kubectl get agentgatewaypolicy mcp-agent-rules -n $NS \
  -o jsonpath='{.status.ancestors[*].conditions[?(@.type=="Attached")].status}' 2>/dev/null)
expect_contains "mcp-agent-rules says Attached: True" "True" "$good"
if grep -q True <<< "$attached"; then
  fail "deny-everything attached to nothing" "Attached: $attached"
else
  pass "deny-everything attached to nothing (Attached: ${attached:-no status at all})"
fi
out=$(list_as support-demo-key "1 tools")
expect_contains "and traffic didn't change" "lookup_account" "$out"
kubectl delete -f ch13/41-typo-policy.yaml >/dev/null 2>&1
finish
