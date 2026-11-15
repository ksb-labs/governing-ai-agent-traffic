# Chapter 14: Putting it all together

`config.yaml` is the finished gateway from section 14.1, on one port: a key per agent, the tool rules, the guards, per-agent token buckets and budgets, and traces, metrics, and JSON logs with agent and user on every record.

```bash
company/start.sh --reckless
cd ch14 && . ./env.sh && agentgateway -f config.yaml | tee gateway.log
# in a second terminal, in ch14:
./replay-poisoned-email.sh
./replay-looping-agent.sh
./governance-check.sh
```

`support-writer-noguard` is the same model with no tool-output guard. The email replay uses it as a stand-in for a guard that misses. Don't copy it into a real config.

The config also has a route for the disputes agent (`python3 company/disputes_agent.py`), which the Your turn's tenth test uses.

## Files

- `config.yaml`: the finished gateway
- `env.sh`: the demo keys
- `replay-poisoned-email.sh, replay-looping-agent.sh`: the two replays
- `governance-check.sh`: the checklist as tests
- `../solutions/ch14-a2a-user-test.sh`: Your turn, the tenth test

## Check your work

```bash
./ch14/check.sh
```
