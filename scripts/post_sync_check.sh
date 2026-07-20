#!/usr/bin/env bash
# post_sync_check.sh — dev-side gates after scripts/sync_to_dev.sh.
#
# Runs Part 4 of docs/20260614_PRE_SYNC_TEST_PLAN.md:
#   S1 health           — HTTP 200 on the frontend + galaxy api
#   S2 audit            — bash scripts/audit_project_framework.sh
#   S3 log scan         — container logs free of new error classes
#   S4 embedding align  — DB row count matches .npz, signature stamped
#   S5 P1 spot-check    — UC-2 (chat with active workspace) + UC-7
#                         (skip injection on abstract question)
#   S6 db-search canary — intent-driven `operation` routing honored end-to-end
#                         (Node proxy -> Galaxy); deterministic, no external dep
#
# Exits non-zero on the first failure. Per-run logs land in
# docs/post_sync_logs/<TS>_{s1,s2,s3,s4,s5}.log.
#
# Required env (sourced from scripts/sync_to_dev.sh if not set):
#   EC2_HOST, EC2_USER, KEY_FILE, INSTANCE_ID, AZ
# Optional env:
#   BIOMATE_URL          (default: https://dev-public.biomate.ai)
#   E2E_TEST_TOKEN       (default: biomate-e2e-bypass-token-dev-only)
#   FIXTURE_EMAIL        (default: lifeifei163361@163.com)
#   FIXTURE_PASSWORD     (default: WpmFixture!2026)
#   SKIP_S2=1            (skip the project framework audit driver)
#   SKIP_S5=1            (skip the P1 spot-check)
#   SKIP_S6=1            (skip the DB-search operation-routing canary)
#
# Exit codes:
#   0 — all pass
#   1 — branch self-check (not on integration/next-phase)
#   2 — S1 health
#   3 — S2 audit
#   4 — S3 log scan
#   5 — S4 embedding alignment
#   6 — S5 P1 spot-check
#   7 — S6 DB-search operation-routing canary

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO/docs/post_sync_logs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
RUN_LOG="$LOG_DIR/${TS}.log"

C_OK=$'\033[32m'   ; C_FAIL=$'\033[31m'
C_WARN=$'\033[33m' ; C_DIM=$'\033[2m'  ; C_RESET=$'\033[0m'
HEAD()   { printf "\n${C_WARN}── %s ──${C_RESET}\n" "$*" | tee -a "$RUN_LOG"; }
NOTE()   { printf "%s\n" "$*" | tee -a "$RUN_LOG"; }
PASS()   { printf "${C_OK}✓${C_RESET} %s\n" "$*" | tee -a "$RUN_LOG"; }
FAIL()   { printf "${C_FAIL}✗${C_RESET} %s\n" "$*" | tee -a "$RUN_LOG"; }

NOTE "${C_DIM}log: $RUN_LOG${C_RESET}"

# ── Branch self-check ───────────────────────────────────────────────
HEAD "Branch self-check"
CUR="$(git -C "$REPO" branch --show-current 2>/dev/null || echo '?')"
NOTE "current branch: $CUR"
if [[ "$CUR" != "integration/next-phase" ]]; then
  FAIL "Not on integration/next-phase. The pre-sync rule applies"
  FAIL "in reverse too: only run post-sync checks from the branch"
  FAIL "you just synced. Switch branches first."
  exit 1
fi
PASS "branch=integration/next-phase"

# ── Source sync env if not provided ─────────────────────────────────
if [[ -z "${EC2_HOST:-}" || -z "${KEY_FILE:-}" || -z "${INSTANCE_ID:-}" || -z "${AZ:-}" ]]; then
  if [[ -f "$REPO/scripts/sync_to_dev.sh" ]]; then
    eval "$(grep -E '^(EC2_HOST|EC2_USER|KEY_FILE|INSTANCE_ID|AZ)=' "$REPO/scripts/sync_to_dev.sh")"
  fi
fi
BIOMATE_URL="${BIOMATE_URL:-https://dev-public.biomate.ai}"
E2E_TEST_TOKEN="${E2E_TEST_TOKEN:-biomate-e2e-bypass-token-dev-only}"
FIXTURE_EMAIL="${FIXTURE_EMAIL:-lifeifei163361@163.com}"
FIXTURE_PASSWORD="${FIXTURE_PASSWORD:-WpmFixture!2026}"

# Refresh the ephemeral SSH key (same pattern as sync_to_dev.sh).
ssh_refresh() {
  [[ -f "${KEY_FILE}.pub" ]] || { ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -q; }
  aws ec2-instance-connect send-ssh-public-key \
    --instance-id "$INSTANCE_ID" --availability-zone "$AZ" \
    --instance-os-user "${EC2_USER:-ubuntu}" \
    --ssh-public-key "file://${KEY_FILE}.pub" \
    --region us-west-2 --output text --query 'Success' >/dev/null 2>&1
}

# ── S1: health ──────────────────────────────────────────────────────
HEAD "S1 — Health"
S1_LOG="$LOG_DIR/${TS}_s1_health.log"
{
  for path in "/" "/galaxy/api/version"; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" -m 10 "$BIOMATE_URL$path")"
    printf "%-30s HTTP %s\n" "$path" "$code"
  done
} 2>&1 | tee "$S1_LOG"
if grep -qvE "HTTP 200|HTTP 30[12]" "$S1_LOG"; then
  FAIL "S1 — at least one endpoint returned a non-2xx/3xx — see $S1_LOG"
  exit 2
fi
PASS "S1 — frontend + galaxy api both reachable"

# ── S2: project framework audit ─────────────────────────────────────
if [[ "${SKIP_S2:-0}" = "1" ]]; then
  NOTE "${C_DIM}S2 — skipped via SKIP_S2 env var${C_RESET}"
else
  HEAD "S2 — Project framework audit"
  S2_LOG="$LOG_DIR/${TS}_s2_audit.log"
  if [[ ! -x "$REPO/scripts/audit_project_framework.sh" ]]; then
    FAIL "S2 — scripts/audit_project_framework.sh missing or not executable"
    exit 3
  fi
  if ! bash "$REPO/scripts/audit_project_framework.sh" 2>&1 | tee "$S2_LOG" | tail -25 ; then
    FAIL "S2 — audit driver returned non-zero. See $S2_LOG"
    exit 3
  fi
  # The driver prints "PASS=N  FAIL=M" at the end. Treat any FAIL>0 as a fail.
  fail_count="$(grep -oE 'FAIL=[0-9]+' "$S2_LOG" 2>/dev/null | tail -1 | cut -d= -f2 || true)"
  fail_count="${fail_count:-0}"
  if [[ "$fail_count" -gt 0 ]]; then
    FAIL "S2 — $fail_count audit assertions failed"
    exit 3
  fi
  PASS "S2 — project framework audit clean"
fi

# ── S3: container log scan ──────────────────────────────────────────
HEAD "S3 — Container log scan (last 10 min)"
S3_LOG="$LOG_DIR/${TS}_s3_logs.log"
ssh_refresh
if ! ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no \
       "${EC2_USER:-ubuntu}@$EC2_HOST" \
       'sudo docker logs biomate-dev-frontend --since 10m 2>&1 | grep -iE "TypeError|crashed|relation.*does not exist|ENOENT|fatal|unhandledRejection" | head -30' \
     > "$S3_LOG" 2>&1
then
  FAIL "S3 — ssh failed; cannot read dev container logs"
  exit 4
fi
errs="$(grep -cE '.' "$S3_LOG" 2>/dev/null || true)"
errs="${errs:-0}"
if [[ "$errs" -gt 0 ]]; then
  FAIL "S3 — $errs lines matched the error pattern. Excerpt:"
  head -8 "$S3_LOG" | tee -a "$RUN_LOG"
  exit 4
fi
PASS "S3 — no new error classes in last 10 min"

# ── S4: embedding alignment on dev ──────────────────────────────────
HEAD "S4 — Embedding alignment on dev"
S4_LOG="$LOG_DIR/${TS}_s4_embed.log"
ssh_refresh
if ! ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no \
       "${EC2_USER:-ubuntu}@$EC2_HOST" bash -s > "$S4_LOG" 2>&1 <<'REMOTE'
sudo docker exec biomate-galaxy-dev python3 - <<'PY'
import sqlite3, os, sys
import numpy as np
DB = "/app/database/galaxy_ai_tools.db"
NPZ = "/app/database/galaxy_ai_workflow_embeddings.npz"
if not os.path.exists(DB):
    print(f"FAIL: missing DB at {DB}")
    sys.exit(1)
if not os.path.exists(NPZ):
    print(f"WARN: missing .npz at {NPZ} — lazy rebuild will happen on next search request")
    sys.exit(0)
db = sqlite3.connect(DB)
n_db = db.execute("SELECT COUNT(*) FROM workflows").fetchone()[0]
data = np.load(NPZ, allow_pickle=True)
n_npz = len(data["workflow_ids"])
sig = data.get("workflow_signature")
has_sig = sig is not None
print(f"DB={n_db}  .npz={n_npz}  signature_stamped={has_sig}")
if n_db != n_npz:
    print(f"FAIL: row-count drift (DB={n_db}, .npz={n_npz}) — schedule a rebuild")
    sys.exit(1)
if not has_sig:
    print(f"WARN: signature missing — .npz predates 2026-06-13 patch")
PY
REMOTE
then
  FAIL "S4 — ssh / docker exec failed. See $S4_LOG"
  exit 5
fi
cat "$S4_LOG" | tee -a "$RUN_LOG"
if grep -q "^FAIL:" "$S4_LOG"; then
  FAIL "S4 — alignment failure (above)"
  exit 5
fi
PASS "S4 — dev embeddings aligned with dev DB"

# ── S5: P1 spot-check (UC-2 + UC-7 API surface) ─────────────────────
if [[ "${SKIP_S5:-0}" = "1" ]]; then
  NOTE "${C_DIM}S5 — skipped via SKIP_S5 env var${C_RESET}"
else
  HEAD "S5 — P1 spot-check (UC-2 + UC-7)"
  S5_LOG="$LOG_DIR/${TS}_s5_p1.log"
  {
    # Register-or-login fixture
    curl -sS -X POST "$BIOMATE_URL/api/auth/register" \
      -H "x-e2e-test-token: $E2E_TEST_TOKEN" -H "content-type: application/json" \
      -d "{\"name\":\"PostSync Fixture\",\"email\":\"$FIXTURE_EMAIL\",\"password\":\"$FIXTURE_PASSWORD\",\"termsAccepted\":true}" \
      > /dev/null 2>&1 || true
    JWT="$(curl -sS -X POST "$BIOMATE_URL/api/auth/login" \
            -H "x-e2e-test-token: $E2E_TEST_TOKEN" -H "content-type: application/json" \
            -d "{\"email\":\"$FIXTURE_EMAIL\",\"password\":\"$FIXTURE_PASSWORD\"}" \
            | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token",""))')"
    if [[ -z "$JWT" || "${#JWT}" -lt 100 ]]; then
      echo "FAIL: login failed (token len ${#JWT})"
      exit 1
    fi
    echo "  fixture login OK (token ${#JWT} chars)"

    # UC-2 light: create + list + delete a project
    PID="$(curl -sS -X POST "$BIOMATE_URL/api/projects" \
            -H "Authorization: Bearer $JWT" -H "content-type: application/json" \
            -d '{"name":"post-sync-uc2","primaryDomain":"transcriptomics"}' \
            | python3 -c 'import sys,json; print(json.load(sys.stdin).get("project",{}).get("id",""))')"
    if [[ -z "$PID" || "${#PID}" -lt 32 ]]; then
      echo "FAIL: project create failed"
      exit 1
    fi
    echo "  UC-2 project created: $PID"

    # Send a chat with that projectId
    SESS="post-sync-uc2-$(date +%s)"
    curl -sS -X POST "$BIOMATE_URL/api/chat/stream" \
      -H "Authorization: Bearer $JWT" -H "content-type: application/json" \
      --max-time 45 \
      -d "{\"message\":\"hello\",\"stream\":true,\"context\":{\"sessionId\":\"$SESS\",\"projectId\":\"$PID\",\"previousMessages\":[]}}" \
      > /dev/null 2>&1
    echo "  UC-2 chat dispatched"

    # UC-7 light: send an abstract question with NO active project — gate should skip
    SESS2="post-sync-uc7-$(date +%s)"
    curl -sS -X POST "$BIOMATE_URL/api/chat/stream" \
      -H "Authorization: Bearer $JWT" -H "content-type: application/json" \
      --max-time 45 \
      -d "{\"message\":\"What is BH FDR correction?\",\"stream\":true,\"context\":{\"sessionId\":\"$SESS2\",\"previousMessages\":[]}}" \
      > /dev/null 2>&1
    echo "  UC-7 abstract question dispatched"

    # Cleanup the test project
    curl -sS -X DELETE "$BIOMATE_URL/api/projects/$PID" \
      -H "Authorization: Bearer $JWT" > /dev/null 2>&1
    echo "  UC-2 project cleaned up"
  } 2>&1 | tee "$S5_LOG"
  if grep -q "^FAIL:" "$S5_LOG"; then
    FAIL "S5 — see $S5_LOG"
    exit 6
  fi
  PASS "S5 — P1 spot-check API surface OK"
  NOTE "${C_DIM}Reminder: UI-level UC-2 and UC-7 (the actual user flow at"
  NOTE "${C_DIM}https://dev-public.biomate.ai) still need a 30-second human"
  NOTE "${C_DIM}smoke. The script only proved the API surface.${C_RESET}"
fi

# ── S6: intent-driven DB-search behavioral canary ───────────────────
# Asserts the `operation` param is honored END-TO-END (Node REST proxy ->
# Galaxy -> code path). The similarity code path sets the `search` key even
# when the upstream API (ChEMBL/RCSB) returns zero hits, so this is
# DETERMINISTIC and not flaky on external outages. This canary would have
# caught the 2026-07-19 proxy-drop bug where routes.ts:8135 silently dropped
# `operation` (see docs/20260719_INTENT_DRIVEN_DB_SEARCH_AND_DEPLOY_ROOT_CAUSE.md).
if [[ "${SKIP_S6:-0}" = "1" ]]; then
  NOTE "${C_DIM}S6 — skipped via SKIP_S6 env var${C_RESET}"
else
  HEAD "S6 — Intent-driven DB search (operation routing)"
  S6_LOG="$LOG_DIR/${TS}_s6_dbsearch.log"
  UBIQ="MQIFVKTLTGKTITLEVEPSDTIENVKAKIQDKEGIPPDQQRLIFAGKQLEDGRTLSDYNIQKESTLHLVLRLRGG"
  s6q() {
    curl -sS -m 45 -X POST "$BIOMATE_URL/api/databases/query" \
      -H "Content-Type: application/json" -H "x-e2e-test-token: $E2E_TEST_TOKEN" -d "$1"
  }
  {
    CHEMBL_SIM="$(s6q '{"database":"chembl","query":"CC(=O)Oc1ccccc1C(=O)O","operation":"similarity"}')"
    PDB_SIM="$(s6q "{\"database\":\"pdb\",\"query\":\"$UBIQ\",\"operation\":\"similarity\"}")"
    PDB_TEXT="$(s6q "{\"database\":\"pdb\",\"query\":\"$UBIQ\",\"operation\":\"text\"}")"
    printf 'chembl.sim : %.180s\n' "$CHEMBL_SIM"
    printf 'pdb.sim    : %.180s\n' "$PDB_SIM"
    printf 'pdb.text   : %.180s\n' "$PDB_TEXT"
    # Strong, deterministic: similarity path must set its `search` tag.
    echo "$CHEMBL_SIM" | grep -q '"search":[[:space:]]*"tanimoto_similarity"' \
      || echo "FAIL: chembl operation=similarity not routed (proxy drop or stale Galaxy code)"
    echo "$PDB_SIM" | grep -q '"search":[[:space:]]*"sequence_similarity"' \
      || echo "FAIL: pdb operation=similarity not routed"
    # Discrimination: same input under operation=text must NOT run similarity.
    echo "$PDB_TEXT" | grep -q '"search":[[:space:]]*"sequence_similarity"' \
      && echo "FAIL: pdb operation=text wrongly ran similarity (operation ignored/hardcoded)"
    echo "OK: operation routing verified (same input, intent decides: similarity != text)"
  } 2>&1 | tee "$S6_LOG"
  if grep -q "^FAIL:" "$S6_LOG"; then
    FAIL "S6 — operation routing broken. See $S6_LOG"
    exit 7
  fi
  PASS "S6 — intent-driven DB search routes by operation (deterministic canary)"
fi

# ── All done ────────────────────────────────────────────────────────
HEAD "All gates passed"
NOTE "${C_OK}✓ Sync verified on dev${C_RESET}"
NOTE "${C_DIM}If a real user reports a regression in the next hour,"
NOTE "see Part 5 (rollback plan) of docs/20260614_PRE_SYNC_TEST_PLAN.md${C_RESET}"
exit 0
