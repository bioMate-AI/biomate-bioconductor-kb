#!/usr/bin/env bash
# Launch ANDV publication-positive science sprint tracks in parallel.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SPRINT="${ROOT}/research/anti-virus/science_sprint"
LOG_DIR="${SPRINT}/logs"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$LOG_DIR" "${SPRINT}/runs"

export BIOMATE_API_URL="${BIOMATE_API_URL:-http://127.0.0.1:8081}"
export GALAXY_API_KEY="${GALAXY_API_KEY:-}"

cd "$ROOT"

echo "[sprint] UTC $TS — logs in $LOG_DIR"

# Fast local tracks (finish in minutes)
python3 "$SPRINT/track_plan_a_structural_epitopes.py" \
  >"$LOG_DIR/${TS}_structural.log" 2>&1 &
PID_STRUCT=$!

python3 "$SPRINT/track_plan_a_cross_species.py" \
  >"$LOG_DIR/${TS}_cross_species.log" 2>&1 &
PID_CROSS=$!

# API / Batch tracks
python3 "$SPRINT/track_plan_a_multitool.py" --ensure-worktree \
  >"$LOG_DIR/${TS}_multitool.log" 2>&1 &
PID_MULTI=$!

python3 "$SPRINT/track_inh_ensemble_docking.py" \
  >"$LOG_DIR/${TS}_ensemble.log" 2>&1 &
PID_ENS=$!

python3 "$SPRINT/track_inh_md.py" --gromacs-n-steps "${GROMACS_N_STEPS:-250000}" \
  >"$LOG_DIR/${TS}_md.log" 2>&1 &
PID_MD=$!

echo "[sprint] PIDs: structural=$PID_STRUCT cross=$PID_CROSS multitool=$PID_MULTI ensemble=$PID_ENS md=$PID_MD"

wait "$PID_STRUCT" && echo "[sprint] structural DONE" || echo "[sprint] structural FAIL"
wait "$PID_CROSS" && echo "[sprint] cross_species DONE" || echo "[sprint] cross_species FAIL"
wait "$PID_MULTI" && echo "[sprint] multitool DONE" || echo "[sprint] multitool FAIL"
wait "$PID_ENS" && echo "[sprint] ensemble DONE" || echo "[sprint] ensemble FAIL"
wait "$PID_MD" && echo "[sprint] md DONE" || echo "[sprint] md FAIL"

echo "[sprint] All tracks finished. Tail logs: ls -lt $LOG_DIR | head"
