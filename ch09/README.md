# Chapter 9: Guardrails in the path

`config.yaml` is Listings 9.1 and 9.2 on one model, pointed at the stand-in. Because the stand-in echoes what you send, you can watch guards act in both directions. `injection-guard.yaml` puts the model and the tools on port 3000 with a tool-output guard in audit mode. `listing-9.1.yaml` is Listings 9.1 and 9.3 for the admin UI's Chat Playground.

```bash
company/start.sh llm docs accounts
cd ch09 && agentgateway -f injection-guard.yaml
# from the repo root:
python3 company/support_agent.py "Customer C123 wrote in. Please read email E-881 and help them."
```

Change `action: audit` to `action: reject` and save, then run the agent again.

## Files

- `config.yaml`: the guards lab
- `injection-guard.yaml`: the poisoned email lab
- `listing-9.1.yaml`: Listings 9.1 and 9.3
- `../solutions/ch09-mask-accounts.yaml`: Your turn

## Check your work

```bash
./ch09/check.sh
```
