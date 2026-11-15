# Chapter 12: Audit trails that hold up

`config.yaml` has Listings 12.1 and 12.2, tracing turned on so every record carries a `trace.id`, and Chapter 8's tool rules so denials land in the trail. The `spl/` folder holds Listings 12.4 to 12.7, ready for Splunk.

```bash
company/start.sh --reckless
. ch14/env.sh
cd ch12 && agentgateway -f config.yaml | tee gateway.log
```

Then make some history and run the searches with `tools/logq.py`, as in the book.

To use Splunk: in Splunk Web, go to Settings → Add Data → Upload, pick `gateway.log`, choose the `_json` source type, and put it in an index named `agentgw`. The SPL files then run as written. On the lab's data the agent is in `agent.id`, because the lab uses API keys. With JWTs it's `jwt.sub`.

## Files

- `config.yaml`: the lab
- `spl/`: Listings 12.4 to 12.7
- `../solutions/ch12-refund-attempts.md`: Your turn

## Check your work

```bash
./ch12/check.sh
```
