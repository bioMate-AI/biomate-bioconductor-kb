#!/usr/bin/env bash
# sweep_drug_dev_workflows.sh — fire all drug-dev-relevant workflows on dev,
# capture per-workflow outcome (terminal status, duration, error class).
#
# Usage:
#   bash scripts/sweep_drug_dev_workflows.sh            # all 209
#   bash scripts/sweep_drug_dev_workflows.sh --batch 10  # 10 only (smoke)
#   bash scripts/sweep_drug_dev_workflows.sh --domain pharmacology

set -uo pipefail

BASE="${BASE:-https://dev-public.biomate.ai}"
TOK="x-e2e-test-token: biomate-e2e-bypass-token-dev-only"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOMAINS=(drug_discovery pharmacology molecular_biology genetics biochemistry structural_biology biophysics virtual_cell physiology cell_biology multi_omics immunology synthetic_biology systems_biology)
PARALLELISM=10
POLL_INTERVAL=20
POLL_TIMEOUT=900   # 15 min per workflow

BATCH_LIMIT=""
ONLY_DOMAIN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --batch)  BATCH_LIMIT="$2"; shift 2;;
    --domain) ONLY_DOMAIN="$2"; shift 2;;
    *) echo "unknown arg: $1"; exit 1;;
  esac
done

RESULTS="/tmp/drug-dev-sweep-$(date +%Y%m%d-%H%M%S).csv"
echo "domain,workflow,runId,status,nfs_status,duration_s,error_class,error_snippet" > "$RESULTS"
echo "[$(date +%H:%M:%S)] results → $RESULTS"

# Collect workflow paths
declare -a WORKFLOWS
for d in "${DOMAINS[@]}"; do
  [[ -n "$ONLY_DOMAIN" && "$d" != "$ONLY_DOMAIN" ]] && continue
  while IFS= read -r path; do
    rel="${path#$REPO_ROOT/backend/biomni_workflows/}"
    WORKFLOWS+=("$rel")
  done < <(find "$REPO_ROOT/backend/biomni_workflows/nextflow_nfcore/subworkflows/$d" -name "main.nf" 2>/dev/null)
done
[[ -n "$BATCH_LIMIT" ]] && WORKFLOWS=("${WORKFLOWS[@]:0:$BATCH_LIMIT}")

echo "[$(date +%H:%M:%S)] total workflows to fire: ${#WORKFLOWS[@]}"

classify_error() {
  local tail="$1"
  if echo "$tail" | grep -q "No such property: meta"; then echo "meta-finalize"
  elif echo "$tail" | grep -q "Statements cannot be mixed with script declarations"; then echo "strict-parser-statements"
  elif echo "$tail" | grep -q "Script compilation"; then echo "script-compile"
  elif echo "$tail" | grep -q "_ARRAY_API"; then echo "numpy-abi"
  elif echo "$tail" | grep -q "ModuleNotFoundError\|ImportError"; then echo "missing-import"
  elif echo "$tail" | grep -q "SIGSEGV\|SIGABRT\|hs_err_pid"; then echo "jvm-crash"
  elif echo "$tail" | grep -q "Unknown configuration profile"; then echo "profile-name"
  elif echo "$tail" | grep -q "Unrecognized config option"; then echo "config-unknown"
  elif echo "$tail" | grep -q "ERROR"; then echo "other-error"
  else echo "(no-error)"
  fi
}

fire_one() {
  local rel="$1"
  local name
  name=$(basename "$(dirname "$rel")")
  local domain
  domain=$(echo "$rel" | awk -F/ '{print $(NF-2)}')

  local rid
  rid=$(curl -s -m 60 "$BASE/api/workflows/execute" \
        -H "Content-Type: application/json" -H "$TOK" \
        -d "{\"workflowDefinition\":{\"name\":\"sweep-$name\",\"workflow_type\":\"nextflow\",\"nextflow_path\":\"$rel\",\"parameters\":{}}}" \
        | python3 -c "import sys,json
try: d=json.load(sys.stdin); print(d.get('runId') or '')
except: print('')" 2>/dev/null)
  if [[ -z "$rid" ]]; then
    echo "$domain,$name,,EXEC_ERR,,0,fire-failed,/api/workflows/execute returned no runId" >> "$RESULTS"
    return
  fi
  printf "[%s] fired %-35s %s\n" "$(date +%H:%M:%S)" "$name" "$rid"

  local start
  start=$(date +%s)
  while true; do
    local now elapsed
    now=$(date +%s)
    elapsed=$((now - start))
    if [[ $elapsed -gt $POLL_TIMEOUT ]]; then
      echo "$domain,$name,$rid,TIMEOUT,running,$elapsed,poll-timeout," >> "$RESULTS"
      return
    fi
    local snap
    snap=$(curl -s -m 20 "$BASE/api/workflows/runs/$rid" -H "$TOK" 2>/dev/null)
    [[ -z "$snap" ]] && { sleep "$POLL_INTERVAL"; continue; }
    local status nf_status dur
    status=$(echo "$snap" | python3 -c "import sys,json
try: print((json.load(sys.stdin).get('execution') or {}).get('status',''))
except: print('')" 2>/dev/null)
    nf_status=$(echo "$snap" | python3 -c "import sys,json
try: print(((json.load(sys.stdin).get('execution') or {}).get('nextflowStatus') or {}).get('status',''))
except: print('')" 2>/dev/null)
    dur=$(echo "$snap" | python3 -c "import sys,json
try: print(((json.load(sys.stdin).get('execution') or {}).get('nextflowStatus') or {}).get('duration_s',''))
except: print('')" 2>/dev/null)
    if [[ "$status" == "completed" || "$status" == "failed" || "$nf_status" == "interrupted" || "$status" == "cancelled" ]]; then
      local err_tail
      err_tail=$(echo "$snap" | python3 -c "import sys,json
try:
  nfs=(json.load(sys.stdin).get('execution') or {}).get('nextflowStatus') or {}
  print('\\n'.join((nfs.get('log_tail') or [])[-10:]))
except: pass" 2>/dev/null)
      local err_class
      err_class=$(classify_error "$err_tail")
      local snippet
      snippet=$(echo "$err_tail" | grep -E "ERROR|Module|numpy|SIGSEGV|Statements" | head -1 | tr ',\n' ';;' | cut -c-200)
      echo "$domain,$name,$rid,$status,$nf_status,$dur,$err_class,\"$snippet\"" >> "$RESULTS"
      printf "[%s] done  %-35s %s %s\n" "$(date +%H:%M:%S)" "$name" "$status/$nf_status" "$err_class"
      return
    fi
    sleep "$POLL_INTERVAL"
  done
}

pids=()
for rel in "${WORKFLOWS[@]}"; do
  fire_one "$rel" &
  pids+=($!)
  if [[ ${#pids[@]} -ge $PARALLELISM ]]; then
    wait "${pids[@]}"
    pids=()
  fi
done
wait "${pids[@]}"

echo ""
echo "=== summary ==="
python3 - <<EOF
import csv, collections
rows = list(csv.DictReader(open('$RESULTS')))
print(f"total fired: {len(rows)}")
print(f"by terminal status:")
for k, v in collections.Counter(r['status'] for r in rows).most_common():
    print(f"  {k:<10} {v}")
print(f"by error class:")
for k, v in collections.Counter(r['error_class'] for r in rows).most_common():
    print(f"  {k:<30} {v}")
EOF
echo ""
echo "Full CSV at $RESULTS"
