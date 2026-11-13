#!/usr/bin/env bash
# sync_guards.sh — pure helpers for scripts/sync_to_dev.sh (sourceable + unit-testable).
#
# No AWS/SSM side effects. Callers decide when to exit.
# Incidents driving these guards: 2026-11-13 multi-worktree races, Cursor
# HTTP_PROXY→SSM failure, FTS-broken / wrong-worktree DB uploads, ledger drift
# from ad-hoc hot-patches. See docs/20261113_COMMIT_PR_SYNC_PROCESS.md.

# Minimum workflows for a "full" galaxy_ai_tools.db upload (catalog ~4.2k).
# Stubs / partial checkouts are ~tens–hundreds and must never overwrite DEV.
BIOMATE_SYNC_DB_MIN_WORKFLOWS="${BIOMATE_SYNC_DB_MIN_WORKFLOWS:-3500}"

# ---------------------------------------------------------------------------
# Loopback HTTP(S)_PROXY → breaks AWS CLI / SSM Session Manager (Cursor sandbox).
# Default: unset offending vars and warn. BIOMATE_STRICT_PROXY=1 → hard fail.
# ---------------------------------------------------------------------------
biomate_proxy_is_loopback() {
  local val="${1:-}"
  [[ -z "$val" ]] && return 1
  # Match http(s)://127.0.0.1 | localhost | [::1] with optional port/path
  [[ "$val" =~ ^(https?|HTTP|HTTPS)://(127\.0\.0\.1|localhost|\[::1\])(:|/|$) ]] && return 0
  [[ "$val" =~ ^(127\.0\.0\.1|localhost|\[::1\])(:|$) ]] && return 0
  return 1
}

# Prints lines "UNSET <VAR>=<value>" for each cleared var to stdout.
# Exit 0 always when auto-unsetting; exit 2 when strict and at least one was bad.
biomate_guard_loopback_proxy() {
  local strict="${BIOMATE_STRICT_PROXY:-0}"
  local var val bad=0
  local -a cleared=()
  for var in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy; do
    # bash nameref-safe read of possibly-unset vars under set -u callers
    val="${!var-}"
    if biomate_proxy_is_loopback "$val"; then
      cleared+=("$var=$val")
      unset "$var" 2>/dev/null || true
      bad=1
    fi
  done
  if [[ "$bad" -eq 1 ]]; then
    for val in "${cleared[@]}"; do
      echo "UNSET $val"
    done
    if [[ "$strict" == "1" ]]; then
      echo "STRICT: loopback HTTP(S)_PROXY would break AWS/SSM — refusing (unset proxies or BIOMATE_STRICT_PROXY=0)" >&2
      return 2
    fi
    echo "WARN: cleared loopback HTTP(S)_PROXY so AWS/SSM can reach EC2 (Cursor sandbox CONNECT tunnels break session-manager)" >&2
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Local sync lock — clearer age / owner messaging (per-machine).
# Usage: biomate_acquire_local_sync_lock /tmp/biomate_sync_to_dev.lock
# Exit 1 if another live sync holds the lock.
# ---------------------------------------------------------------------------
biomate_local_lock_age_s() {
  local lock="$1" now mtime
  [[ -e "$lock" ]] || { echo 0; return 0; }
  now=$(date +%s)
  mtime=$(stat -c %Y "$lock" 2>/dev/null || stat -f %m "$lock" 2>/dev/null || echo "$now")
  [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=$now
  echo $(( now - mtime ))
}

biomate_acquire_local_sync_lock() {
  local lock="$1"
  local pid age cmd
  if [[ -e "$lock" ]]; then
    pid="$(cat "$lock" 2>/dev/null || true)"
    age="$(biomate_local_lock_age_s "$lock")"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      cmd="$(ps -p "$pid" -o args= 2>/dev/null | head -c 120 || echo '?')"
      echo "ERROR: another sync_to_dev.sh is already running on this machine." >&2
      echo "  pid=$pid age=${age}s cmd=$cmd" >&2
      echo "  lock=$lock" >&2
      echo "  If you are sure that process is dead/orphan: rm -f $lock" >&2
      echo "  Multi-worktree rule: only ONE writer syncs DEV — coordinate before clearing." >&2
      return 1
    fi
    # Stale lock (pid dead) — reclaim with a note
    echo "WARN: reclaiming stale local sync lock (pid=${pid:-?} dead, age=${age}s): $lock" >&2
    rm -f "$lock"
  fi
  echo $$ > "$lock"
  return 0
}

# ---------------------------------------------------------------------------
# Catalog DB gates (galaxy_ai_tools.db) — refuse bad uploads before S3.
# ---------------------------------------------------------------------------
biomate_db_fts_ok() {
  local db="$1"
  command -v sqlite3 >/dev/null 2>&1 || return 0  # no sqlite3 → skip (caller may still refuse)
  sqlite3 "$db" "INSERT INTO workflows_fts(workflows_fts, rank) VALUES('integrity-check', 1);" >/dev/null 2>&1
}

biomate_db_workflow_count() {
  local db="$1"
  command -v sqlite3 >/dev/null 2>&1 || { echo -1; return 0; }
  sqlite3 "$db" "SELECT COUNT(*) FROM workflows;" 2>/dev/null || echo -1
}

# Decide whether local catalog may be uploaded to DEV.
# Prints one of: skip_forced | refuse_fts | refuse_count | refuse_shrink | allow
# Env:
#   BIOMATE_SYNC_DB=0           → skip_forced (never upload)
#   BIOMATE_SYNC_DB_MIN_WORKFLOWS (default 3500)
#   BIOMATE_SYNC_DB_ALLOW_SHRINK=1 → permit local_count < dev_count
# Args: local_db [dev_workflow_count|-1]
biomate_db_upload_decision() {
  local db="$1"
  local dev_count="${2:--1}"
  local local_count min

  if [[ "${BIOMATE_SYNC_DB:-1}" == "0" ]]; then
    echo "skip_forced"
    return 0
  fi
  if [[ ! -f "$db" ]]; then
    echo "refuse_missing"
    return 0
  fi
  if ! biomate_db_fts_ok "$db"; then
    echo "refuse_fts"
    return 0
  fi
  local_count="$(biomate_db_workflow_count "$db")"
  min="${BIOMATE_SYNC_DB_MIN_WORKFLOWS:-3500}"
  if [[ "$local_count" =~ ^[0-9]+$ ]] && [[ "$local_count" -lt "$min" ]]; then
    echo "refuse_count"
    return 0
  fi
  if [[ "$dev_count" =~ ^[0-9]+$ ]] && [[ "$dev_count" -gt 0 ]] \
     && [[ "$local_count" =~ ^[0-9]+$ ]] && [[ "$local_count" -lt "$dev_count" ]] \
     && [[ "${BIOMATE_SYNC_DB_ALLOW_SHRINK:-0}" != "1" ]]; then
    echo "refuse_shrink"
    return 0
  fi
  echo "allow"
  return 0
}

biomate_db_decision_message() {
  local decision="$1" db="${2:-}" local_count="${3:-?}" dev_count="${4:-?}" min="${BIOMATE_SYNC_DB_MIN_WORKFLOWS:-3500}"
  case "$decision" in
    skip_forced)
      echo "BIOMATE_SYNC_DB=0 — forcing db=false (DEV keeps its catalog)"
      ;;
    refuse_fts)
      echo "workflows_fts integrity-check FAILED on $db — refusing upload. Rebuild: sqlite3 $db \"INSERT INTO workflows_fts(workflows_fts) VALUES('rebuild')\""
      ;;
    refuse_count)
      echo "local workflow count $local_count < min $min — refusing upload (wrong/stub/wrong-worktree DB). Set BIOMATE_SYNC_DB=0 to sync code without DB."
      ;;
    refuse_shrink)
      echo "local workflows ($local_count) < DEV ($dev_count) — refusing shrink. Use the designated catalog worktree, or BIOMATE_SYNC_DB_ALLOW_SHRINK=1 only with an explicit incident reason."
      ;;
    refuse_missing)
      echo "local galaxy_ai_tools.db missing — cannot upload"
      ;;
    allow)
      echo "DB upload allowed (local_count=$local_count dev_count=$dev_count)"
      ;;
    *)
      echo "unknown DB decision: $decision"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Remote lease messaging (caller still does mkdir/ssh).
# ---------------------------------------------------------------------------
biomate_remote_lease_refuse_message() {
  local age="${1:-unknown}" stale_s="${2:-1800}" owner="${3:-}"
  cat <<EOF
ERROR: another deployment holds /opt/biomate/.dev-deploy.lock (age=${age}s; stale-break only after ${stale_s}s).
  One-writer rule: panelfix / nextphase / review / coldstart must NOT sync DEV in parallel.
  Owner file: ${owner:-unknown}
  Wait for the other sync to finish, or if it is truly orphaned AND age > ${stale_s}s the next sync will break the lease.
  Do NOT clear the lock while a live sync is running — that causes ledger tip ≠ actual code.
  Do NOT S3/docker hot-patch around the lock — that leaves the deploy ledger lying.
EOF
}

# ---------------------------------------------------------------------------
# One-screen DEV receipt (caller supplies already-fetched values).
# ---------------------------------------------------------------------------
biomate_print_dev_receipt() {
  local commit="${1:-?}" branch="${2:-?}" layers="${3:-?}"
  local db_md5="${4:-?}" wf_count="${5:-?}" ik_count="${6:-?}" result="${7:-?}"
  cat <<EOF

========== DEV RECEIPT ==========
commit:     ${commit}
branch:     ${branch}
result:     ${result}
layers:     ${layers}
db md5:     ${db_md5}
workflows:  ${wf_count}
input_kinds non-null: ${ik_count}
verify:     curl -fsS https://dev-public.biomate.ai/build-info.json
ledger:     must match this commit after a healthy sync (no hot-patch)
playbook:   docs/20261113_COMMIT_PR_SYNC_PROCESS.md
=================================

EOF
}
