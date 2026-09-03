#!/bin/bash
# TEMPLATE — copy this to start a new correctness check.
#
# The rule that makes a check worth having:
#   Do not ask "does it respond?" — ask "does it still do its job?"
#
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"
cc_init CC_TOKEN_TEMPLATE          # name of the token variable in config.env

# 1. Do the real thing the service exists for.
# 2. Verify the RESULT, not the response code.
# 3. Any path where you cannot verify must call cc_fail — never fall through.

RESULT=$(cc_run 20 some-command --that-actually-works) \
  || cc_fail "command failed or timed out"

[ -n "$RESULT" ] || cc_fail "empty result — cannot verify, treating as failure"

grep -q "expected marker" <<< "$RESULT" \
  || cc_fail "result present but wrong: missing 'expected marker'"

cc_ok "did the real work, result verified"
