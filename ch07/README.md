# Chapter 7: Identity at the edge

`apikeys.yaml` and `jwt.yaml` are Listings 7.1 and 7.3 with a `baseUrl` added, so the last request gets a real 200 from the stand-in. `mcp-auth.yaml` is Listing 7.4 with the project's test key and the company's docs server.

```bash
ch07/get-test-keys.sh                     # downloads pub-key and test-token.jwt
company/start.sh llm docs
export SUPPORT_AGENT_KEY=support-demo-key RECON_AGENT_KEY=recon-demo-key OPENAI_API_KEY=sk-placeholder
cd ch07 && agentgateway -f apikeys.yaml
```

Run the gateway from the `ch07` folder, because `jwt.yaml` and `mcp-auth.yaml` read `./pub-key`.

## Files

- `apikeys.yaml`: Listing 7.1, lab version
- `jwt.yaml`: Listing 7.3, lab version
- `mcp-auth.yaml`: Listing 7.4, lab version
- `get-test-keys.sh`: downloads the public test key and token
- `../solutions/ch07-keyhash.yaml`: Your turn

## Check your work

```bash
./ch07/check.sh
```
