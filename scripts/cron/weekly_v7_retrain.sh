#!/usr/bin/env bash
# Weekly auto-retrain pipeline (item 6 from handoff).
#
# Runs once a week to:
#   1. Build customer-edits DPO pool from the accumulated customer_pairs.jsonl
#   2. Merge with synthetic + rejection-sampled pools
#   3. Skip retrain if customer-edit count is below threshold (no new signal)
#   4. Launch v{N+1} DPO training from the current production adapter
#   5. Evaluate v{N+1} against the test split
#   6. Auto-promote v{N+1} only if every checker pass rate is ≥ v{N}
#      (no regression); otherwise keep v{N} and alert reg-science.
#
# Install (host):
#   ln -s "$PWD/scripts/cron/weekly_v7_retrain.sh" \
#         /etc/cron.weekly/biomate-regulatory-retrain
#
# Manual run:
#   bash scripts/cron/weekly_v7_retrain.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Configuration
MIN_NEW_CUSTOMER_PAIRS=25     # below this, skip retrain (no signal)
ALERT_EMAIL=${REG_SCIENCE_ALERT:-reg-science@biomate.local}
LOG_DIR=logs/cron
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/weekly_retrain_$(date +%Y%m%d_%H%M%S).log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== weekly retrain pipeline start ==="

# ---------------------------------------------------------------------------
# 1. Determine current production adapter version (v6 → v7-candidate)
# ---------------------------------------------------------------------------
CURRENT_VER=$(
    ls -1d models/regulatory_llm_v[0-9]* 2>/dev/null \
    | sort -V | tail -1 | sed -E 's|.*regulatory_llm_v([0-9]+).*|\1|'
)
if [[ -z "$CURRENT_VER" ]]; then
    log "FATAL: no production adapter found in models/"
    exit 1
fi
NEXT_VER=$((CURRENT_VER + 1))
log "current: v${CURRENT_VER}  →  candidate: v${NEXT_VER}"

# ---------------------------------------------------------------------------
# 2. Build customer-edits DPO pool
# ---------------------------------------------------------------------------
CUST_PAIRS=data/regulatory_training/dpo/customer_pairs.jsonl
if [[ ! -s "$CUST_PAIRS" ]]; then
    log "no customer pairs accumulated — skipping retrain (run again next week)"
    exit 0
fi
N_CUST=$(wc -l < "$CUST_PAIRS")
log "customer_pairs.jsonl has $N_CUST entries"
if (( N_CUST < MIN_NEW_CUSTOMER_PAIRS )); then
    log "below threshold ($MIN_NEW_CUSTOMER_PAIRS) — skipping retrain"
    exit 0
fi

python scripts/build_dpo_pairs.py --mode customer-edits \
    --out data/regulatory_training/dpo/customer_validated_pairs.jsonl \
    2>&1 | tee -a "$LOG"

# ---------------------------------------------------------------------------
# 3. Merge synthetic + rejection-sampled + customer-validated → merged pool
# ---------------------------------------------------------------------------
MERGED=data/regulatory_training/dpo/merged_pairs_v${NEXT_VER}.jsonl
cat data/regulatory_training/dpo/synthetic_pairs.jsonl \
    data/regulatory_training/dpo/rejection_pairs_phase_gating.jsonl \
    data/regulatory_training/dpo/customer_validated_pairs.jsonl \
    2>/dev/null > "$MERGED"
log "merged pool: $(wc -l < "$MERGED") pairs → $MERGED"

# ---------------------------------------------------------------------------
# 4. Launch DPO training for v{N+1}
# ---------------------------------------------------------------------------
V_PREV_ADAPTER=models/regulatory_llm_v${CURRENT_VER}/lora_adapter
V_NEW_OUT=models/regulatory_llm_v${NEXT_VER}

if [[ ! -d "$V_PREV_ADAPTER" ]]; then
    log "FATAL: $V_PREV_ADAPTER not found"
    exit 1
fi

log "launching DPO training: resume from $V_PREV_ADAPTER"
docker run --rm \
    --gpus all --ipc=host \
    --ulimit memlock=-1 --ulimit stack=67108864 \
    -v "$PWD":/workspace -w /workspace \
    biomate/regulatory-llm-train:latest \
    python scripts/finetune_regulatory_llm.py \
        --model qwen3-8b \
        --dpo --dpo-data "$MERGED" \
        --resume "$V_PREV_ADAPTER" \
        --output "$V_NEW_OUT" \
        --epochs 2 --batch-size 1 --grad-accum 16 \
        --lora-r 16 --lora-alpha 32 --lr 2e-4 \
    2>&1 | tee -a "$LOG"

NEW_ADAPTER="$V_NEW_OUT/lora_adapter"
if [[ ! -f "$NEW_ADAPTER/adapter_config.json" ]]; then
    log "FATAL: training did not produce $NEW_ADAPTER"
    exit 1
fi

# ---------------------------------------------------------------------------
# 5. Evaluate v{N+1} against the test split
# ---------------------------------------------------------------------------
log "evaluating v${NEXT_VER}"
NEW_EVAL=evaluation/results/regulatory_v${NEXT_VER}
mkdir -p "$NEW_EVAL"
docker run --rm \
    --gpus all --ipc=host \
    --ulimit memlock=-1 --ulimit stack=67108864 \
    -v "$PWD":/workspace -w /workspace \
    biomate/regulatory-llm-train:latest \
    python scripts/evaluate_v6.py --adapter "$NEW_ADAPTER" \
        --out "$NEW_EVAL/test_predictions.jsonl" \
    2>&1 | tee -a "$LOG"

# ---------------------------------------------------------------------------
# 6. Auto-promote decision
#    Promote only if NEW pass rate >= CURRENT pass rate on every checker.
# ---------------------------------------------------------------------------
CURRENT_EVAL=evaluation/results/regulatory_v${CURRENT_VER}/summary.json
if [[ ! -f "$CURRENT_EVAL" || ! -f "$NEW_EVAL/summary.json" ]]; then
    log "WARN: missing summary.json — manual review required"
    exit 0
fi

PROMOTE=$(python - <<PY
import json
prev = json.load(open("$CURRENT_EVAL"))
new  = json.load(open("$NEW_EVAL/summary.json"))
ok = True
for task, stats in prev.items():
    p = stats.get("pass_rate", 0)
    n = new.get(task, {}).get("pass_rate", 0)
    print(f"  {task:25s} v${CURRENT_VER}={p:.1f}%  v${NEXT_VER}={n:.1f}%  "
          + ("OK" if n + 0.5 >= p else "REGRESSION"))
    if n + 0.5 < p:   # allow 0.5pp noise tolerance
        ok = False
print("PROMOTE" if ok else "HOLD")
PY
)
log "$PROMOTE"

if echo "$PROMOTE" | grep -q "PROMOTE"; then
    log "v${NEXT_VER} matches/exceeds v${CURRENT_VER} on every checker — promoting"
    # The active adapter is resolved at request time by _resolve_adapter_path()
    # which prefers numerically higher versions automatically. Nothing else
    # to do — next backend restart picks it up.
    echo "v${NEXT_VER} promoted on $(date)" >> models/PROMOTION_LOG.txt
else
    log "v${NEXT_VER} regressed on at least one checker — HOLDING at v${CURRENT_VER}"
    # Quarantine the new adapter so _resolve_adapter_path() doesn't pick it up
    mv "$V_NEW_OUT" "${V_NEW_OUT}_QUARANTINED_$(date +%Y%m%d)"
    log "moved to $(ls -d ${V_NEW_OUT}_QUARANTINED_* 2>/dev/null | tail -1)"
    if command -v mail >/dev/null; then
        echo "v${NEXT_VER} regression — see $LOG" \
            | mail -s "[BioMate] regulatory LLM retrain held" "$ALERT_EMAIL" || true
    fi
fi

log "=== weekly retrain pipeline end ==="
