#!/bin/bash
# Checks that an HTTP endpoint returns USABLE data, not merely HTTP 200.
#
# Why: health endpoints that hardcode {"ok":true} are common. They stay green
# while the database behind them is unreachable. Assert on a value you would
# actually miss.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"
cc_init CC_TOKEN_HTTP

URL="${HTTP_URL:?set HTTP_URL}"
FIELD="${HTTP_FIELD:?set HTTP_FIELD}"        # dotted path, e.g. data.count
MIN="${HTTP_MIN:-1}"                          # value must be numeric and >= MIN

BODY=$(cc_run 20 curl -sS -m 15 "$URL") || cc_fail "$URL unreachable"
[ -n "$BODY" ] || cc_fail "$URL returned an empty body"

VALUE=$(printf '%s' "$BODY" | python3 "$(dirname "$0")/../lib/json-field.py" "$FIELD" 2>/dev/null) \
  || cc_fail "field '$FIELD' missing from response — API changed?"

[[ "$VALUE" =~ ^[0-9]+$ ]] || cc_fail "field '$FIELD' is not numeric: '$VALUE'"
[ "$VALUE" -ge "$MIN" ] || cc_fail "$FIELD is $VALUE, expected at least $MIN — data loss?"

cc_ok "$FIELD = $VALUE"
