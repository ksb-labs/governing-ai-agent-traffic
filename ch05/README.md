# Chapter 5: Federating MCP servers

`config.yaml` is Listings 5.1 and 5.3 together, pointed at the company's docs, accounts, and ledger. `listing-5.4.yaml` is the two-stdio-server version for the admin UI's Tool Playground.

```bash
company/start.sh accounts docs ledger
cd ch05 && agentgateway -f config.yaml
# from the repo root:
python3 tools/mcp_client.py list
python3 tools/mcp_client.py call ledger_list_entries query.account=C123
python3 tools/mcp_client.py call ledger_delete_entry path.id=L-2
```

The ledger keeps its entries in memory. Restart it (`company/stop.sh`, then start again) to get L-2 back.

`stdio-leak.yaml` is the Your turn: run it from the `ch05` folder so the relative path to `company/mcp_server.py` works. The answer turns on `clear_env`. With an empty environment, Python adds `LC_CTYPE` by itself on most systems, which is why `debug_env` shows two variables, not one.

## Files

- `config.yaml`: the lab
- `ledger-openapi.yaml`: Listing 5.2
- `listing-5.4.yaml`: Listing 5.4
- `stdio-leak.yaml`: Your turn setup
- `../solutions/ch05-stdio-clear-env.yaml`: Your turn answer

## Check your work

```bash
./ch05/check.sh
```
