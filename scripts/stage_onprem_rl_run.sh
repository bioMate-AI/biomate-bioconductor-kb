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

echo; echo "# PREREQ (VERIFIED 2026-10-22 via read-only 'aws s3 ls', acct 399683337364):"
echo "#  The launcher's hardcoded SFT_ADAPTER_S3=.../med/sft_decompv2_adapter is ABSENT in S3 →"
echo "#  run_grpo_decomp_9b.sh:27-28 would REFUSE TO LAUNCH as-is. Available SFT adapters under"
echo "#  models_20260919/med/: sft_gold_adapter, sft_v3clean_adapter, sft_sftv3real_adapter,"
echo "#  full_today_20261003_adapter, midtrain_adapter, base_domain."
echo "#  RECOMMENDED start policy: sft_gold_adapter (the collected-gold SFT — includes the decomp"
echo "#  lift, node-F1 0.36→0.73). To fire T1, repoint the launcher at it (and it is GPU \$ — explicit go):"
echo "#     SFT_ADAPTER_S3=.../models_20260919/med/sft_gold_adapter EVAL_HOOK=1 EXECUTE=1 bash $0"
echo "#  (choosing the start policy is a real decision; sft_decompv2 was never landed — see diagnosis.)"

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
echo "#  DE-RISKED OFFLINE: decision_reward.build_reward_fn() exposes the TRL reward hook, and"
echo "#   'python3 decision_reward.py --selftest' VERIFIES the data+reward contract end-to-end on the"
echo "#   real gold (22/22: gold completions score high, wrong score lower). So data + reward are"
echo "#   PROVEN; only the TRL trainer wiring remains (version-specific trl==1.14.1 — write+test it in"
echo "#   the GPU env, do NOT guess offline)."
echo "#  UNIFIED REWARD (2026-10-22): decision_reward.score_one now ALSO dispatches the agent-task"
echo "#   scorers (routing / cross_domain_routing / param_select / param_prefill / autofix via"
echo "#   evaluation/scorers/agent_task_scorers.py), so the SAME reward_funcs=[decision_reward] trains"
echo "#   the WHOLE corpus: decision (22) + db_generated routing (9,418) + param (2,741) + error-mined"
echo "#   (94) GRPO rows. --selftest proves oracle>anti-oracle ranking on every real row (12,275 total)."
echo "#   Point the GRPO dataset at a concat of {decision,db_generated_routing,db_generated_param,"
echo "#   error_analysis}_grpo.jsonl (all carry prompt/gold/scorer) — no per-pool reward glue needed."
echo "#  REMAINING GLUE (GPU env): a thin train_grpo_decision.py reusing train_grpo_decomp.py's GRPO"
echo "#   scaffolding with reward_funcs=[decision_reward.build_reward_fn()], dataset=decision_grpo.jsonl"
echo "#   (prompt/gold/scorer/labels columns), eval hook over decision_eval.jsonl. n=22 is a SEED."
run bash -c "cd '$LT' && python3 decision_reward.py --selftest"   # offline contract check (safe)
echo "+   (after trainer glue, GPU) python3 train_grpo_decision.py --base \$BASE --adapter \$SFT --data decision_grpo.jsonl --bench decision_eval.jsonl ..."

echo; echo "# T3 (FURTHEST) — grounded DPO"
echo "#  train_dpo_grounded.py exists (preference pairs from grounded rewards) but has NO launcher and"
echo "#  no run evidence. Needs a spot entry script + preference-pair data before it can be staged to fire."

echo; echo "# After any run lands an adapter in S3: serve + re-eval through the SAME clean evals"
echo "#  (decomposition_real / decision_eval / the RealBio leaderboard bare-vs-harness) and gate any"
echo "#  'win' on a real lift vs the SFT start policy — per the session's leakage lessons."

echo; echo "=== staged. Nothing launched unless EXECUTE=1. T1 is the one ready, highest-upside run. ==="
