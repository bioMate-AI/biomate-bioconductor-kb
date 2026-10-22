#!/usr/bin/env bash
# stage_onprem_rl_run.sh — STAGED, GATED verifiable-reward RL for the on-prem 9B.
#
# The session's strategic conclusion: capacity/CPT are dead levers; the one UNTESTED high-upside
# lever is the deferred verifiable-reward RL (GRPO/DPO) on REAL gold, measured on a clean held-out
# eval. This stages those runs. ALL are SPOT-GPU ($$$), so DRY BY DEFAULT.
#
#   EXECUTE=1 bash scripts/stage_onprem_rl_run.sh      # actually launch (spot GPU spend)
# Readiness tiers below: T1 ready, T2 needs small glue, T3 furthest.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LT="$ROOT/evaluation/local_trial"
EXECUTE="${EXECUTE:-0}"
run() { echo "+ $*"; if [ "$EXECUTE" = "1" ]; then ( "$@" ); else echo "  (dry; EXECUTE=1 to launch spot GPU)"; fi; }

echo "=== on-prem RL run (EXECUTE=$EXECUTE) ==="

echo; echo "# PREREQ: the SFT-decomp adapter must be in S3 (start policy + KL ref). The decomp launcher"
echo "#  already REFUSES TO LAUNCH without it (run_grpo_decomp_9b.sh:27-28). Confirm it exists first."

echo; echo "# T1 (READY) — decomposition GRPO on REAL gold, clean held-out eval"
echo "#  Spot-only, resume-safe, self-terminating; EVAL_HOOK=1 evaluates every eval_steps on"
echo "#  datasets/decomposition_real (OUT-OF-GENERATOR → the honest transfer test, NOT the leaked v2)."
echo "#  Reward = decomp_reward (node/edge-F1 + catalog structural validity). This is THE untested"
echo "#  differentiator: does verifiable-reward RL lift real-topology decomposition above the SFT floor?"
run bash -c "cd '$LT' && EVAL_HOOK=1 bash run_grpo_decomp_9b.sh"

echo; echo "# T2 (NEEDS GLUE) — DECISION GRPO on the decision benchmark (9 archetypes)"
echo "#  Data: docs/20260912_onprem_llm/data_pool_v2/decision_grpo.jsonl (TRAIN split, 22 rows)"
echo "#  Reward: evaluation/local_trial/decision_reward.decision_reward (verifiable; dispatches scorers)"
echo "#  Held-out eval: data_pool_v2/decision_eval.jsonl (DISJOINT — built leak-guarded this session)"
echo "#  GLUE NEEDED: train_grpo_decomp.py hardcodes 'import decomp_reward' (line ~79). Parameterize"
echo "#   it (--reward-module) OR add a thin train_grpo_decision.py reusing the same GRPO loop with"
echo "#   decision_reward + the decision gold. n=22 is a SEED (expand the gold before over-reading)."
echo "+   (after glue) cd '$LT' && python3 train_grpo_decision.py --base \$BASE --adapter \$SFT \\"
echo "+       --data .../decision_grpo.jsonl --reward decision_reward --bench .../decision_eval.jsonl ..."
echo "  (dry; build the reward-param glue first)"

echo; echo "# T3 (FURTHEST) — grounded DPO"
echo "#  train_dpo_grounded.py exists (preference pairs from grounded rewards) but has NO launcher and"
echo "#  no run evidence. Needs a spot entry script + preference-pair data before it can be staged to fire."

echo; echo "# After any run lands an adapter in S3: serve + re-eval through the SAME clean evals"
echo "#  (decomposition_real / decision_eval / the RealBio leaderboard bare-vs-harness) and gate any"
echo "#  'win' on a real lift vs the SFT start policy — per the session's leakage lessons."

echo; echo "=== staged. Nothing launched unless EXECUTE=1. T1 is the one ready, highest-upside run. ==="
