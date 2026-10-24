# On-prem 9B RL — data-generation & study-design survey (pre-redesign)

**Date:** 2026-10-23 · **Purpose:** before spending GPU on a *redesigned* RL run, survey the method
space and the in-repo assets, diagnose why the first unified GRPO run stalled, and specify the
study design. Grounds the redesign in evidence, not a hunch. Builds on (does not duplicate):
`docs/nextPhase/20260409_RL_WORKFLOW_GENERATION_SURVEY.md`,
`docs/20261015_ONPREM_LLM_SFT_DPO_RLVR_STATUS.md`,
`docs/20261019_GRPO_AUTOFIRE_REVIEW_NOTE.md`, `docs/20261008_GOOGLE_MEDLLM_RL_REFERENCE.md`,
`docs/20261006_DECOMP_STAGE2_GRPO_DESIGN.md`.

## 1. What the first unified GRPO run showed (evidence)

Fired 2026-10-22 (commit `ba3abae5a`): start policy `sft_gold_adapter`, unified 12,275-row corpus,
`decision_reward` (dispatches decision/routing/param/autofix). Ran to step ~150/400 on a spot
g6e before reclaim. Training dynamics:
- **`frac_reward_zero_std ≈ 0.95–1.0`** — 95%+ of rollout groups had identical rewards.
- **`kl ≈ 0.001`**, loss ≈ 0, grad_norm ≈ 0.002 — the policy barely moved from `sft_gold`.

**Diagnosis:** GRPO's advantage is the *within-group* reward z-score; a group whose rollouts all
score the same contributes **zero gradient**. 77% of the corpus is **binary** routing (workflow
right/wrong), and the `sft_gold` start is already *consistent per prompt* (gets a prompt all-right
or all-wrong across 8 rollouts) → near-zero within-group variance → GRPO learns from ~5% of the
batch. This is a **study-design error, not a capability result**.

## 2. Method survey — what actually produces signal (grounded)

From the in-repo survey + RLVR literature, the levers that create a usable gradient for a strong SFT
start on verifiable tasks:

| Lever | Mechanism | In-repo status |
|---|---|---|
| **Graded / process reward** | continuous reward → within-group variance even when all rollouts "wrong" (one is closer). The decomp GRPO correctly used **node/edge-F1 + struct-validity** (graded), not binary. | decomp reward graded ✓; routing reward binary ✗ (the regression) |
| **Difficulty / variance filtering** | train only on prompts where the start policy's pass-rate ∈ (0,1) — i.e. where rollouts *disagree*. Prompts the model already always-gets or always-misses give zero advantage and waste compute. Standard in RLVR-for-reasoning. | NOT done — the unified corpus is unfiltered |
| **DPO on preference pairs** | chosen ≻ rejected is a *pairwise* signal — no within-group variance needed. Ideal for binary-correctness tasks (right workflow vs confusable failing sibling). | **BUILT, never run**: `train_dpo_grounded.py`, 286 exec pairs / 15 domains, leak-guarded (`20261015_...RLVR_STATUS`) |
| **Sub-sequence / process credit** (GSsPO, PRM promise/progress) | assign credit to Think→Action cycles, not uniform tokens | survey-noted; future (multi-turn) |
| **Execution-graded reward** | un-gameable PASS/FAIL from a real run | MEASURED eval-only; needs Batch budget + graded-run store (gated) |

**Key reconciliation:** GRPO is the right tool when the reward is **graded/process** and the prompt
set is **variance-rich**; DPO is the right tool for **binary-correctness** tasks where you can form
chosen/rejected **pairs**. The first run misapplied GRPO-on-binary to a consistent SFT start.

## 3. Study design for the redesigned run

Two arms, both grounded in existing assets; run DPO first (cheapest, no variance problem, already
built), then the graded+filtered GRPO.

### Arm A — DPO on grounded preference pairs (recommended first)
- **Data:** the 286 exec pairs (chosen = workflow with `real_exec_status∈{ok,ok_warnings}`; rejected
  = confusable same-domain sibling that failed; request synthesized from shared signal only;
  leak-guarded). **Expand** by mining more chosen/rejected pairs from the catalog's validated subset
  (1,092 real-exec workflows) — pairs need only a correct + a confusable-wrong, which is abundant.
- **Why:** pairwise preference sidesteps the zero-variance failure entirely; matched to binary
  correctness; `train_dpo_grounded.py` exists (built-not-run). No-tiny-dataset bar: expand ≥ a few k pairs.
- **Reward:** programmatic gold-match / did-it-run (upgrade later to execution-graded).

### Arm B — GRPO, graded reward + variance-filtered prompts
- **Graded reward:** replace binary routing in the *training* reward with a graded variant
  (`score_routing_graded`: exact = 1.0, else partial credit for path-token / domain overlap) so
  near-miss rollouts outscore random ones → within-group variance. Decomp already graded; param /
  decision / chain scorers already continuous. Eval stays strict-binary.
- **Variance filter (data-gen step):** before training, sample `sft_gold` k=8× on each prompt,
  compute pass-rate, **keep only 0 < p < 1** prompts. This is a one-time GPU inference pass that
  produces the *trainable* subset (the prompts GRPO can actually move). Expect it to drop the
  always-right and always-wrong prompts — exactly the zero-advantage mass.
- **Knobs:** temperature ↑ (0.9 → 1.1) for rollout diversity; keep KL β=0.04 anchor to sft_gold.

### Shared eval (WIN GATE)
Out-of-generator held-outs only (`decomposition_real` + `decision_eval` + RealBio bare-vs-harness),
scored vs the `sft_gold` start policy, **never** the in-generator `decomposition_v2`. Report
bare-vs-harness so the system-vs-model framing holds. A real lift gates "continue"; flat gates
"RL isn't the lever here — SFT+harness is."

## 4. Recommendation

1. **Run DPO (Arm A) first** — it is built, matched to the task, and immune to the variance failure;
   expand the pair set first to clear the no-tiny-dataset bar.
2. **Then GRPO (Arm B)** with graded routing + the variance-filtered prompt subset — the version that
   is actually worth the GPU (the first run was not).
3. Both gated on the clean held-out WIN GATE vs `sft_gold`.

The `score_routing_graded` scorer for Arm B is implemented (`evaluation/scorers/agent_task_scorers.py`);
the variance-filter pass and the DPO pair expansion are the remaining data-gen steps.
