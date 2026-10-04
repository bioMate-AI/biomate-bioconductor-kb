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
LABELS=${LABELS:-"base ft"}  # which generation labels to refold/rerank
HERE=${HERE:-$ROOT/code}
# DRY = cheapest possible A1/A2 confirmation: one target (build_candidates.py truncates to recs[:1])
# AND one label (first of LABELS). The base-vs-ft rerank is then skipped (needs both labels).
if [ "$DRY_RUN" = 1 ]; then LABELS=$(echo "$LABELS" | awk '{print $1}'); fi

stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/sc_status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }

# --- install Boltz (cyclic-capable predictor) into a conda env with PREBUILT scipy/numpy ---
# (miniforge base is py3.13 -> `pip install boltz` rebuilds scipy from source -> OpenBLAS-not-found
#  FATAL. py3.11 + conda-forge scipy/numpy ship prebuilt wheels/libs, so pip never compiles scipy.)
stage installing_boltz
source /opt/miniforge/etc/profile.d/conda.sh
conda create -y -n boltz -c conda-forge python=3.11 numpy scipy >/dev/null 2>&1 || { echo "FATAL: conda create (boltz) failed"; exit 1; }
set +u; conda activate boltz; set -u
pip install -q --upgrade pip
pip install -q boltz || { echo "FATAL: boltz install failed"; exit 1; }
# Boltz-2's triangle-attention kernel imports cuequivariance_torch (not a hard dep of `boltz`);
# without it, `boltz predict` crashes mid-fold with ModuleNotFoundError. Install it explicitly.
pip install -q cuequivariance-torch || { echo "FATAL: cuequivariance-torch install failed"; exit 1; }
python -c "import boltz, cuequivariance_torch; print('boltz', getattr(boltz,'__version__','?'), 'cueq OK')"
# NOTE: Boltz requires an MSA; folds use --use_msa_server (confirmed: single-seq w/o MSA errors out).

# --- preflight A1/A2: confirm the layout on ONE target before spending folds ---
stage preflight_layout
for label in $LABELS; do
  d="$RES/$label"
  [ -d "$d" ] || { echo "FATAL(A?): missing $d — run a generation that saved candidates first"; exit 1; }
  rep="$d/eval_report_.jsonl"; [ -f "$rep" ] || rep="$d/results.jsonl"
  [ -f "$rep" ] || { echo "FATAL(A2): no eval_report_.jsonl / results.jsonl under $d"; exit 1; }
  CAND_GLOB=${CAND_GLOB:-$d/candidates}
  [ -d "$CAND_GLOB" ] || { echo "FATAL(A1): no candidate-pose dir under $d (expected candidates/); confirm UniMoMo save layout + set CAND_GLOB"; exit 1; }
done
echo "preflight OK: results + candidate dirs present for labels: $LABELS"

# --- per-label: build candidates.jsonl (top-K refolded) ---
build_label(){ # $1=label
  local label="$1" d="$RES/$1"
  stage "refolding_$label"
  REP="$d/eval_report_.jsonl"; [ -f "$REP" ] || REP="$d/results.jsonl"
  LABEL="$label" DLABEL="$d" TOPK="$TOPK" DRY_RUN="$DRY_RUN" REP="$REP" \
  python "$HERE/build_candidates.py" > "$ROOT/status/candidates_$label.jsonl" 2> "$ROOT/status/refold_$label.log"
  aws s3 cp "$ROOT/status/candidates_$label.jsonl" "$OUT_S3/status/candidates_$label.jsonl" --only-show-errors
}
for label in $LABELS; do build_label "$label"; done

# --- re-rank + designability summary (needs BOTH base and ft candidate files) ---
if [ -f "$ROOT/status/candidates_base.jsonl" ] && [ -f "$ROOT/status/candidates_ft.jsonl" ]; then
  stage summarizing
  python "$HERE/selfconsistency_rerank.py" \
    --base "$ROOT/status/candidates_base.jsonl" --ft "$ROOT/status/candidates_ft.jsonl" \
    --out "$ROOT/status/selfconsistency_summary.json"
  aws s3 cp "$ROOT/status/selfconsistency_summary.json" "$OUT_S3/status/selfconsistency_summary.json" --only-show-errors
  stage selfconsistency_complete
  echo "DONE -> $OUT_S3/status/selfconsistency_summary.json"
else
  # DRY / single-label: A1/A2 confirmed via candidate extraction; base-vs-ft rerank intentionally skipped.
  echo "DRY/single-label ($LABELS): candidate extraction validated; base-vs-ft rerank skipped (needs both)."
  for label in $LABELS; do
    echo "---- candidates_$label.jsonl (first record) ----"; head -1 "$ROOT/status/candidates_$label.jsonl" || true
  done
  stage dry_candidates_complete
  echo "DRY DONE -> $OUT_S3/status/candidates_<label>.jsonl (+ refold_<label>.log)"
fi
