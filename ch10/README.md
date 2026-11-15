# Chapter 10: Stopping runaway agents

`limits.yaml` is Listing 10.2 with a 3,000-token bucket per agent. `budgets.yaml` is Listing 10.3 with the hackathon budget cut to a tenth of a cent. `listing-10.4.yaml` is the hit-the-limit lab.

```bash
company/start.sh llm
export SUPPORT_AGENT_KEY=support-demo-key HACKATHON_AGENT_KEY=hackathon-demo-key OPENAI_API_KEY=sk-placeholder
cd ch10 && agentgateway -f limits.yaml
# from the repo root:
python3 company/hackathon_agent.py --gateway http://localhost:4000 --key "$HACKATHON_AGENT_KEY" --times 8
```

Budget totals live in `ch10/agentgateway.db`. Delete it to start over.

## Files

- `limits.yaml`: per-agent buckets
- `budgets.yaml`: budgets in dollars
- `listing-10.4.yaml`: Listing 10.4
- `../solutions/ch10-audit-budget.yaml`: Your turn

## Check your work

```bash
./ch10/check.sh
```
