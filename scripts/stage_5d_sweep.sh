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

echo; echo "# CAVEAT — resolved 2026-10-22 (do not use run_stability.py for the roster):"
echo "#  run_stability.py / run_consistency_benchmark.py are the BioMate-harness / Ollama path on a"
echo "#  DIFFERENT benchmark set (biomni_eval1/labbench/routing/bixbench/sgi, loaded from prior result"
echo "#  DBs). They do NOT cover the OpenRouter roster on the 8 RealBio leaderboard tasks. Keep them"
echo "#  for BioMate/open-model stability; use the run_baseline recipe below for the roster."

echo; echo "# D2 Stability (roster, RealBio tasks) — N× run_baseline then consistency over the N sets"
echo "#  (consistency_rate / Cohen's κ / flip_rate; CLAUDE.md target ≥90%)."
echo "#  !!! Two prerequisites BEFORE firing (small glue, not yet built):"
echo "#   (a) run_baseline writes results/<model>/<task>.jsonl and OVERWRITES on repeat — add a"
echo "#       --run-index (or copy each run aside) so the N sets are distinct."
echo "#   (b) D2 is MEANINGLESS at greedy/temperature-0 (repeats are identical → trivially 1.0) —"
echo "#       the stability runs MUST use production sampling (temperature>0), unlike the accuracy sweep."
echo "#  Recipe (per model m in the roster, N=3, production temp):"
echo "+   for i in 1 2 3: (cd $PE && python3 run_baseline.py <task> --model m --run-index \$i --temperature <prod>)"
echo "+   python3 compute_roster_stability.py   # score each run via score.py; build StabilityReport via"
echo "+     evaluation.core.stability_runner (TaskStabilityResult / StabilityReport / _mean_pairwise_kappa)"
echo "  (dry; build the run-index + compute_roster_stability glue, set prod temperature, then EXECUTE=1)"

echo; echo "# D5 Hallucination + full 5-D consolidation — via FiveDimensionReporter over the results DB"
echo "#  (runs hallucination_detector on a sample of responses; needs an LLM judge configured)."
echo "#  Pattern (confirm the reporter entrypoint/args against five_dimension_reporter.py):"
echo "+   python3 -c \"from evaluation.core.five_dimension_reporter import report_from_db, FiveDimensionReporter; ...(store, n_stability_repeats=3, hallucination_sample_frac=0.3)\""
echo "  (dry; wire the exact call once the per-model results + a judge are in the ResultsStore)"

echo; echo "# After D2/D5 land in the store: refresh the consolidated view (D3/D4 already offline):"
run bash -c "cd '$PE' && python3 build_5d_leaderboard.py"

echo; echo "=== staged. Nothing above ran unless EXECUTE=1. Resolve the model-wiring CAVEAT first. ==="
