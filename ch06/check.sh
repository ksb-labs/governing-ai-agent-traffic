#!/usr/bin/env bash
# Chapter 6 labs: a calling agent follows the card; two agents, one port;
# and the require-a-user Your turn.
. "$(dirname "$0")/../lib/check-lib.sh"
check_header 6
require_free_ports 3000 15000 9998 9999

HELLO=0
step "Starting the A2A Hello World agent (first run clones it and installs its requirements)"
if command -v git >/dev/null && ch06/start-helloworld.sh --background > "$CHECK_TMP/hello.out" 2>&1 \
   && wait_port 9999 20; then
  HELLO=1; BG_PIDS+=("$(cat .cache/helloworld.pid)"); pass "Hello World agent is up on :9999"
else
  skip "couldn't start the Hello World agent; skipping its checks ($(tail -1 "$CHECK_TMP/hello.out"))"
fi
bg python3 company/disputes_agent.py > "$CHECK_TMP/disputes.log" 2>&1
wait_port 9998 10 && pass "disputes agent is up on :9998"

if [ $HELLO -eq 1 ]; then
  step "Listing 6.2 (ch06/config.yaml): the card through the gateway"
  gw_start ch06 config.yaml 3000
  card=$(curl -s http://localhost:3000/.well-known/agent-card.json)
  expect_contains "the card's interface points at the gateway" '"url":"http://localhost:3000/"' "$card"
  expect_contains "its one skill is Echo Bot" "Echo Bot" "$card"
  out=$(python3 tools/a2a_client.py send http://localhost:3000 hi 2>&1)
  printf '%s\n' "$out" | sed 's/^/    /'
  expect_contains "the client follows the card to the gateway" "card says: send messages to http://localhost:3000/" "$out"
  expect_contains "task state" "task state: TASK_STATE_COMPLETED" "$out"
  expect_contains "the agent answers" "agent: Hello, World! I have received your request (hi)" "$out"
  wait_log "a2a.method=SendMessage" 5
  expect_match "the gateway log has the A2A details" \
    "protocol=a2a a2a.method=SendMessage a2a.response.outcome=success a2a.result.kind=task a2a.task.state=TASK_STATE_COMPLETED" "$(cat "$GW_LOG")"
  out=$(python3 tools/a2a_client.py send http://localhost:9999 hi 2>&1 | head -1)
  expect_eq "the agent's own card points around the gateway" "card says: send messages to http://127.0.0.1:9999" "$out"
  gw_stop
fi

step "ch06/two-agents.yaml: two agents on one port"
gw_start ch06 two-agents.yaml 3000
out=$(python3 tools/a2a_client.py send http://localhost:3000/disputes "dispute the 12 dollar fee" 2>&1)
printf '%s\n' "$out" | sed 's/^/    /'
expect_contains "the card includes the prefix" "card says: send messages to http://localhost:3000/disputes" "$out"
expect_contains "no user: the confused deputy" \
  "No end user was passed, so I acted with my own permissions, which cover every customer." "$out"
out=$(python3 tools/a2a_client.py send http://localhost:3000/disputes "dispute the 12 dollar fee" \
  --header "x-end-user: C123" 2>&1)
expect_match "with x-end-user, a case for that customer" "Opened case DSP-[0-9]+ for customer C123." "$out"
if [ $HELLO -eq 1 ]; then
  out=$(python3 tools/a2a_client.py send http://localhost:3000/hello hi 2>&1)
  expect_contains "the Hello World agent still answers on /hello" "Hello, World!" "$out"
fi
gw_stop

step "Your turn: solutions/ch06-require-user.yaml"
gw_start solutions ch06-require-user.yaml 3000
expect_eq "reading the card still works without the header" "200" \
  "$(code http://localhost:3000/disputes/.well-known/agent-card.json)"
before=$(grep -c SendMessage "$CHECK_TMP/disputes.log")
out=$(python3 tools/a2a_client.py send http://localhost:3000/disputes "dispute the 12 dollar fee" 2>&1)
expect_contains "a message with no user gets 403" "error: HTTP 403: authorization failed" "$out"
after=$(grep -c SendMessage "$CHECK_TMP/disputes.log")
expect_eq "and the disputes agent never saw it" "$before" "$after"
out=$(python3 tools/a2a_client.py send http://localhost:3000/disputes "dispute the 12 dollar fee" \
  --header "x-end-user: C123" 2>&1)
expect_contains "a message that names a user goes through" "for customer C123" "$out"
finish
