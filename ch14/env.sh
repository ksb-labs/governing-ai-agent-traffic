# Source this before starting the Chapter 14 gateway or running its scripts:
#   cd ch14 && . ./env.sh
# Demo keys only. In production these come from a secret store.
export SUPPORT_AGENT_KEY="${SUPPORT_AGENT_KEY:-support-demo-key}"
export RECON_AGENT_KEY="${RECON_AGENT_KEY:-recon-demo-key}"
export CODING_AGENT_KEY="${CODING_AGENT_KEY:-coding-demo-key}"
export HACKATHON_AGENT_KEY="${HACKATHON_AGENT_KEY:-hackathon-demo-key}"
export OPENAI_API_KEY="${OPENAI_API_KEY:-sk-placeholder}"     # the stand-in model ignores it
if [ -z "${SESSION_KEY:-}" ]; then
  SESSION_KEY="$(openssl rand -hex 32 2>/dev/null || python3 -c 'import secrets; print(secrets.token_hex(32))')"
  export SESSION_KEY
fi
