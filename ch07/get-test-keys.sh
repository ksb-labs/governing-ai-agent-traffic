#!/usr/bin/env bash
# Download the agentgateway project's public test key and a token signed with
# it (section 7.3) into this folder. The token says it was issued by
# agentgateway.dev for test.agentgateway.dev, with subject test-user.
# These keys are public: never use them anywhere but your own machine.
set -euo pipefail
cd "$(dirname "$0")"
URL=https://raw.githubusercontent.com/agentgateway/agentgateway/v1.7.0/manifests/jwt
curl -sfLO "$URL/pub-key"
curl -sfL "$URL/example1.key" -o test-token.jwt
echo "saved ch07/pub-key and ch07/test-token.jwt"
