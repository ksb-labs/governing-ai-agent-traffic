# Your turn answers

Try each exercise before you look. Each chapter's `check.sh` tests these too.

| Chapter | File | What it does |
|---|---|---|
| 2 | `ch02-remote-target.yaml` | The company's accounts server as a remote target |
| 3 | `ch03-healthz.yaml` | A `/healthz` route the gateway answers by itself |
| 4 | `ch04-canary.yaml` | `classifier` as a weighted virtual model, 4 to 1 |
| 5 | `ch05-stdio-clear-env.yaml` | A stdio server with an empty environment plus `PATH` |
| 6 | `ch06-require-user.yaml` | Refuse A2A messages that don't name a user |
| 7 | `ch07-keyhash.yaml` | API keys stored as SHA-256 hashes |
| 8 | `ch08-coding-agent.yaml` | `fetch_email` for support only, and a `require` rule |
| 9 | `ch09-mask-accounts.yaml` | Mask account IDs before they reach a model |
| 10 | `ch10-audit-budget.yaml` | The hackathon budget in `Audit` mode |
| 11 | `ch11-errors-only.yaml` | Trace everything, export only failures |
| 12 | `ch12-refund-attempts.md` | Every refund attempt, in logq.py and SPL |
| 13 | (in `ch13/41-typo-policy.yaml`) | Read a policy's status to see it attached to nothing |
| 14 | `ch14-a2a-user-test.sh` | A tenth governance test for agent-to-agent calls |

Run the YAML answers from the chapter's own folder when they use relative paths (Chapters 5, 7, 10, and 11), for example:

```bash
cd ch05 && agentgateway -f ../solutions/ch05-stdio-clear-env.yaml
```
