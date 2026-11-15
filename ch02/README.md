# Chapter 2: Your first agentgateway

`config.yaml` is Listing 2.3: `server-everything` behind the gateway on port 3000.

```bash
cd ch02 && agentgateway -f config.yaml
# in another terminal, from the repo root:
python3 tools/mcp_client.py list
python3 tools/mcp_client.py call echo message=hello
```

The first start downloads `server-everything` with `npx`, which can take a minute.

## Files

- `config.yaml`: Listing 2.3
- `../solutions/ch02-remote-target.yaml`: Your turn 2

## Check your work

```bash
./ch02/check.sh
```
