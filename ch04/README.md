# Chapter 4: The LLM gateway

`config.yaml` is Listing 4.3 pointed at the stand-in model. `failover.yaml` is Listing 4.4 with the primary pointed at port 8099, where nothing listens.

```bash
company/start.sh llm
export OPENAI_API_KEY=sk-placeholder ANTHROPIC_API_KEY=placeholder
cd ch04 && agentgateway -f config.yaml
```

**Note:** in the lab config, `support-writer` is sent to the stand-in as `gpt-5.6` with the `openAI` provider, not as Anthropic's `claude-sonnet-5-5`. The stand-in only speaks the OpenAI format, and this keeps the price comparison in the lab's table (gpt-5.6 against gpt-5.6-luna).

## Files

- `config.yaml`: Listing 4.3, lab version
- `failover.yaml`: Listing 4.4, lab version
- `../solutions/ch04-canary.yaml`: Your turn

## Check your work

```bash
./ch04/check.sh
```
