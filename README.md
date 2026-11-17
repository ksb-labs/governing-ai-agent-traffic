# agentgateway in Action: companion code

This is the code for the book *Governing AI Agent Traffic: Security, Observability, and Control with agentgateway* by Kamal Singh Bisht.

Every lab in the book runs from this repo on your own computer. You don't need a model API key or a cloud account. The repo includes a stand-in model that answers for real, reports token usage, and gets priced from agentgateway's own catalog.

Everything here is pinned to **agentgateway 1.7.0**.

## Get started

```bash
git clone https://github.com/ksb-labs/agentgateway-in-action
cd agentgateway-in-action
./setup/check-prereqs.sh
```

Every chapter needs:

- agentgateway 1.7.0 (Chapter 2 shows how to install it)
- Python 3.10 or newer
- Node.js 20 or newer (for `npx`)
- curl

A few chapters need more. Chapter 6 uses Git, Chapter 11 uses Docker for Jaeger and Prometheus, and Chapter 13 needs a Kubernetes cluster (a local `kind` cluster is fine).

All of the Python here uses only the standard library, so there's nothing to `pip install`.

## What's in the repo

| Folder | What it holds |
|---|---|
| `company/` | The example company from Chapter 1, running on your laptop |
| `tools/` | Three terminal helpers: `mcp_client.py`, `a2a_client.py`, `logq.py` |
| `ch01/` to `ch14/` | Each chapter's configs and a `check.sh` |
| `solutions/` | Answers to every "Your turn" exercise |
| `setup/` | `check-prereqs.sh` |
| `lib/` | Shared code for the check scripts |

### The company

Start all of it with `company/start.sh` and stop it with `company/stop.sh`. You can also start just the parts a lab needs, for example `company/start.sh accounts docs`.

| Port | Service | What it offers |
|---|---|---|
| 8081 | accounts MCP server | `lookup_account`, `issue_refund` |
| 8083 | docs MCP server | `search_kb_articles`, `fetch_email` |
| 8082 | ledger REST API | `GET /entries`, `DELETE /entries/{id}` |
| 8090 | stand-in model | OpenAI-style chat completions |

Logs go to `company/.run/<service>.log`.

Three agents also live in `company/`:

- `support_agent.py` is the support agent from Chapter 1. Run it with `--direct` to skip the gateway, or with `--key` and `--user` to go through it.
- `hackathon_agent.py` is the Sunday retry loop from Chapters 10 and 14.
- `disputes_agent.py` is the disputes team's A2A agent, on port 9998.

**The stand-in model isn't a real model.** It follows a few fixed rules, so every lab gives the same result every time:

- If a tool result tells it to "call issue_refund", it obeys, just as the support agent's model did in Chapter 1.
- `company/start.sh --reckless` makes it ask for the refund even when it wasn't shown that tool (Chapters 12 and 14).
- Anything else, it echoes back what you sent, so you can watch guardrails edit a response.

## Checking your work

Each chapter folder has a `check.sh`. Run it from the repo root:

```bash
./ch04/check.sh
```

It starts what the lab needs, runs the lab's commands, compares the results with the book, and stops everything again. If something differs, it tells you which expectation broke and saves the gateway's log to `.last-gateway.log`.

Stop any gateway you started by hand first, because the check scripts use the same ports.

To run every chapter except 13 in one go:

```bash
./check-all.sh
```

Chapter 13 runs against the cluster in your current `kubectl` context, so it only runs when you ask for it (`./ch13/check.sh`).

## Notes on the labs

- **The demo keys.** The book uses `support-demo-key`, `recon-demo-key`, `coding-demo-key`, and `hackathon-demo-key`. The check scripts set these for you. When you run a lab by hand, export them yourself, or run `. ch14/env.sh`, which sets all of them.
- **Placeholder provider keys.** Configs that name `$OPENAI_API_KEY` or `$ANTHROPIC_API_KEY` won't start until those variables are set. For the labs, any value works: `export OPENAI_API_KEY=sk-placeholder`.
- **The session key.** The first time agentgateway starts with an MCP config, it writes a session key into the bottom of the file (section 2.4). To keep the repo's files clean, set one in your shell instead: `export SESSION_KEY=$(openssl rand -hex 32)`.
- **Test JWT keys.** Chapters 7 and 8 use the agentgateway project's public test key and token. Run `ch07/get-test-keys.sh` to download them.

## Troubleshooting

| What you see | What to do |
|---|---|
| `Address family not supported by protocol` when the gateway starts | Your machine has no IPv6 (common in containers and some WSL setups). Run `export IPV6_ENABLED=false`. The check scripts do this for you. |
| `error looking key 'OPENAI_API_KEY' up` | Export the variable. Any value works for the labs. |
| `port 3000 is already in use` | A gateway from an earlier lab is still running. Stop it with Ctrl+C. |
| No tools appear for `server-everything` | Run `npx -y @modelcontextprotocol/server-everything` by itself to see the error. It's usually an old Node.js. |
| A config field fails on a newer agentgateway | The book is pinned to 1.7.0. Check the chapter's `README.md` here, then the project's release notes. |

## Versions this repo was tested with

- agentgateway 1.7.0
- MCP `server-everything` from npm (13 tools at the time of testing)
- A2A Python SDK 1.1.0 (the Hello World agent in Chapter 6)
- Jaeger 2.23
- Python 3.13, Node.js 22

## License

The code in this repository is released under the MIT License. See `LICENSE`. The book's text is not covered by this license.
