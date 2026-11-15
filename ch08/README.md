# Chapter 8: Authorization for tools

`config.yaml` is Listing 8.1 with API keys in place of `jwtAuth`, and rules that read `apiKey.agent` where the listing reads `jwt.sub`. `listing-8.2.yaml` is Listing 8.2, with the test key from Chapter 7.

```bash
company/start.sh accounts docs
export SUPPORT_AGENT_KEY=support-demo-key RECON_AGENT_KEY=recon-demo-key CODING_AGENT_KEY=coding-demo-key
cd ch08 && agentgateway -f config.yaml
# from the repo root:
python3 tools/mcp_client.py --token "$SUPPORT_AGENT_KEY" list
python3 tools/mcp_client.py --token "$SUPPORT_AGENT_KEY" call accounts_issue_refund account_id=C123 amount=250
```

## Files

- `config.yaml`: the lab
- `listing-8.2.yaml`: Listing 8.2
- `../solutions/ch08-coding-agent.yaml`: Your turn

## Check your work

```bash
./ch08/check.sh
```
