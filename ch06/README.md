# Chapter 6: Agent-to-agent traffic

`config.yaml` is Listing 6.2 in front of the A2A Hello World agent. `two-agents.yaml` puts the Hello World agent on `/hello` and the disputes agent on `/disputes`.

`start-helloworld.sh` does Listing 6.1 for you: it clones the A2A samples into `.cache/`, sets up the virtual environment once, and runs the agent on port 9999.

```bash
ch06/start-helloworld.sh &                # or follow Listing 6.1 by hand
python3 company/disputes_agent.py &
cd ch06 && agentgateway -f two-agents.yaml
# from the repo root:
python3 tools/a2a_client.py send http://localhost:3000/disputes "dispute the 12 dollar fee"
python3 tools/a2a_client.py send http://localhost:3000/disputes "dispute the 12 dollar fee" \
  --header "x-end-user: C123"
```

The Hello World agent uses A2A 1.0 and refuses requests that don't send `A2A-Version: 1.0`. `a2a_client.py` sends it for you.

## Files

- `config.yaml`: Listing 6.2
- `two-agents.yaml`: the two-agents lab
- `start-helloworld.sh`: Listing 6.1 as a script
- `../solutions/ch06-require-user.yaml`: Your turn

## Check your work

```bash
./ch06/check.sh
```
