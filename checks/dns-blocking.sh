#!/bin/bash
# Proves the DNS blocker still blocks — and still resolves everything else.
#
# Why: blocklists expire, update jobs fail, a config reload drops them. The
# service keeps answering, so nothing looks wrong; ads simply come back.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"
cc_init CC_TOKEN_BLOCKING

read -r -a RESOLVER <<< "${RESOLVER_CMD:?set RESOLVER_CMD}"
HOST="${RESOLVER_HOST:-127.0.0.1}"
# Domains that MUST be blocked, and one that must NOT be.
IFS=',' read -r -a BLOCKED <<< "${BLOCK_DOMAINS:-doubleclick.net,googleadservices.com}"
CONTROL="${CONTROL_DOMAIN:-example.com}"

hits=0
for d in "${BLOCKED[@]}"; do
  answer=$(cc_run 15 "${RESOLVER[@]}" "@$HOST" "$d" +short 2>/dev/null | head -1) || true
  # A blocked domain returns nothing or 0.0.0.0 depending on the blocking mode.
  if [ -z "$answer" ] || [ "$answer" = "0.0.0.0" ] || [ "$answer" = "::" ]; then
    hits=$((hits+1))
  fi
done
[ "$hits" -eq "${#BLOCKED[@]}" ] \
  || cc_fail "only $hits of ${#BLOCKED[@]} test domains blocked — blocklist degraded or gone"

# Counter-test: over-blocking is a failure too. A resolver that blocks
# everything would pass the test above while breaking the network.
ctrl=$(cc_run 15 "${RESOLVER[@]}" "@$HOST" "$CONTROL" +short 2>/dev/null | head -1) || true
[ -n "$ctrl" ] || cc_fail "control domain $CONTROL does not resolve — over-blocking or resolver broken"

cc_ok "$hits/${#BLOCKED[@]} blocked, $CONTROL still resolves"
