# On-prem LLM — decisive eval results: base vs sft_v5 vs mid500 vs dpo_v5 (2026-09-30)

All numbers via **vLLM** (deployment-matching), candidate-grounded routing (`gold_routing_eval`, 279) +
17-task `objective_eval`. Confirmed across two independent runs (HF + vLLM agree on routing).

## Routing (accept-set) — decided
| arm | routing |
|---|---|
| **base (plain Qwen3-4B)** | **0.932–0.947** ← best |
| mid500 (base + 500-step mid-train) | 0.910 / 0.853 |
| sft_v5 (clean + open-book + contrastive + paraphrase) | 0.867 |
| dpo_v5 (sft_v5 + hard-neg DPO) | 0.860 |

**Nothing beats the base at routing.** Fine-tuning, mid-train, and DPO all degrade it → routing = **base + retrieval**, no fine-tuning. (4× confirmed.)

## Full 17-task — macro is a TIE (base 0.433, sft_v5 0.436, mid500 0.424) but that hides the split

### SFT wins big — CLEANLY-graded tasks (MCQA exact / accept-set) = TRUSTWORTHY
| task | base → sft_v5 |
|---|---|
| knowledge_recall | 0.28 → **0.66** (+0.38) |
| scientific_qa | 0.19 → **0.47** (+0.29) |
| model_selection | 0.24 → **0.51** (+0.28) |
| design_constraint | 0.51 → **0.69** (+0.18) |
| lane_arbitration | 0.27 → **0.36** (+0.09) |

### base "wins" 12 tasks — but mostly `content_overlap` grader = VERBOSITY-BIASED artifact, NOT a verdict
findings_interpretation, task_decomposition, tool_recommendation, parameter_extraction, workflow_generation,
out_of_catalog_composition, multi_workflow_chaining, dataset_prerequisite_check, autofix_repair, log_diagnosis,
clarification_request — these are graded by salient-token overlap, which favors the base's verbose output over
SFT's terse answers. **These tasks are currently UNMEASURABLE; the "base wins" is a grader artifact.**

## Conclusions (data-driven)
1. **SFT works where cleanly measured** — teaches skills the base lacks (bare-MCQA format → +0.38/+0.29). Real.
2. **Routing → base + retrieval** (0.947, clean). Do not fine-tune the base's strongest native skill.
3. **Mid-train: drop it.** mid500 knowledge_recall 0.30 ≈ base 0.28 (vs sft 0.66) — no usable knowledge injected;
   the full run was also impractical (142 s/step on L4 → 79 h projected).
4. **DPO: drop it as-is.** Learned the pairs (0.93 pref-acc) but zero eval generalization (macro 0.433→0.433).
5. **Generative tasks unmeasurable** until `content_overlap` is replaced with proper objective graders
   (RealBio score.py / Latch eval_graders style).

## Ship decision
**Hybrid**: base+retrieval for routing; **sft_v5 for the knowledge/QA/selection tasks** (knowledge_recall,
scientific_qa, model_selection, design_constraint, lane_arbitration). Do NOT ship mid-train or DPO.
Next: proper graders for the generative tasks → then re-judge SFT there (it may well win once terseness
isn't penalized). The literature-recipe + PMC-bulk work continues to enrich SFT data for those tasks.
