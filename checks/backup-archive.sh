#!/bin/bash
# Verifies that the newest backup archive is RECENT and actually CONTAINS the
# file that makes it worth having.
#
# Why: a backup script can abort halfway through and still leave a perfectly
# valid, fully extractable .tar.gz — just without the database in it. `tar -tzf`
# returns 0 either way. We shipped empty Vaultwarden backups for nine days
# before anyone noticed, because every check only asked "is the archive
# readable?".
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"
cc_init CC_TOKEN_BACKUP

DIR="${BACKUP_DIR:?set BACKUP_DIR}"          # where archives live
MARKER="${BACKUP_MARKER:?set BACKUP_MARKER}" # path that must exist inside
MAX_AGE_H="${BACKUP_MAX_AGE_H:-26}"

NEWEST=$(ls -1t "$DIR"/*.tar.gz 2>/dev/null | head -1)
[ -n "$NEWEST" ] || cc_fail "no archive at all in $DIR"

AGE_H=$(( ( $(date +%s) - $(stat -c %Y "$NEWEST") ) / 3600 ))
[ "$AGE_H" -lt "$MAX_AGE_H" ] \
  || cc_fail "newest archive is ${AGE_H}h old (limit ${MAX_AGE_H}h): $(basename "$NEWEST")"

# Read the listing into a variable first.
# Do NOT write `tar -tzf … | grep -q …` here: under `set -o pipefail` grep
# closes after its first match, tar gets SIGPIPE, and the pipeline reports 141
# even though the match was found. That false failure cost us an evening.
LISTING=$(cc_run 120 tar -tzf "$NEWEST") \
  || cc_fail "archive is corrupt, tar cannot read it: $(basename "$NEWEST")"

[[ "$LISTING" == *"$MARKER"* ]] \
  || cc_fail "archive valid but INCOMPLETE — '$MARKER' missing from $(basename "$NEWEST")"

cc_ok "$(basename "$NEWEST"), ${AGE_H}h old, contains $MARKER"
