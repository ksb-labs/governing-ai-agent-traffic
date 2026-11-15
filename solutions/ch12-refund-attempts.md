# Chapter 12, Your turn: every refund attempt, allowed or not

Counted by agent and status. On the lab's data you should see `support 400`
and `reconciliation 200`.

## logq.py

```
python3 tools/logq.py ch12/gateway.log gen_ai.tool.name=issue_refund \
  --count-by agent.id,http.status
```

```
agent.id        status  count
support         400     1
reconciliation  200     1
```

## SPL

```
index=agentgw protocol=mcp gen_ai.tool.name="issue_refund"
| stats count by agent.id http.status
```

Leaving out `http.status=200` is the whole trick: Listing 12.4 asks what
happened, and this search asks what was tried.
