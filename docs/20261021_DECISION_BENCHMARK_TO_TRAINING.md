# DrugDev Decision Benchmark → On-Prem LLM Training Gold

**Date:** 2026-10-21
**What:** Convert the 9-archetype / 30-task DrugDev *decision* benchmark into SFT + GRPO
training data for the on-prem model, closing the benchmark→training loop CLAUDE.md asks for.
**Builder:** `evaluation/local_trial/build_decision_sft.py` · **Reward:**
`evaluation/local_trial/decision_reward.py`
**Outputs:** `docs/20260912_onprem_llm/data_pool_v2/{decision_sft.jsonl, decision_grpo.jsonl,
decision_sft_manifest.json}`

## Why this is the right training signal

The decision benchmark grades the **decision + reasoning**, not tool-routing, against
real-data ground truth with objective scorers. Those scorers are therefore **verifiable
rewards** (no reward model, no proxy), and the gold decisions are **SFT targets**. So the
same artifacts serve eval *and* training — optimizing GRPO on `decision_reward` optimizes
exactly the benchmarked decision quality.

This matches the architecture conclusion (docs thread 2026-10-21): train the model's
**judgment / knowledge / composition**, and **route deterministic computation to the engine**.

## What was built

- **SFT rows** (`decision_sft.jsonl`, 30) — `{"messages":[system,user,assistant]}`, the schema
  `train_qlora_pilot.py` reads. The assistant message is a **synthesized gold completion**: a
  correct decision with a short data-grounded rationale ending in the exact structured block
  (DECISION / verdict / action / required / answer / chain).
- **GRPO rows** (`decision_grpo.jsonl`, 30) — `{"prompt","gold"(json ground_truth),"scorer",
  "labels","policy"}`. TRL forwards `gold`/`scorer`/`labels` to `decision_reward.decision_reward`,
  which dispatches to the matching decision scorer and returns the composite in [0,1].

## Fail-closed gold verification

Every synthesized gold completion is **scored by its own scorer before emission**; the builder
refuses to write any target below 0.9. Current run: **30/30 gold completions score 1.000.**
No non-winning SFT target is ever emitted.

## Policy tag (the key design point)

| policy | count | archetypes | training intent |
|---|---|---|---|
| `learn_decision` | 27 | triage, FEP selection, MTD, tissue exposure, special-pop, process knowledge, workflow chains, schedule | the model SHOULD learn this judgment/knowledge/composition |
| `route_not_compute` | 3 | dose projection (MRSD, allometry) | numeric/deterministic — keep as ROUTE+interpret exemplars; the **engine computes**, the model must **not** learn arithmetic (LLMs are unreliable at it) |

So the three numeric dose-projection rows are included only to teach *routing + interpreting*
a computed result, not to memorize the arithmetic — consistent with the rule-first principle.

## How to use (GATED — needs GPU; not run here)

- SFT:  `train_qlora_pilot.py --data docs/20260912_onprem_llm/data_pool_v2/decision_sft.jsonl …`
  (optionally filter to `policy == learn_decision`, or down-weight `route_not_compute`).
- GRPO: point a `GRPOTrainer` at `decision_grpo.jsonl` with
  `reward_funcs=[decision_reward.decision_reward]` (mirrors the decomp GRPO setup).

Scale note: 30 tasks is a **seed** — real training needs the gold expanded (more compounds
per archetype, the remaining archetypes A/B/D/I, and the provisional F2/F4 values verified).
The builder regenerates deterministically as the benchmark grows.

See `project_drugdev_benchmark_series`, `feedback_benchmark_practical_decisions`,
`project_sft_from_gold_result`, `project_execution_grader`.
