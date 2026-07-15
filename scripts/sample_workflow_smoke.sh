#!/usr/bin/env bash
# sample_workflow_smoke.sh — post-deploy REAL sample-workflow execution smoke.
#
# Runs a small set of SELF-CONTAINED workflows end-to-end against a deployed
# BioMate: generate -> execute -> poll to completion -> verify outputs. This
# proves the execution engine (the AWS Batch path) actually works after a
# deploy — not just that routing/generation respond (that is the fast
# per-deploy gate in deploy.sh's workflow_smoke).
#
# Real Batch runs cost money + minutes, so this is NOT a per-deploy gate. It is
# meant to run AFTER a successful deploy (workflow_run), on a nightly schedule,
# or on-demand — off the deploy critical path, alert-on-failure (never rolls a
# deploy back over a Batch flake).
#
# Runs ON the deployed host (curl localhost:3000). Needs: curl, python3.
#
# Env:
#   BASE_URL        default http://localhost:3000 (the Node frontend on the host)
#   SMOKE_E2E_TOKEN x-e2e-test-token value — bypasses the 5/hour guest rate limit
#                   on generate_workflow + billing quota (REQUIRED in practice;
#                   without it repeated generate calls hit the guest limit)
#   SAMPLES         optional "label=intent" lines to override the default set
#   POLL_TIMEOUT    per-workflow poll budget, seconds (default 900 = 15 min)
#   REQUIRE_OUTPUTS 1 (default) = a completed run must also list output files
#
# Exit: 0 = all samples completed; 1 = at least one did not.

set -uo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
TOKEN="${SMOKE_E2E_TOKEN:-}"
POLL_TIMEOUT="${POLL_TIMEOUT:-900}"
REQUIRE_OUTPUTS="${REQUIRE_OUTPUTS:-1}"

# Default sample set — SELF-CONTAINED workflows (no input-data staging needed),
# each verified to run green end-to-end on test (Batch, real outputs). Spans
# pharmacology (hERG, CNS), ADMET-AI (MPNN), and clinical-trial (BOIN). One
# "label=intent" per line; override via the SAMPLES env var (same format).
# NOTE: "required_params: []" does NOT guarantee self-contained — e.g.
# gene_set_enrichment_analysis reports no required params but still needs a gene
# list and fails at launch, so it is deliberately excluded. Only add workflows
# here after confirming they complete with outputs given ZERO staged input.
DEFAULT_SAMPLES='admet_herg=Screen aspirin CC(=O)Oc1ccccc1C(=O)O for ADMET and hERG cardiac safety
cns_penetration=Predict blood-brain barrier BBB permeability for a small molecule
admet_ai=Predict aqueous solubility and lipophilicity for a molecule
clinical_trial=Perform BOIN dose escalation design for a phase I trial'
SAMPLES="${SAMPLES:-$DEFAULT_SAMPLES}"

CT='-H'; CTV='Content-Type: application/json'
XF='-H'; XFV='X-Forwarded-Proto: https'
auth_args=()
[ -n "$TOKEN" ] && auth_args=(-H "x-e2e-test-token: $TOKEN")

curl_json() { # method path datafile-or-empty
  local method="$1" path="$2" data="${3:-}"
  if [ -n "$data" ]; then
    curl -sS -m 160 "$CT" "$CTV" "$XF" "$XFV" "${auth_args[@]}" -X "$method" "$BASE_URL$path" --data "@$data" 2>/dev/null
  else
    curl -sS -m 30 "$CT" "$CTV" "$XF" "$XFV" "${auth_args[@]}" -X "$method" "$BASE_URL$path" 2>/dev/null
  fi
}

PASS=0; FAIL=0; RESULTS=""

run_sample() {
  local label="$1" intent="$2"
  echo "── sample: $label ──"

  # 1) generate — get the workflow_ga (guarded: must actually route)
  printf '{"request_text":%s}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$intent")" > /tmp/wf_gen_req.json
  curl_json POST /api/ai_assistant/generate_workflow /tmp/wf_gen_req.json > /tmp/wf_gen.json
  local wf_name
  wf_name=$(python3 -c "
import json,sys
try: d=json.load(open('/tmp/wf_gen.json'))
except Exception: print(''); sys.exit()
wf=d.get('workflow_ga') or {}
if wf.get('name') and wf.get('nextflow_path'):
    json.dump({'workflowDefinition':wf}, open('/tmp/wf_exec_req.json','w')); print(wf.get('name'))
else:
    print('')
" 2>/dev/null)
  if [ -z "$wf_name" ]; then
    echo "  FAIL generate — no route (rate-limited? routing broken?). body: $(head -c 160 /tmp/wf_gen.json)"
    RESULTS="$RESULTS\n  FAIL  $label (generate/no-route)"; FAIL=$((FAIL+1)); return
  fi
  echo "  routed -> $wf_name"

  # 2) execute -> runId
  local run_id
  run_id=$(curl_json POST /api/workflows/execute /tmp/wf_exec_req.json | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(''); sys.exit()
print(d.get('runId') or '')
" 2>/dev/null)
  if [ -z "$run_id" ]; then
    echo "  FAIL execute — no runId"
    RESULTS="$RESULTS\n  FAIL  $label (execute)"; FAIL=$((FAIL+1)); return
  fi
  echo "  launched run: $run_id"

  # 3) poll to terminal
  local status="" elapsed=0 step=15
  while [ "$elapsed" -lt "$POLL_TIMEOUT" ]; do
    status=$(curl_json GET "/api/workflows/runs/$run_id/status" | python3 -c "
import json,sys
try: print((json.load(sys.stdin).get('status') or '').lower())
except Exception: print('')
" 2>/dev/null)
    case "$status" in
      completed|success|succeeded) break ;;
      failed|error|cancelled)      break ;;
    esac
    sleep "$step"; elapsed=$((elapsed+step))
  done
  echo "  final status: ${status:-timeout} (${elapsed}s)"

  case "$status" in
    completed|success|succeeded) : ;;
    *)
      echo "  FAIL — run did not complete (status=${status:-timeout})"
      RESULTS="$RESULTS\n  FAIL  $label (status=${status:-timeout})"; FAIL=$((FAIL+1)); return ;;
  esac

  # 4) verify outputs (optional)
  if [ "$REQUIRE_OUTPUTS" = "1" ]; then
    local nfiles
    nfiles=$(curl_json GET "/api/workflows/runs/$run_id/outputs" | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(0); sys.exit()
fs=d if isinstance(d,list) else (d.get('files') or d.get('outputs') or [])
print(len(fs))
" 2>/dev/null)
    if [ "${nfiles:-0}" -lt 1 ]; then
      echo "  FAIL — completed but produced 0 output files"
      RESULTS="$RESULTS\n  FAIL  $label (no outputs)"; FAIL=$((FAIL+1)); return
    fi
    echo "  outputs: $nfiles file(s)"
  fi

  echo "  PASS $label"
  RESULTS="$RESULTS\n  PASS  $label ($wf_name)"; PASS=$((PASS+1))
}

echo "=== sample-workflow execution smoke @ $BASE_URL (per-wf timeout ${POLL_TIMEOUT}s) ==="
[ -z "$TOKEN" ] && echo "::warning:: SMOKE_E2E_TOKEN unset — generate may hit the 5/hour guest rate limit"

while IFS= read -r line; do
  [ -z "$line" ] && continue
  label="${line%%=*}"; intent="${line#*=}"
  run_sample "$label" "$intent"
done <<< "$SAMPLES"

echo ""
echo "=== results: PASS=$PASS FAIL=$FAIL ==="
printf '%b\n' "$RESULTS"
echo "SAMPLE_SMOKE_RESULT=$([ "$FAIL" -eq 0 ] && echo pass || echo fail)"
[ "$FAIL" -eq 0 ]
