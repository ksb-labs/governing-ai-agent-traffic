# Chapter 11: Seeing every call

`config.yaml` is Listings 11.1, 11.2, and 11.4 together, in front of the company's model and tools, with the agent keys from Chapter 7.

```bash
docker compose -f ch11/docker-compose.yml up -d     # Jaeger on :16686, Prometheus on :9090
company/start.sh llm docs accounts
. ch14/env.sh                                       # the demo keys
cd ch11 && agentgateway -f config.yaml
# from the repo root:
python3 company/support_agent.py --key "$SUPPORT_AGENT_KEY" --user C123 \
  "Customer C123 wrote in. Please read email E-881 and help them."
```

The same keys guard both the model and the tools, so the config writes them once (`&agent-keys`) and reuses them (`*agent-keys`). That's a standard YAML anchor.

`check.sh` runs the trace checks only when Jaeger is reachable on port 16686. It talks to Jaeger 2's `/api/v3` query API.

## Files

- `config.yaml`: the lab
- `docker-compose.yml and prometheus.yml`: Jaeger and Prometheus
- `../solutions/ch11-errors-only.yaml`: Your turn

## Check your work

```bash
./ch11/check.sh
```
