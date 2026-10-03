#!/bin/bash
# Spot-resilient trainer for ONE model size. Self-sufficient: downloads base model, pulls data,
# resumes from S3 checkpoints, mirrors checkpoints to S3, handles the spot interruption notice.
# SFT-first path (mid-train optional): STAGE=sft trains the SFT adapter directly on the base.
#   MODEL_SIZE=small STAGE=sft bash spot_train.sh
set -euo pipefail
TRAIN_LOG=${TRAIN_LOG:-/var/log/spot_train.log}
exec > >(tee -a "$TRAIN_LOG") 2>&1
SIZE=${MODEL_SIZE:-small}; STAGE=${STAGE:-sft}; TAG=${TAG:-}   # TAG namespaces outputs for A/B variants (e.g. _mix)
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
CKPT_S3="$S3/spot_ckpt/$SIZE/$STAGE$TAG"; LOG_S3="$S3/spot_logs/$SIZE/$STAGE$TAG"
OUT="$SCRATCH/out/$SIZE/$STAGE"; mkdir -p "$OUT" "$SCRATCH/data" "$SCRATCH/models"
case "$SIZE" in
  small) HF=Qwen/Qwen3-4B    ; SFT=500; MID=400; SEQ=2048; R=16 ;;
  med)   HF=Qwen/Qwen3.5-9B  ; SFT=500; MID=400; SEQ=2048; R=16 ;;   # 9B (Insilico's L-Qwen winner base)
  large) HF=Qwen/Qwen3.8-27B ; SFT=700; MID=800; SEQ=2048; R=32 ;;
  *) echo "MODEL_SIZE must be small|med|large"; exit 1 ;;
esac
HF=${HF_OVERRIDE:-$HF}   # allow pinning an exact base (e.g. a specific 9B revision)
SEQ=${SEQ_OVERRIDE:-$SEQ}; R=${R_OVERRIDE:-$R}; MID=${MID_OVERRIDE:-$MID}; SFT=${SFT_OVERRIDE:-$SFT}   # overrides to fit GPU / set corpus coverage
BS=${BS_OVERRIDE:-1}; GA=${GA_OVERRIDE:-16}   # per-device batch + grad-accum (raise BS to fill a big GPU)
# reduce CUDA fragmentation (the packed-logits allocation OOM'd a 24GB L4 with 12GB reserved-but-free)
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
NGPU=$(nvidia-smi -L 2>/dev/null | wc -l) || NGPU=0; [ "${NGPU:-0}" -ge 1 ] || NGPU=1
# multi-GPU -> torchrun data-parallel (each rank = full model on its own GPU); single GPU -> plain python
# FORCE_NGPU pins the launcher (e.g. =1 to use the proven single-process path even on a multi-GPU box).
[ -n "${FORCE_NGPU:-}" ] && NGPU=$FORCE_NGPU
# --tee/--redirects surface each rank's child traceback into the log (torchrun otherwise hides it: error_file N/A).
if [ "$NGPU" -gt 1 ]; then LAUNCH="torchrun --nproc_per_node=$NGPU --master_port=29500 --tee 3 --redirects 3"; else LAUNCH="python3"; fi
echo "[spot] GPUs=$NGPU launcher='$LAUNCH' per-device-batch=$BS grad-accum=$GA (effective batch=$((BS*GA*NGPU)))"
BASE="$SCRATCH/models/base_$SIZE"

# stream this log to S3 every 30s so progress/errors are observable without SSH
( while true; do aws s3 cp "$TRAIN_LOG" "$LOG_S3/train.log" --quiet 2>/dev/null; sleep 30; done ) &
LOGPID=$!

echo "[spot] $(date) size=$SIZE stage=$STAGE — pull data + base"
aws s3 cp "$S3/sft/${SFT_DATA:-multitask_sft_enriched.jsonl}" "$SCRATCH/data/sft_enriched.jsonl" --quiet
[ -n "${DPO_PAIRS:-}" ] && aws s3 cp "$S3/sft/${DPO_PAIRS}" "$SCRATCH/data/dpo_pairs.jsonl" --quiet && echo "[spot] DPO pairs: $(wc -l < "$SCRATCH/data/dpo_pairs.jsonl")"
[ "$STAGE" != sft ] && aws s3 cp "$S3/midtrain_corpus/midtrain_all.jsonl" "$SCRATCH/data/midtrain_all.jsonl" --quiet
# MIX_LITERATURE=1 -> mid-train DOMAIN = PubMed literature (stride-sampled) + structured (upweighted).
# Build once + persist to S3 (composition logged for verification); resume pulls the prebuilt mix (cheap).
DATA_MID="$SCRATCH/data/midtrain_all.jsonl"
if [ "${MIX_LITERATURE:-0}" = 1 ] && [ "$STAGE" != sft ]; then
  DATA_MID="$SCRATCH/data/midtrain_domain$TAG.jsonl"      # TAG-namespaced so mixes don't collide across runs
  if aws s3 ls "$S3/midtrain_corpus/${MID_DATA:-midtrain_domain$TAG.jsonl}" >/dev/null 2>&1; then
    echo "[spot] pulling prebuilt domain mix"; aws s3 cp "$S3/midtrain_corpus/${MID_DATA:-midtrain_domain$TAG.jsonl}" "$DATA_MID" --quiet
  else
    echo "[spot] building domain mix = literature + full-text + tool-docs + DB + structured + KG (dedup=${MIX_DEDUP:-1}, keep-every=${LIT_KEEP_EVERY:-5}, struct-repeat=${STRUCT_REPEAT:-8}, kg-repeat=${KG_REPEAT:-1})"
    aws s3 cp "$S3/midtrain_corpus/literature_corpus.jsonl" "$SCRATCH/data/lit.jsonl" --quiet
    KGARG=""
    if [ "${MIX_KG:-0}" = 1 ] && aws s3 ls "$S3/midtrain_corpus/kg_corpus.jsonl" >/dev/null 2>&1; then
      aws s3 cp "$S3/midtrain_corpus/kg_corpus.jsonl" "$SCRATCH/data/kg.jsonl" --quiet
      KGARG="--kg $SCRATCH/data/kg.jsonl --kg-repeat ${KG_REPEAT:-1}"
    fi
    # extra Meditron-style sources: PMC full-text (incl. methods/protocols), tool-docs, DB catalog. Each
    # pulled if present on S3; passed as path:source:repeat. Full-text upweighted (highest-value domain text).
    EXTRA=""
    for spec in "${PMC_FILE:-pmc_fulltext_corpus.jsonl}:pmc_fulltext:${PMC_REPEAT:-2}" \
                "tooldocs_corpus.jsonl:tooldoc:${TOOLDOC_REPEAT:-3}" \
                "db_catalog_corpus.jsonl:db_catalog:${DBCAT_REPEAT:-1}" \
                "forum_corpus.jsonl:forum:${FORUM_REPEAT:-2}"; do
      f="${spec%%:*}"
      if aws s3 ls "$S3/midtrain_corpus/$f" >/dev/null 2>&1; then
        aws s3 cp "$S3/midtrain_corpus/$f" "$SCRATCH/data/$f" --quiet
        EXTRA="$EXTRA --extra $SCRATCH/data/${spec}"
      else echo "[spot] extra source absent, skipping: $f"; fi
    done
    DEDUP=""; [ "${MIX_DEDUP:-1}" = 1 ] && DEDUP="--dedup"
    python3 "$HERE/build_midtrain_mix.py" --lit "$SCRATCH/data/lit.jsonl" --struct "$SCRATCH/data/midtrain_all.jsonl" \
      --out "$DATA_MID" --struct-repeat "${STRUCT_REPEAT:-8}" --lit-keep-every "${LIT_KEEP_EVERY:-5}" $KGARG $EXTRA $DEDUP
    aws s3 cp "$DATA_MID" "$S3/midtrain_corpus/midtrain_domain$TAG.jsonl" --quiet
    aws s3 cp "$DATA_MID.composition.json" "$S3/midtrain_corpus/midtrain_domain$TAG.composition.json" --quiet
  fi
fi
if [ ! -d "$BASE" ]; then
  echo "[spot] downloading base $HF"
  python3 -c "import os; from huggingface_hub import snapshot_download; snapshot_download('$HF', revision=os.environ.get('HF_REVISION') or None, local_dir='$BASE')"
fi

# FETCH_REPLAY=1 → build/reuse the general-replay corpus (FineWeb-Edu, ODC-BY) for the 25/75
# anti-forgetting mixture. Reused from S3 if already staged; else streamed here (disk box) + cached.
if [ "${FETCH_REPLAY:-0}" = 1 ] && [ "$STAGE" != sft ]; then
  REPLAY="$SCRATCH/data/general_replay.jsonl"
  [ -s "$REPLAY" ] || aws s3 cp "$S3/midtrain_corpus/general_replay.jsonl" "$REPLAY" --quiet 2>/dev/null || true
  if [ ! -s "$REPLAY" ]; then
    echo "[spot] streaming general-replay (FineWeb-Edu sample-10BT) -> $REPLAY"
    python3 - "$REPLAY" "${REPLAY_DOCS:-550000}" <<'PYEOF'
import sys, json
from datasets import load_dataset
out, cap = sys.argv[1], int(sys.argv[2])
ds = load_dataset("HuggingFaceFW/fineweb-edu", "sample-10BT", split="train", streaming=True)
n = 0
with open(out, "w") as f:
    for r in ds:
        t = r.get("text", "")
        if len(t) > 300:
            f.write(json.dumps({"text": t[:16000]}) + "\n"); n += 1
        if n >= cap: break
print("general_replay docs:", n)
PYEOF
    aws s3 cp "$REPLAY" "$S3/midtrain_corpus/general_replay.jsonl" --quiet
  fi
  export REPLAY REPLAY_FRAC=${REPLAY_FRAC:-0.75}
  echo "[spot] replay ready: $(wc -l < "$REPLAY") docs, frac=$REPLAY_FRAC"
fi

echo "[spot] resume check"; aws s3 sync "$CKPT_S3/" "$OUT/" --quiet || true
RESUME=""; LAST=$(ls -d "$OUT"/checkpoint-* 2>/dev/null | sort -t- -k2 -n | tail -1) || LAST=""
[ -n "$LAST" ] && RESUME="--resume $LAST" && echo "[spot] resuming from $LAST"

( while true; do aws s3 sync "$OUT/" "$CKPT_S3/" --exclude "*" --include "*checkpoint-*" --quiet; sleep 120; done ) & SYNCPID=$!
( while true; do curl -s -m 2 http://169.254.169.254/latest/meta-data/spot/instance-action | grep -q action \
    && { echo "[spot] interruption notice — final sync"; aws s3 sync "$OUT/" "$CKPT_S3/" --quiet; break; }; sleep 5; done ) & WATCHPID=$!
CHECKPOINT_ROOT="$OUT"
trap 'rc=$?; trap - EXIT; kill $SYNCPID $WATCHPID $LOGPID 2>/dev/null || true; aws s3 sync "$CHECKPOINT_ROOT/" "$CKPT_S3/" --quiet || true; aws s3 cp "$TRAIN_LOG" "$LOG_S3/train.log" --quiet || true; exit "$rc"' EXIT

echo "[spot] START training stage=$STAGE (MID=$MID SFT=$SFT SEQ=$SEQ R=$R)"
if [ "$STAGE" = midtrain ]; then
  $LAUNCH "$HERE/midtrain_run.py" --base "$BASE" --data "$DATA_MID" \
     --out "$OUT" --max-steps $MID --seq-len $SEQ --lora-r $R --batch-size $BS --grad-accum $GA $RESUME ${REPLAY:+--replay "$REPLAY" --replay-frac ${REPLAY_FRAC:-0.5}}
elif [ "$STAGE" = full ]; then
  # committee-v3 fix: domain-adaptive mid-training FIRST, merge, then SFT — all on one box.
  # RESUME-AWARE (safe on-demand<->spot switch via periodic S3 checkpoints):
  #  - if base_domain already built+persisted -> skip midtrain, restore it, go to SFT
  #  - else resume midtrain from its nested checkpoint; SFT resumes from its own nested checkpoint
  if aws s3 ls "$S3/models_20260919/$SIZE/base_domain$TAG/config.json" >/dev/null 2>&1; then
    echo "[spot] base_domain$TAG already built -> restore + skip to SFT"
    mkdir -p "$OUT/base_domain"; aws s3 cp "$S3/models_20260919/$SIZE/base_domain$TAG/" "$OUT/base_domain/" --recursive --quiet
  else
    MLAST=$(ls -d "$OUT"/midtrain/checkpoint-* 2>/dev/null | sort -t- -k2 -n | tail -1) || MLAST=""; MR=""
    [ -n "$MLAST" ] && MR="--resume $MLAST" && echo "[spot] resume midtrain from $MLAST"
    $LAUNCH "$HERE/midtrain_run.py" --base "$BASE" --data "$DATA_MID" \
       --out "$OUT/midtrain" --max-steps $MID --seq-len $SEQ --lora-r $R --batch-size $BS --grad-accum $GA $MR ${REPLAY:+--replay "$REPLAY" --replay-frac ${REPLAY_FRAC:-0.5}}
    python3 "$HERE/merge_lora.py" --base "$BASE" --adapter "$OUT/midtrain" --out "$OUT/base_domain"   # merge = single process
    # PERSIST mid-training artifacts NOW — NVMe is wiped on terminate; base_domain is the SFT adapter's base.
    aws s3 cp "$OUT/midtrain/" "$S3/models_20260919/$SIZE/midtrain_adapter$TAG/" --recursive --exclude "checkpoint-*/*" --quiet
    aws s3 cp "$OUT/base_domain/" "$S3/models_20260919/$SIZE/base_domain$TAG/" --recursive --quiet
  fi
  SLAST=$(ls -d "$OUT"/sft/checkpoint-* 2>/dev/null | sort -t- -k2 -n | tail -1) || SLAST=""; SR=""
  [ -n "$SLAST" ] && SR="--resume $SLAST" && echo "[spot] resume sft from $SLAST"
  $LAUNCH "$HERE/train_qlora_pilot.py" --base "$OUT/base_domain" --data "$SCRATCH/data/sft_enriched.jsonl" \
     --out "$OUT/sft" --max-steps $SFT --seq-len $SEQ --lora-r $R --batch-size $BS --grad-accum $GA $SR
  OUT="$OUT/sft"   # so the upload below grabs the SFT adapter
elif [ "$STAGE" = sftdpo ]; then
  # SFT on v5 (clean+openbook+contrastive+paraphrase) -> merge -> DPO on hard-negative pairs.
  SLAST=$(ls -d "$OUT"/sft/checkpoint-* 2>/dev/null | sort -t- -k2 -n | tail -1) || SLAST=""; SR=""
  [ -n "$SLAST" ] && SR="--resume $SLAST" && echo "[spot] resume sft from $SLAST"
  if aws s3 ls "$S3/models_20260919/$SIZE/sft${TAG}_merged/config.json" >/dev/null 2>&1; then
    echo "[spot] sft${TAG}_merged already built -> restore + skip to DPO"
    mkdir -p "$OUT/sft_merged"; aws s3 cp "$S3/models_20260919/$SIZE/sft${TAG}_merged/" "$OUT/sft_merged/" --recursive --quiet
  else
    $LAUNCH "$HERE/train_qlora_pilot.py" --base "${BASE_DOMAIN:-$BASE}" --data "$SCRATCH/data/sft_enriched.jsonl" \
       --out "$OUT/sft" --max-steps $SFT --seq-len $SEQ --lora-r $R --batch-size $BS --grad-accum $GA $SR
    # FAIL-FAST: don't barrel on if SFT produced no adapter (else merge+DPO fail confusingly)
    [ -f "$OUT/sft/adapter_config.json" ] || { echo "[spot] FATAL: SFT produced no adapter — aborting"; exit 21; }
    python3 "$HERE/merge_lora.py" --base "${BASE_DOMAIN:-$BASE}" --adapter "$OUT/sft" --out "$OUT/sft_merged"
    [ -f "$OUT/sft_merged/config.json" ] || { echo "[spot] FATAL: merge produced no model — aborting"; exit 22; }
    aws s3 cp "$OUT/sft/" "$S3/models_20260919/$SIZE/sft${TAG}_adapter/" --recursive --exclude "checkpoint-*/*" --quiet
    aws s3 cp "$OUT/sft_merged/" "$S3/models_20260919/$SIZE/sft${TAG}_merged/" --recursive --quiet
  fi
  [ -f "$OUT/sft_merged/config.json" ] || { echo "[spot] FATAL: no merged SFT model for DPO — aborting"; exit 23; }
  $LAUNCH "$HERE/train_dpo_grounded.py" --phase train --model "$OUT/sft_merged" \
     --pairs-out "$SCRATCH/data/dpo_pairs.jsonl" --out "$OUT/dpo"
  aws s3 cp "$OUT/dpo/" "$S3/models_20260919/$SIZE/dpo${TAG}_adapter/" --recursive --quiet
  OUT="$OUT/dpo"
else
  $LAUNCH "$HERE/train_qlora_pilot.py" --base "${BASE_DOMAIN:-$BASE}" --data "$SCRATCH/data/sft_enriched.jsonl" \
     --out "$OUT" --max-steps $SFT --seq-len $SEQ --lora-r $R --batch-size $BS --grad-accum $GA $RESUME
fi
RC=$?
echo "[spot] training exit=$RC — upload final adapter"
aws s3 cp "$OUT/" "$S3/models_20260919/$SIZE/${STAGE}${TAG}_adapter/" --recursive --quiet
echo "SPOT_${STAGE}${TAG}_DONE size=$SIZE rc=$RC"
