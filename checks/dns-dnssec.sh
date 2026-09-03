#!/bin/bash
# Proves the resolver still VALIDATES DNSSEC — in both directions.
#
# Why: a resolver that answers is not the same as a resolver that validates.
# If validation silently breaks, every lookup still succeeds and every uptime
# check stays green, while the protection you configured is simply gone.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"
cc_init CC_TOKEN_DNSSEC

# How to reach the resolver. Adapt RESOLVER_CMD to your setup, e.g.
#   RESOLVER_CMD="docker exec unbound drill"   or   RESOLVER_CMD="drill"
read -r -a RESOLVER <<< "${RESOLVER_CMD:?set RESOLVER_CMD}"
PORT="${RESOLVER_PORT:-53}"
HOST="${RESOLVER_HOST:-127.0.0.1}"
GOOD_DOMAIN="${DNSSEC_GOOD:-cloudflare.com}"      # correctly signed
BAD_DOMAIN="${DNSSEC_BAD:-dnssec-failed.org}"     # deliberately broken signature

# Note: `drill -D` requests DNSSEC. With dig the flag is `+dnssec` — mixing the
# two syntaxes silently produces an unvalidated answer that still looks fine.
GOOD=$(cc_run 20 "${RESOLVER[@]}" -D -p "$PORT" "$GOOD_DOMAIN" "@$HOST" 2>&1) \
  || cc_fail "resolver did not answer for $GOOD_DOMAIN"

# The 'ad' flag means the answer was authenticated. Without it, validation is off.
grep -qE '^;; flags:.* ad ' <<< "$GOOD" \
  || cc_fail "$GOOD_DOMAIN resolved but NOT validated (no 'ad' flag) — DNSSEC is off"

# The counter-test matters just as much: a resolver that accepts a knowingly
# broken signature is not validating, it is only pretending to.
BAD=$(cc_run 20 "${RESOLVER[@]}" -D -p "$PORT" "$BAD_DOMAIN" "@$HOST" 2>&1) || true
grep -q "SERVFAIL" <<< "$BAD" \
  || cc_fail "$BAD_DOMAIN was NOT rejected — broken signatures are being accepted"

cc_ok "valid signature authenticated, broken signature rejected"
