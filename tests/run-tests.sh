#!/bin/bash
# Test suite. Never touches a real monitoring instance: every push goes to
# tests/kuma-stub.py.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d /tmp/cc-tests.XXXXXX)
PORT=18099
PUSHES="$T/pushes.log"
PASS=0; FAIL=0; FAILED=()

cleanup() { [ -n "${STUB:-}" ] && kill "$STUB" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

check() {  # check <name> <expected-exit> <actual-exit>
  if [ "$2" = "$3" ]; then printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1))
  else printf '  \033[31m✗\033[0m %s (exit %s, expected %s)\n' "$1" "$3" "$2"
       FAIL=$((FAIL+1)); FAILED+=("$1"); fi
}
last_msg() { tail -1 "$PUSHES" 2>/dev/null | python3 -c \
  "import json,sys;d=sys.stdin.read().strip();print(json.loads(d)['msg'] if d else '')"; }

python3 "$ROOT/tests/kuma-stub.py" "$PORT" "$PUSHES" & STUB=$!
sleep 1
cat > "$T/config.env" <<CFG
KUMA_BASE=http://127.0.0.1:$PORT/api/push
CC_TOKEN_BACKUP=T
CC_TOKEN_SMART=T
CC_TOKEN_HTTP=T
CFG
export CC_CONFIG="$T/config.env"

printf '\n\033[1mcorrectness-checks test suite\033[0m\n\n'

# --- backup-archive ----------------------------------------------------------
printf '\033[1mbackup-archive.sh\033[0m\n'
mkdir -p "$T/bk" "$T/src/data"
echo db > "$T/src/data/db.sqlite3"
tar -czf "$T/bk/full.tar.gz" -C "$T/src" data
export BACKUP_DIR="$T/bk" BACKUP_MARKER="data/db.sqlite3" BACKUP_MAX_AGE_H=26
"$ROOT/checks/backup-archive.sh" >/dev/null 2>&1; check "complete archive passes" 0 $?

mkdir -p "$T/empty/data"; tar -czf "$T/bk/full.tar.gz" -C "$T/empty" data
"$ROOT/checks/backup-archive.sh" >/dev/null 2>&1; check "valid archive WITHOUT marker fails" 1 $?
[[ "$(last_msg)" == *INCOMPLETE* ]] && { printf '  \033[32m✓\033[0m message names the problem\n'; PASS=$((PASS+1)); } \
  || { printf '  \033[31m✗\033[0m message unclear\n'; FAIL=$((FAIL+1)); FAILED+=("backup message"); }

tar -czf "$T/bk/full.tar.gz" -C "$T/src" data
touch -d '30 hours ago' "$T/bk/full.tar.gz"
"$ROOT/checks/backup-archive.sh" >/dev/null 2>&1; check "stale archive fails" 1 $?
rm -f "$T/bk"/*.tar.gz
"$ROOT/checks/backup-archive.sh" >/dev/null 2>&1; check "no archive at all fails" 1 $?
unset BACKUP_DIR BACKUP_MARKER BACKUP_MAX_AGE_H

# --- disk-smart --------------------------------------------------------------
printf '\n\033[1mdisk-smart.sh\033[0m\n'
cat > "$T/smart-ok.txt" <<S
critical_warning			: 0
available_spare				: 100%
available_spare_threshold		: 10%
percentage_used				: 0%
media_errors				: 0
S
export SMART_SOURCE="$T/smart-ok.txt"
"$ROOT/checks/disk-smart.sh" >/dev/null 2>&1; check "healthy disk passes" 0 $?
sed 's/^media_errors.*/media_errors				: 3/' "$T/smart-ok.txt" > "$T/s2"; SMART_SOURCE="$T/s2" \
  "$ROOT/checks/disk-smart.sh" >/dev/null 2>&1; check "media errors fail" 1 $?
sed 's/^percentage_used.*/percentage_used				: 85%/' "$T/smart-ok.txt" > "$T/s3"; SMART_SOURCE="$T/s3" \
  "$ROOT/checks/disk-smart.sh" >/dev/null 2>&1; check "wear over limit fails" 1 $?
sed 's/^available_spare\t.*/available_spare				: 5%/' "$T/smart-ok.txt" > "$T/s4"; SMART_SOURCE="$T/s4" \
  "$ROOT/checks/disk-smart.sh" >/dev/null 2>&1; check "spare under threshold fails" 1 $?
grep -v percentage_used "$T/smart-ok.txt" > "$T/s5"; SMART_SOURCE="$T/s5" \
  "$ROOT/checks/disk-smart.sh" >/dev/null 2>&1; check "missing field fails (not silently OK)" 1 $?
: > "$T/s6"; SMART_SOURCE="$T/s6" \
  "$ROOT/checks/disk-smart.sh" >/dev/null 2>&1; check "empty output fails" 1 $?
unset SMART_SOURCE

# --- json-field helper -------------------------------------------------------
printf '\n\033[1mlib/json-field.py\033[0m\n'
v=$(echo '{"data":{"count":42}}' | python3 "$ROOT/lib/json-field.py" data.count 2>/dev/null)
check "reads a nested field" 0 $?
[ "$v" = "42" ] && { printf '  \033[32m✓\033[0m returns the right value\n'; PASS=$((PASS+1)); } \
  || { printf '  \033[31m✗\033[0m wrong value: %s\n' "$v"; FAIL=$((FAIL+1)); FAILED+=("json value"); }
echo '{"data":{}}' | python3 "$ROOT/lib/json-field.py" data.missing >/dev/null 2>&1
check "missing field errors out" 1 $?

# --- config guard ------------------------------------------------------------
printf '\n\033[1mconfig handling\033[0m\n'
CC_CONFIG=/nonexistent "$ROOT/checks/disk-smart.sh" >/dev/null 2>&1
check "missing config fails loudly" 1 $?

printf '\n\033[1mResult\033[0m\n  \033[32m%s passed\033[0m' "$PASS"
[ "$FAIL" -gt 0 ] && printf ', \033[31m%s failed\033[0m' "$FAIL"
printf '\n'
[ "$FAIL" -gt 0 ] && { printf '\n  Failed:\n'; printf '    - %s\n' "${FAILED[@]}"; exit 1; }
printf '  \033[32mAll good.\033[0m\n'
