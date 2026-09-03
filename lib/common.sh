#!/bin/bash
# Shared helpers for correctness checks.
# Source this at the top of every check:  . "$(dirname "$0")/../lib/common.sh"

# --- Configuration -----------------------------------------------------------
# CONFIG_FILE holds KUMA_BASE plus one push token per check. Override the path
# so tests can point at a stub instead of the real monitoring instance.
CONFIG_FILE="${CC_CONFIG:-$(dirname "${BASH_SOURCE[0]}")/../config.env}"

cc_init() {                       # cc_init <TOKEN_VARIABLE_NAME>
  local token_var="$1"
  [ -r "$CONFIG_FILE" ] || { echo "$(date '+%F %T') config not readable: $CONFIG_FILE" >&2; exit 1; }
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
  CC_TOKEN="${!token_var:-}"
  [ -n "${KUMA_BASE:-}" ] || { echo "$(date '+%F %T') KUMA_BASE not set in $CONFIG_FILE" >&2; exit 1; }
  [ -n "$CC_TOKEN" ]      || { echo "$(date '+%F %T') $token_var not set in $CONFIG_FILE" >&2; exit 1; }
}

cc_push() {                       # cc_push <up|down> <message>
  curl -sS -m 10 -G "$KUMA_BASE/$CC_TOKEN" \
    --data-urlencode "status=$1" --data-urlencode "msg=$2" >/dev/null
}

cc_ok()   { cc_push up   "$1"; echo "$(date '+%F %T') OK: $1"; exit 0; }

# Every failure path ends here — including "I could not perform the check".
# Treating "unable to verify" as success is the exact bug this project exists
# to prevent.
cc_fail() { cc_push down "$1"; echo "$(date '+%F %T') FAIL: $1" >&2; exit 1; }

# Run a command with a timeout and fail loudly if it does not return cleanly.
# Never let a hanging container silently stall a cron run.
cc_run() {                        # cc_run <seconds> <command...>
  local secs="$1"; shift
  timeout "$secs" "$@"
}
