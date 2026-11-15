# Shared helpers for the chNN/check.sh scripts. Source it; don't run it.
#
# Each check script starts what its lab needs, runs the lab's commands,
# compares the results with the book, and stops everything again.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

# The demo keys the book uses. Override any of them by exporting it first.
export SUPPORT_AGENT_KEY="${SUPPORT_AGENT_KEY:-support-demo-key}"
export RECON_AGENT_KEY="${RECON_AGENT_KEY:-recon-demo-key}"
export CODING_AGENT_KEY="${CODING_AGENT_KEY:-coding-demo-key}"
export HACKATHON_AGENT_KEY="${HACKATHON_AGENT_KEY:-hackathon-demo-key}"
export OPENAI_API_KEY="${OPENAI_API_KEY:-sk-placeholder}"
export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-placeholder}"
# A session key in the environment stops the gateway writing one into the config file.
if [ -z "${SESSION_KEY:-}" ]; then
  SESSION_KEY="$(openssl rand -hex 32 2>/dev/null || python3 -c 'import secrets; print(secrets.token_hex(32))')"
  export SESSION_KEY
fi

# Machines without IPv6 (some containers and WSL setups) can't bind the
# gateway's default [::] addresses. Tell it to use IPv4 only there.
if [ -z "${IPV6_ENABLED:-}" ] && { [ ! -s /proc/net/if_inet6 ] && [ "$(uname -s)" = Linux ]; }; then
  export IPV6_ENABLED=false
fi

PASS=0
FAIL=0
GW_PID=""
GW_LOG=""
BG_PIDS=()
CHECK_TMP="$(mktemp -d)"
COMPANY_STARTED=0

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
pass() { printf '  [ok]   %s\n' "$1"; PASS=$((PASS + 1)); }
fail() {
  printf '  [FAIL] %s\n' "$1"
  if [ -n "${2:-}" ]; then printf '%s\n' "$2" | sed 's/^/         /' | head -15; fi
  FAIL=$((FAIL + 1))
}
skip() { printf '  [skip] %s\n' "$1"; }

expect_eq() {       # description expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected: $2"$'\n'"got:      $3"; fi
}
expect_contains() { # description needle haystack
  if grep -qF -- "$2" <<< "$3"; then pass "$1"; else fail "$1" "expected to find: $2"$'\n'"in: $(printf '%s' "$3" | head -c 600)"; fi
}
expect_not_contains() {
  if grep -qF -- "$2" <<< "$3"; then fail "$1" "did not expect: $2"; else pass "$1"; fi
}
expect_match() {    # description regex haystack
  if grep -qE -- "$2" <<< "$3"; then pass "$1"; else fail "$1" "expected to match: $2"$'\n'"in: $(printf '%s' "$3" | head -c 600)"; fi
}

need() {
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      say "This check needs '$c', which isn't on your PATH. See setup/check-prereqs.sh."
      exit 2
    fi
  done
}

port_up() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

require_free_ports() {
  local busy=()
  for p in "$@"; do port_up "$p" && busy+=("$p"); done
  if [ ${#busy[@]} -gt 0 ]; then
    say "Port(s) ${busy[*]} are in use. Stop any gateway or service you started by hand, then run this again."
    exit 2
  fi
}

wait_port() {       # port [seconds]
  local i
  for i in $(seq 1 $(( ${2:-20} * 10 ))); do port_up "$1" && return 0; sleep 0.1; done
  return 1
}

company() {         # company/start.sh arguments
  "$REPO/company/start.sh" "$@" > "$CHECK_TMP/company.out" 2>&1 || {
    cat "$CHECK_TMP/company.out"; say "Couldn't start the company's services."; exit 1; }
  COMPANY_STARTED=1
}

# gw_start <dir> <config> [ports to wait for...]
# Starts agentgateway in <dir> with -f <config>, logging to $GW_LOG.
gw_start() {
  local dir="$1" cfg="$2"; shift 2
  gw_stop
  GW_LOG="$CHECK_TMP/gateway-$(basename "$cfg" .yaml).log"
  (cd "$dir" && exec agentgateway -f "$cfg") > "$GW_LOG" 2>&1 &
  GW_PID=$!
  local ready=0 i
  for i in $(seq 1 600); do
    if ! kill -0 "$GW_PID" 2>/dev/null; then break; fi
    if curl -sf -o /dev/null http://localhost:15021/healthz/ready; then ready=1; break; fi
    sleep 0.1
  done
  if [ $ready -eq 0 ]; then
    fail "gateway starts with $dir/$cfg" "$(grep -m3 -iE 'error|invalid' "$GW_LOG" || tail -5 "$GW_LOG")"
    if grep -q "Address family not supported" "$GW_LOG"; then
      say "         Your machine has no IPv6. Run: export IPV6_ENABLED=false"
    fi
    GW_PID=""
    say "  Stopping here, since the rest of this chapter needs that gateway."
    finish
  fi
  for p in "$@"; do wait_port "$p" 30 || true; done
  return 0
}

gw_stop() {
  if [ -n "$GW_PID" ] && kill -0 "$GW_PID" 2>/dev/null; then
    kill "$GW_PID" 2>/dev/null
    local i; for i in $(seq 1 50); do kill -0 "$GW_PID" 2>/dev/null || break; sleep 0.1; done
    kill -9 "$GW_PID" 2>/dev/null || true
  fi
  GW_PID=""
}

# Wait until the gateway has written a log line matching a pattern.
wait_log() {        # pattern [seconds]
  local i
  for i in $(seq 1 $(( ${2:-5} * 10 ))); do grep -qE -- "$1" "$GW_LOG" 2>/dev/null && return 0; sleep 0.1; done
  return 1
}

bg() { "$@" & BG_PIDS+=("$!"); }

# status code of a request: code <curl args...>
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

chat_body() {       # model content
  python3 -c 'import json,sys; print(json.dumps({"model": sys.argv[1], "messages": [{"role": "user", "content": sys.argv[2]}]}))' "$1" "$2"
}

cleanup() {
  gw_stop
  for p in "${BG_PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  if [ $COMPANY_STARTED -eq 1 ]; then "$REPO/company/stop.sh" >/dev/null 2>&1; fi
  rm -rf "$CHECK_TMP"
}
trap cleanup EXIT

finish() {
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  if [ "$FAIL" -gt 0 ]; then
    [ -n "$GW_LOG" ] && [ -f "$GW_LOG" ] && cp "$GW_LOG" "$REPO/.last-gateway.log" && \
      say "The last gateway log is in .last-gateway.log"
    exit 1
  fi
  exit 0
}

check_header() {    # chapter title
  need agentgateway python3 curl
  local v
  v="$(agentgateway --version 2>/dev/null | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')"
  say "Chapter $1 checks (agentgateway ${v:-unknown})"
  if [ -n "$v" ] && [ "$v" != "1.7.0" ]; then
    say "Note: this book was tested with agentgateway 1.7.0. Some checks may differ on $v."
  fi
}
