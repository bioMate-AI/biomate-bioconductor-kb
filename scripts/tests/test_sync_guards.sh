#!/usr/bin/env bash
# Unit-style checks for scripts/lib/sync_guards.sh (no AWS / no DEV).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/sync_guards.sh
source "$ROOT/scripts/lib/sync_guards.sh"

pass=0
fail=0
assert_eq() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name (got=$(printf %q "$got") want=$(printf %q "$want"))" >&2
    fail=$((fail + 1))
  fi
}
assert_ok() {
  local name="$1"; shift
  if "$@"; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name (expected success)" >&2
    fail=$((fail + 1))
  fi
}
assert_fail() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: $name (expected failure)" >&2
    fail=$((fail + 1))
  else
    echo "PASS: $name"
    pass=$((pass + 1))
  fi
}

# --- proxy loopback detection ---
assert_ok "proxy 127.0.0.1:port" biomate_proxy_is_loopback "http://127.0.0.1:8080"
assert_ok "proxy localhost" biomate_proxy_is_loopback "https://localhost:1234"
assert_fail "proxy public" biomate_proxy_is_loopback "https://proxy.example.com:443"
assert_fail "proxy empty" biomate_proxy_is_loopback ""

# --- auto-unset (must run in-process; $(...) would only clear a subshell) ---
export HTTP_PROXY="http://127.0.0.1:9"
export HTTPS_PROXY="http://127.0.0.1:9"
export http_proxy="http://127.0.0.1:9"
BIOMATE_STRICT_PROXY=0
_unset_log="$(mktemp)"
biomate_guard_loopback_proxy >"$_unset_log" 2>/dev/null || true
assert_eq "unset reports HTTP_PROXY" "$(grep -c '^UNSET HTTP_PROXY=' "$_unset_log" || true)" "1"
assert_eq "HTTP_PROXY cleared" "${HTTP_PROXY-}" ""
assert_eq "HTTPS_PROXY cleared" "${HTTPS_PROXY-}" ""
rm -f "$_unset_log"

# --- strict mode ---
export HTTP_PROXY="http://127.0.0.1:9"
BIOMATE_STRICT_PROXY=1
set +e
biomate_guard_loopback_proxy >/dev/null 2>&1
rc=$?
set -e
assert_eq "strict proxy exit 2" "$rc" "2"
BIOMATE_STRICT_PROXY=0
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy 2>/dev/null || true

# --- local lock ---
LOCK="$(mktemp /tmp/biomate_test_sync_lock.XXXXXX)"
rm -f "$LOCK"
assert_ok "acquire fresh lock" biomate_acquire_local_sync_lock "$LOCK"
# Simulate another live holder: write our own pid (kill -0 succeeds) then try acquire from a subshell?
# Subshell would see same pid as parent if we echo $$ — use a sleep child instead.
sleep 120 &
holder=$!
echo "$holder" > "$LOCK"
set +e
biomate_acquire_local_sync_lock "$LOCK" >/dev/null 2>&1
rc=$?
set -e
assert_eq "refuse live lock" "$rc" "1"
kill "$holder" 2>/dev/null || true
wait "$holder" 2>/dev/null || true
# Dead pid → reclaim
echo "999999" > "$LOCK"
assert_ok "reclaim dead lock" biomate_acquire_local_sync_lock "$LOCK"
rm -f "$LOCK"

# --- DB decision matrix (no real FTS required for skip_forced / missing) ---
BIOMATE_SYNC_DB=0
assert_eq "skip_forced" "$(biomate_db_upload_decision /nonexistent.db -1)" "skip_forced"
BIOMATE_SYNC_DB=1
assert_eq "refuse_missing" "$(biomate_db_upload_decision /nonexistent.db -1)" "refuse_missing"

# Tiny sqlite with no FTS → refuse_fts (when sqlite3 present)
if command -v sqlite3 >/dev/null 2>&1; then
  tmpdb="$(mktemp /tmp/biomate_test_db.XXXXXX.db)"
  sqlite3 "$tmpdb" "CREATE TABLE workflows (id INTEGER PRIMARY KEY); INSERT INTO workflows DEFAULT VALUES;"
  # No FTS table → integrity check fails
  assert_eq "refuse_fts no fts" "$(biomate_db_upload_decision "$tmpdb" -1)" "refuse_fts"
  # Build a DB that passes FTS but has too few workflows
  sqlite3 "$tmpdb" <<'SQL'
DROP TABLE IF EXISTS workflows;
CREATE TABLE workflows (id INTEGER PRIMARY KEY, name TEXT);
CREATE VIRTUAL TABLE workflows_fts USING fts5(name, content='workflows', content_rowid='id');
INSERT INTO workflows(name) VALUES ('a'),('b'),('c');
INSERT INTO workflows_fts(workflows_fts) VALUES('rebuild');
SQL
  BIOMATE_SYNC_DB_MIN_WORKFLOWS=10
  assert_eq "refuse_count" "$(biomate_db_upload_decision "$tmpdb" -1)" "refuse_count"
  BIOMATE_SYNC_DB_MIN_WORKFLOWS=2
  assert_eq "allow small min" "$(biomate_db_upload_decision "$tmpdb" -1)" "allow"
  assert_eq "refuse_shrink" "$(biomate_db_upload_decision "$tmpdb" 100)" "refuse_shrink"
  BIOMATE_SYNC_DB_ALLOW_SHRINK=1
  assert_eq "allow shrink override" "$(biomate_db_upload_decision "$tmpdb" 100)" "allow"
  unset BIOMATE_SYNC_DB_ALLOW_SHRINK
  BIOMATE_SYNC_DB_MIN_WORKFLOWS=3500
  rm -f "$tmpdb"
else
  echo "SKIP: sqlite3 not installed — FTS/count cases not run"
fi

# --- receipt prints ---
receipt="$(biomate_print_dev_receipt abc123 main 'frontend=true' deadbeef 4223 4167 healthy)"
assert_ok "receipt has commit" grep -q 'commit:     abc123' <<<"$receipt"
assert_ok "receipt has playbook" grep -q '20261113_COMMIT_PR_SYNC_PROCESS' <<<"$receipt"

# --- remote lease message ---
msg="$(biomate_remote_lease_refuse_message 42 1800 'other-lease')"
assert_ok "lease mentions one-writer" grep -q 'One-writer' <<<"$msg"
assert_ok "lease forbids hot-patch" grep -qi 'hot-patch' <<<"$msg"

echo
echo "Results: pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
