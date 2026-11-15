#!/usr/bin/env bash
# Check that your machine has what the labs need.
#   required for every chapter: agentgateway 1.7.0, Python 3.10+, Node.js 20+ (npx), curl
#   optional: Git (Ch. 6), Docker (Ch. 11), kubectl + helm + kind (Ch. 13), openssl
set -uo pipefail
ok=0; bad=0
yes()  { printf '  [ok]      %s\n' "$1"; ok=$((ok + 1)); }
no()   { printf '  [missing] %s\n' "$1"; bad=$((bad + 1)); }
opt()  { printf '  [--]      %s\n' "$1"; }
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

echo "Required"
if command -v agentgateway >/dev/null; then
  v=$(agentgateway --version 2>/dev/null | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')
  if [ "$v" = "1.7.0" ]; then yes "agentgateway $v"
  else yes "agentgateway ${v:-?} (the book is tested with 1.7.0; see Chapter 2 to pin it)"; fi
else
  no "agentgateway. Install it (Chapter 2): curl -sL https://agentgateway.dev/install | bash -s -- --version v1.7.0"
fi
if command -v python3 >/dev/null; then
  v=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
  if ver_ge "$v" 3.10; then yes "Python $v"; else no "Python 3.10 or newer (found $v)"; fi
else no "Python 3.10 or newer"; fi
if command -v node >/dev/null; then
  v=$(node --version | tr -d v)
  if ver_ge "$v" 20.0.0; then yes "Node.js $v"; else no "Node.js 20 or newer (found $v)"; fi
else no "Node.js 20 or newer"; fi
command -v npx >/dev/null && yes "npx" || no "npx (comes with Node.js)"
command -v curl >/dev/null && yes "curl" || no "curl"

echo "Optional"
command -v git >/dev/null && yes "git (Chapter 6)" || opt "git, for the A2A sample agent in Chapter 6"
command -v openssl >/dev/null && yes "openssl" || opt "openssl, for SESSION_KEY and the keyHash exercise (any hex generator works)"
if command -v docker >/dev/null; then
  if docker info >/dev/null 2>&1; then yes "docker (Chapter 11)"; else opt "docker is installed but not running (Chapter 11)"; fi
else opt "docker, for Jaeger and Prometheus in Chapter 11"; fi
for c in kubectl helm kind; do
  command -v $c >/dev/null && yes "$c (Chapter 13)" || opt "$c, for Chapter 13"
done

echo "Ports the labs use"
busy=""
for p in 3000 4000 8081 8082 8083 8090 9998 9999 15000 15020 15021; do
  (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null && busy="$busy $p"
done
if [ -z "$busy" ]; then yes "all free"; else opt "in use right now:$busy (stop whatever is there before a lab)"; fi

if [ "$(uname -s)" = Linux ] && [ ! -s /proc/net/if_inet6 ]; then
  echo
  echo "Note: this machine has no IPv6. Before starting agentgateway, run:"
  echo "  export IPV6_ENABLED=false"
fi
echo
if [ $bad -eq 0 ]; then echo "Ready."; else echo "$bad required item(s) missing."; exit 1; fi
