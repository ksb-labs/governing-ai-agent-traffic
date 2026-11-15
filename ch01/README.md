# Chapter 1: Why AI agents need a gateway

Replay the Chapter 1 incident with no gateway in the way.

```bash
company/start.sh
python3 company/support_agent.py --direct \
  "Customer C123 wrote in. Please read email E-881 and help them."
cat company/.run/accounts.log
company/stop.sh
```

The accounts server's log records the refund with `caller=? user=?`: it knows the tool and the arguments, but not which agent called or for whom.

The agent prints the whole email when it fetches it. The book shows only the hidden comment at the end, to fit the page.

## Check your work

```bash
./ch01/check.sh
```
