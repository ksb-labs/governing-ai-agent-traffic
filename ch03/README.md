# Chapter 3: Thinking in traffic types

`config.yaml` is the local edition of Listing 3.1. The ledger route points at the repo's ledger API on port 8082, so it needs no `backendTLS`. `listing-3.1.yaml` is the listing exactly as printed, which gets a 503 on your laptop.

```bash
company/start.sh ledger
cd ch03 && agentgateway -f config.yaml
curl -i 'http://localhost:3000/api/entries?account=C123'   # 200
curl -i http://localhost:3000/hello                          # 404
curl -i http://localhost:3000/mcp                            # 406
```

## Files

- `config.yaml`: the lab version
- `listing-3.1.yaml`: Listing 3.1 as printed
- `../solutions/ch03-healthz.yaml`: Your turn

## Check your work

```bash
./ch03/check.sh
```
