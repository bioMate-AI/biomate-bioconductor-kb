#!/usr/bin/env bash
# stage_5d_sweep.sh — STAGED, GATED D2 (stability) + D5 (hallucination) sweep for RealBio.
#
# Fills the two remaining dimensions of leaderboard_5d (D1 in leaderboard.csv; D3/D4 already in
# leaderboard_5d.csv). D2 = re-run benchmarks N times and measure cross-run consistency; D5 = run
# the hallucination detector (LLM-judge) on a sample. Both COST REAL $: D2 is N× a normal sweep
# (consistency needs repeats), and D5 adds judge calls.
#
# !!! DRY BY DEFAULT — only PRINTS commands. To run:  EXECUTE=1 bash scripts/stage_5d_sweep.sh
# !!! Confirm per-model wiring first (see CAVEAT) — do NOT fire blind across the roster.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/evaluation/runners"
PE="$ROOT/evaluation/datasets/public_export"
EXECUTE="${EXECUTE:-0}"

run() { echo "+ $*"; if [ "$EXECUTE" = "1" ]; then ( "$@" ); else echo "  (dry; EXECUTE=1 to run)"; fi; }

echo "=== RealBio D2+D5 sweep (EXECUTE=$EXECUTE) ==="

echo; echo "# CAVEAT (read before EXECUTE=1):"
echo "#  run_stability.py / run_consistency_benchmark.py use the default/Ollama client; per-OpenRouter-"
echo "#  ROSTER-MODEL stability is NOT wired the same way as run_all.py (--models). Confirm the model"
echo "#  wiring (route each roster model's repeats through the same run_baseline --model path, writing"
echo "#  to the ResultsStore) BEFORE firing across models. As written, these run the DEFAULT model."

echo; echo "# D2 Stability — cross-run consistency (consistency_rate / Cohen's κ / flip_rate; target ≥90%)"
echo "#  N repeats on a sample per benchmark. Cost ≈ N × (sample × normal sweep)."
run bash -c "cd '$RUN' && python3 run_stability.py --all --n-repeats 3 --sample 0.2"
echo "#  alt (routing/clarification/paraphrase tiers, has its own --dry-run):"
run bash -c "cd '$RUN' && python3 run_consistency_benchmark.py --runs-per-query 3 --tier all"

echo; echo "# D5 Hallucination + full 5-D consolidation — via FiveDimensionReporter over the results DB"
echo "#  (runs hallucination_detector on a sample of responses; needs an LLM judge configured)."
echo "#  Pattern (confirm the reporter entrypoint/args against five_dimension_reporter.py):"
echo "+   python3 -c \"from evaluation.core.five_dimension_reporter import report_from_db, FiveDimensionReporter; ...(store, n_stability_repeats=3, hallucination_sample_frac=0.3)\""
echo "  (dry; wire the exact call once the per-model results + a judge are in the ResultsStore)"

echo; echo "# After D2/D5 land in the store: refresh the consolidated view (D3/D4 already offline):"
run bash -c "cd '$PE' && python3 build_5d_leaderboard.py"

echo; echo "=== staged. Nothing above ran unless EXECUTE=1. Resolve the model-wiring CAVEAT first. ==="
