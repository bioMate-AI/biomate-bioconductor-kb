# Benchmark Error Analysis → LLM Training Gold (owner-bucketed)

**Date:** 2026-10-22 · **Tool:** `evaluation/local_trial/error_analysis.py` (read-only, offline)
**Point:** turn benchmark failures into model improvement — but only the MODEL-owned ones. Most
"errors" are harness/data/eval (session diagnosis), so training on them is wasted.

## Method (routing — the clean case)
Same items scored BARE and +HARNESS(catalog) → bucket each item by owner:
- **correct** (bare already right)
- **harness_fixable** — bare-wrong, catalog-right → a RETRIEVAL lever, NOT a training target
- **model_or_data** — bare-wrong AND catalog-wrong → training candidate (minus the subset whose
  gold workflow isn't in the catalog = a DATA gap)

## Result (cross_domain_routing, n=200)
| model | correct | harness_fixable | model/data |
|---|---|---|---|
| on-prem **sft** | 57 | **112** | **31** |
| on-prem base | 36 | 128 | 36 |
| DeepSeek V4-pro (contrast) | 83 | 85 | 32 |

**Headline:** of the on-prem SFT's 143 routing failures, **78% (112) are harness-fixable** and only
**22% (31) are genuine model-training targets.** Training on the 78% is wasted — the harness owns
them. This is the owner-categorization in action: error analysis tells you *what not to train* as
much as what to train.

## Extended to param_prefill + autofix

**param_prefill (n=170)** — owner split by failure type:
| model | ok_restraint | must_not_fill_violation (MODEL over-fill → train) | value/missing |
|---|---|---|---|
| sft | 102 | **34** | 34 |
| base | 97 | **51** | 22 |

The `must_not_fill_violation` is the unambiguous model-owned error (filled a forbidden param).
Notable: **sft (34) < base (51)** — the gold-SFT *improved* restraint over base here (a real positive
data point; contrast with the earlier multitask-SFT that worsened it). `value/missing` is flagged,
not auto-gold (needs alias-aware value checking, e.g. hg38≡GRCh38).

**autofix (n=100)** — pure model reasoning (error-log → fix category; no harness lever): sft **15**
model errors, base 13 → all trainable.

## Output
`evaluation/local_trial/error_analysis_gold_candidates.jsonl` — **94** deduped MODEL-owned failures
(routing model/data + param must_not_fill-overfill + autofix wrong-category), each with
`{task, owner, id, prompt, gold, …}` → directly usable as SFT targets / GRPO prompts. True trainable
count is ≤94 after subtracting routing DATA-gap items (gold workflow not in catalog).

## Discipline
- Clean evals only (never the leaked `decomposition_v2`).
- The same method extends to `param_prefill` (a `must_not_fill` over-fill = model over-filling =
  trainable), `autofix`, etc. — each with its own owner split.
- Feeds the staged RL: these gold candidates expand the real-gold SFT/GRPO pool (`stage_onprem_rl_run.sh`),
  and a "win" is re-measured on the same clean eval vs the SFT start policy.
