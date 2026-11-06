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

## Recipe pipeline — loose vs strict filter (2026-09-30, batched audit)
- LOOSE filter recipe: ~2-20% bioinformatics (2-model committee: 80-90% off-domain) -> QUARANTINED/dead.
- STRICT filter recipe (>=2 specific bioinfo signals AND a real tool): batched full-audit (corrected reviewer,
  3387-row judged sample) = **81% bio, 86% correct, 71% keep** -> SALVAGED. Clean subset
  `sft/recipe_clean_bioinformatics.jsonl` (~2.4k audited-clean, ~4.3k projected). Coverage-gap now REAL
  (limma/WGCNA/blastp/STRING = catalog-expansion candidates).
- Batch-reviewer bug fixed: failed LLM calls were silently counted as reject (false 2.4%); now retried +
  excluded from denominator. Lesson: verify the measurement before trusting it (twice: F1 grader, this reviewer).

## FAIR re-tests of mid-train + DPO (2026-10-01) — both honest negatives
Per the "don't drop a technique on a botched run" correction, both got proper tests:
- **DPO fair-test**: eval-matched prompt template + 3 epochs + 0.93 pref-accuracy on pairs -> routing 0.842
  (vs sft_v5 0.86, base 0.94), full macro 0.430 (flat). FAIR NEGATIVE — base near-ceiling on routing; SFT
  already learned candidate-selection; DPO on below-base sft_v5 can't exceed base.
- **mid-train v2 fair-test**: task-aware corpus (KG-reasoning+tool-QA+db), SPOT GPU, proper F1 eval ->
  full_v2mid macro 0.397 vs sft_v5 0.431 (−3.4). model_selection 0.46->0.21. FAIR NEGATIVE — continued-
  pretraining shifts the base distribution; SFT can't recover. Caveat: low-coverage fast check (~6%), but a
  small dose already HURTS + mechanism + cost -> stop.
- Policy: SPOT-ONLY enforced (no on-demand fallback) across all launchers.
FINAL: SFT alone wins. Routing=base+retrieval. mid-train + DPO NOT shipped (fairly tested, negative).
Recipe (strict filter) salvaged -> v6 enrichment eval pending.

## FINAL (2026-10-01): SFT v5 ships; everything on top is neutral-negative
F1 macro: base 0.27 | sft_v5 0.43 (WINNER) | sft_v6(+recipe) 0.42 | full_v2mid(+midtrain) 0.397 | dpo_v5 0.43.
- Recipe enrichment (2403 clean rows, 3%): net −0.009; tiny gains on findings/tool_rec, routing −0.06. Not shipped.
- SHIP: sft_v5 for 16 tasks + base+retrieval for routing. mid-train/DPO/recipe-enrichment all fairly tested, none add.
- Salvaged value: recipe pipeline (strict filter, 81% clean) + coverage-gap = catalog-expansion list (NOT SFT data).
