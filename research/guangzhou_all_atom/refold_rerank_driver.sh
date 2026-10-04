#!/bin/bash
# Self-consistency re-fold + re-rank stage (runs ON a GPU box, after a UniMoMo generation that SAVED
# candidate poses). Produces per-target candidates.jsonl (dockq+likelihood+scrmsd+confidence) for base
# and ft, then selfconsistency_rerank.py -> selfconsistency_summary.json.
#
# Re-folder = Boltz PREDICTION (independent of the UniMoMo generator), cyclic bond constraint.
# NOTE: NOT BoltzGen — BoltzGen's CLI (`boltzgen run --protocol peptide-anything`) is DESIGN mode
# (generates sequences), not fold-a-given-sequence. Structure prediction of a given cyclic sequence is
# `boltz predict` (Boltz-2 supports cyclic peptides via a bond/cyclic constraint). This is the correction
# flagged to the parent.
#
# TWO on-instance assumptions that MUST be confirmed on the first target (preflights fail loud if wrong),
# because the UniMoMo repo was not available locally to verify exact output layout:
#   A1  candidate poses are at   $RES/<label>/candidates/<target>/<k>.pdb   (or .cif)   [CAND_GLOB]
#   A2  per-target records in    $RES/<label>/eval_report_.jsonl            carry DockQ.individual (per
#       candidate, SAME ORDER as the saved poses) and a per-candidate likelihood/score field.
# If A1/A2 differ, adjust CAND_GLOB / the python extractor below — do a DRY_RUN=1 one-target pass first.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
ROOT=${ROOT:-/opt/unimomo-run}
RES=${RES:?dir holding <label>/ generation outputs (results/base, results/ft) with saved candidates}
OUT_S3=${OUT_S3:?}
TOPK=${TOPK:-25}             # re-fold the top-K by likelihood per target (bounds cost: K x 88 x 2 folds)
DRY_RUN=${DRY_RUN:-0}        # 1 = one target per label, to confirm A1/A2 cheaply before the full run
HERE=${HERE:-$ROOT/code}

stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/sc_status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }

# --- install Boltz (cyclic-capable predictor) into an isolated venv ---
stage installing_boltz
python3 -m venv "$ROOT/boltz-venv"
set +u; source "$ROOT/boltz-venv/bin/activate"; set -u
pip install -q --upgrade pip
pip install -q boltz || { echo "FATAL: boltz install failed"; exit 1; }
python -c "import boltz; print('boltz', getattr(boltz,'__version__','?'))"

# --- preflight A1/A2: confirm the layout on ONE target before spending folds ---
stage preflight_layout
for label in base ft; do
  d="$RES/$label"
  [ -d "$d" ] || { echo "FATAL(A?): missing $d — run a generation that saved candidates first"; exit 1; }
  rep="$d/eval_report_.jsonl"; [ -f "$rep" ] || rep="$d/results.jsonl"
  [ -f "$rep" ] || { echo "FATAL(A2): no eval_report_.jsonl / results.jsonl under $d"; exit 1; }
  CAND_GLOB=${CAND_GLOB:-$d/candidates}
  [ -d "$CAND_GLOB" ] || { echo "FATAL(A1): no candidate-pose dir under $d (expected candidates/); confirm UniMoMo save layout + set CAND_GLOB"; exit 1; }
done
echo "preflight OK: results + candidate dirs present for base and ft"

# --- per-label: build candidates.jsonl (top-K refolded) ---
build_label(){ # $1=label
  local label="$1" d="$RES/$1"
  stage "refolding_$label"
  REP="$d/eval_report_.jsonl"; [ -f "$REP" ] || REP="$d/results.jsonl"
  LABEL="$label" DLABEL="$d" TOPK="$TOPK" DRY_RUN="$DRY_RUN" REP="$REP" \
  python "$HERE/build_candidates.py" > "$ROOT/status/candidates_$label.jsonl" 2> "$ROOT/status/refold_$label.log"
  aws s3 cp "$ROOT/status/candidates_$label.jsonl" "$OUT_S3/status/candidates_$label.jsonl" --only-show-errors
}
build_label base
build_label ft

# --- re-rank + designability summary ---
stage summarizing
python "$HERE/selfconsistency_rerank.py" \
  --base "$ROOT/status/candidates_base.jsonl" --ft "$ROOT/status/candidates_ft.jsonl" \
  --out "$ROOT/status/selfconsistency_summary.json"
aws s3 cp "$ROOT/status/selfconsistency_summary.json" "$OUT_S3/status/selfconsistency_summary.json" --only-show-errors
stage selfconsistency_complete
echo "DONE -> $OUT_S3/status/selfconsistency_summary.json"
