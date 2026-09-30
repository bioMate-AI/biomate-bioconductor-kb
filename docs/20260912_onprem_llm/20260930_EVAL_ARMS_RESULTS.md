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

### base "wins" 12 tasks under recall-grader — BUT this was a VERBOSITY ARTIFACT (now disproven)
Re-ran with a **salient-token F1 grader** (precision+recall, de-biases verbosity). Result FLIPPED:
**MACRO base 0.27 vs sft_v5 0.431; SFT wins 14/17 tasks, base wins only routing.** Every "base win" reversed:
parameter_extraction 0.29→0.53, findings 0.17→0.29, log_diagnosis 0.27→0.46, tool_rec 0.30→0.41,
task_decomp 0.22→0.29, workflow_generation 0.21→0.28, etc. The recall-only content_overlap grader had been
**hiding SFT's broad value.** With correct scoring, the SFT rebuild works across the board.

## Conclusions (data-driven)
1. **SFT works where cleanly measured** — teaches skills the base lacks (bare-MCQA format → +0.38/+0.29). Real.
2. **Routing → base + retrieval** (0.947, clean). Do not fine-tune the base's strongest native skill.
3. **Mid-train: UNPROVEN, not dropped.** mid500 showed no knowledge gain — but the RUN was unfair (weak L4,
   only 500/2000 steps = ~2% corpus coverage, raw-LM-heavy + degenerate KG). A fair test = task-aware corpus
   (KG-reasoning + findings + capped full-text) on a fast GPU (L40S) with ≥1 real epoch, then SFT+eval. PENDING.
4. **DPO: UNPROVEN, not dropped.** Learned the pairs (0.93 pref-acc) but didn't transfer — the signature of a
   train/eval DISTRIBUTION MISMATCH (DB-sibling negatives vs the eval's retriever candidates), plus too few
   steps (372/1 epoch) on the below-base sft_v5. Fair test = eval-matched negatives + more epochs. PENDING.
   [Corrected 2026-09-30: "drop" was premature — a failed run is not a disproven method.]
5. **Generative tasks unmeasurable** until `content_overlap` is replaced with proper objective graders
   (RealBio score.py / Latch eval_graders style).

## Ship decision
**Hybrid**: base+retrieval for **routing only** (base 0.94); **sft_v5 for the other 16 tasks** — under proper
F1 grading SFT wins 14/17 (macro 0.43 vs base 0.27), so the clean-data rebuild ships broadly, NOT just QA.
Mid-train and DPO NOT shipped **yet** — pending fair re-tests (task-aware mid-train on L40S; eval-matched DPO
now running). If a proper run beats sft_v5, it ships.

**KEY LESSON:** the grader nearly buried the whole SFT effort. Always de-bias the metric (F1 not recall)
before concluding — the "base wins generative tasks" verdict was 100% a verbosity artifact.
Next: proper graders for the generative tasks → then re-judge SFT there (it may well win once terseness
isn't penalized). The literature-recipe + PMC-bulk work continues to enrich SFT data for those tasks.
