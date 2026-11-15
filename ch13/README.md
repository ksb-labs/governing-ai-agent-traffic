# Chapter 13: Running on Kubernetes

These manifests were checked against the agentgateway 1.7.0 CRD schemas and the Gateway API v1.6.3 CRDs.

```bash
kind create cluster --name agw-book
# install agentgateway as in section 13.2, then:
kubectl create namespace accounts
kubectl create configmap accounts-mcp-code -n accounts --from-file=company/mcp_server.py
kubectl apply -f ch13/10-accounts.yaml -f ch13/20-gateway.yaml
kubectl get svc -n agentgateway-system
kubectl port-forward -n agentgateway-system svc/<gateway service> 3000:80
python3 tools/mcp_client.py list
kubectl apply -f ch13/30-agent-keys.yaml -f ch13/40-mcp-policy.yaml
```

`check.sh` runs the whole lab, including the install, against the cluster in your current `kubectl` context. Set `SKIP_INSTALL=1` if agentgateway is already installed.

## Files

- `10-accounts.yaml`: the accounts MCP server in the cluster
- `20-gateway.yaml`: Listing 13.2, unchanged
- `30-agent-keys.yaml`: the agent keys as a Secret
- `40-mcp-policy.yaml`: Chapter 8's rules as an AgentgatewayPolicy
- `41-typo-policy.yaml`: Your turn
- `listing-13.3-13.4.yaml`: Listings 13.3 and 13.4

## Check your work

```bash
./ch13/check.sh
```
