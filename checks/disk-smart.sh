#!/bin/bash
# Reads NVMe SMART data and fails on the indicators that precede a real failure.
#
# Why: SSDs die with warning. percentage_used and media_errors rise before
# anything breaks. If nothing reads them, that warning is wasted — and on a
# single-disk machine it is the only warning you get.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"
cc_init CC_TOKEN_SMART

DEVICE="${SMART_DEVICE:-/dev/nvme0n1}"
WEAR_LIMIT="${SMART_WEAR_LIMIT:-80}"
# SMART_SOURCE lets tests feed a captured smart-log instead of real hardware.
if [ -n "${SMART_SOURCE:-}" ]; then
  SMART=$(cat "$SMART_SOURCE") || cc_fail "test source unreadable"
else
  SMART=$(cc_run 20 sudo -n nvme smart-log "$DEVICE" 2>/dev/null) \
    || cc_fail "cannot read SMART data (nvme-cli missing, sudo rule gone, or disk dead)"
fi
[ -n "$SMART" ] || cc_fail "SMART output empty"

field() { grep -m1 "^$1" <<< "$SMART" | grep -oE '[0-9]+' | head -1; }

WARN=$(field critical_warning); ERRS=$(field media_errors)
WEAR=$(field percentage_used);  SPARE=$(field available_spare)
SPARE_MIN=$(field available_spare_threshold)

# A missing field means the output format changed — that is a failure, not a
# pass. Silently skipping unparseable data is how checks start lying.
for pair in "critical_warning:$WARN" "media_errors:$ERRS" \
            "percentage_used:$WEAR" "available_spare:$SPARE"; do
  [[ "${pair#*:}" =~ ^[0-9]+$ ]] || cc_fail "SMART field '${pair%%:*}' missing — output format changed?"
done

PROBLEMS=()
[ "$WARN" -ne 0 ]      && PROBLEMS+=("critical_warning=$WARN")
[ "$ERRS" -gt 0 ]      && PROBLEMS+=("$ERRS media errors — data integrity at risk")
[ "$WEAR" -ge "$WEAR_LIMIT" ] && PROBLEMS+=("wear ${WEAR}% — plan replacement")
if [[ "${SPARE_MIN:-}" =~ ^[0-9]+$ ]] && [ "$SPARE" -lt "$SPARE_MIN" ]; then
  PROBLEMS+=("spare blocks ${SPARE}% below threshold ${SPARE_MIN}% — failure imminent")
fi
[ ${#PROBLEMS[@]} -gt 0 ] && cc_fail "$(printf '%s; ' "${PROBLEMS[@]}")"

cc_ok "healthy: wear ${WEAR}%, spare ${SPARE}%, 0 media errors"
