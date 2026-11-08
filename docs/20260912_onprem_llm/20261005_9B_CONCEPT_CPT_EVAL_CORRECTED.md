# 9B concept-CPT works — the recorded eval was mis-scored by a grader bug (CORRECTED)

**Date:** 2026-10-05 · Supersedes the "data-gated, build the corpus next" conclusion in
`20261005_CPT_GATE1_2_VERIFIED_AND_NEXT.md` (that was wrong — see §4). Honesty: every number is
re-computed from the committed prediction strings in `s3://…/eval/med_today_20261003/{base,domainpro}.json`.

## 1. What already existed (I almost rebuilt it)
The concept-CPT pipeline the plan calls for is **already built and already ran**:
- Concept corpus + volume on S3: `background_corpus.jsonl` (22 MB seed), `pmc_concept_corpus.jsonl`
  (2.2 GB), and the concept-dominant CPT mix `midtrain_domain_concept_norm2.jsonl` (2.8 GB,
  **593,367,127 tokens**; composition: pmc_fulltext 166,724 + pmc_review 23,562 + db_tool 32,430 +
  db_workflow 20,785 + gtn 1,715 + openstax 795 + wikibook 8,180; bg_repeat 5).
- A **9B concept CPT+SFT candidate run** (2026-10-03, tag `_today_20261003`): Qwen3.5-9B, **300 CPT +
  500 SFT steps** (bounded — a *partial* pass of the 593M corpus, not a full epoch). Final artifacts on
  S3: `models_20260919/med/base_domain_today_20261003/` (merged CPT base) + `…/full_today_20261003_adapter/`
  (SFT). Paired MCQA eval auto-chained into `eval/med_today_20261003/`.

So the "critical remaining data step" from the CPT plan was already done. The real open question was the
**eval**, not the data.

## 2. The recorded eval artifact is mis-scored (do NOT cite its per_task)
`eval/med_today_20261003/domainpro.json` per_task reads knowledge_recall **0.018** / scientific_qa
**0.007** with **256/261 invalid_answers** — which looks like the concept-CPT *destroyed* the model.
It did not. Root cause: the grader `eval_today.py:answer()` used `re.fullmatch(r"...([A-E])...")`, so the
*entire* decoded string had to be a bare letter. The SFT model answers in **option-text format**
(`"D) Thyroid agenesis."`, `"B) FSH. FSH is an amine hormone."`) — a correct, well-formed choice whose
leading letter is right — but fullmatch scored every one as invalid. The base model happens to emit a bare
`"D"`, so it scored fine. **The artifact measured output format, not knowledge.**

## 3. Corrected result (fair extraction: leading option letter; base identical → fairness proof)
Re-scoring the committed predictions with a robust leading-option-letter extractor (exact letter, else
leading `letter[).:,]`; a bare letter followed by prose is still rejected). Base is **unchanged**, proving
the new extractor adds no false positives:

| task | base (orig 9B) | domainpro (concept-CPT + SFT) | Δ | invalid (both) |
|---|---|---|---|---|
| knowledge_recall | 0.679 (76/112) | **0.723 (81/112)** | **+4.4pp** | 0 |
| scientific_qa | 0.604 (90/149) | 0.604 (90/149) | 0 | 0 |
| **overall** | 0.636 (166/261) | **0.655 (171/261)** | **+1.9pp** | 0 |

**The concept-CPT+SFT improves domain knowledge recall by +4.4pp with no regression**, on a *bounded*
run. This is the user's stated goal ("grasp more domain background knowledge") and it is working.

## 4. Root-cause fix (shipped)
`evaluation/local_trial/eval_today.py:answer()` rewritten to accept both a bare letter and a leading
option-letter-with-text; comment documents the before/after. Verified on the committed predictions:
base 0.636→0.636 (0 invalid, unchanged), domainpro 0.011→0.655 (256 invalid → 0). This is a grader
*correctness* fix, not benchmark-fitting: it does not change base, and the model's answers were already
correct — only the extraction was wrong. **All future `eval_today.py` runs now score correctly.**

Correction to `20261005_CPT_GATE1_2_VERIFIED_AND_NEXT.md`: its "the next step is data, not GPU — build the
background corpus" conclusion was wrong. The corpus, mix, and a bounded 9B run already existed; the gap was
(a) the eval-grader bug (now fixed) and (b) a *fuller* CPT pass. The gate-1/2 verification in that doc
(recovery-run checkpoints real; SFT masking live) stands.

## 5. Honesty caveats (carry into any manuscript use)
- **Bounded run:** 300 CPT + 500 SFT steps is a partial pass, not a converged model. The +4.4pp is a
  lower bound on what a full pass could yield, not a final capability number.
- **Diagnostic scope:** open-book MCQA only (the artifact's own `scope` string) — NOT execution-task
  success, broad domain judgment, or client acceptance. The grounded workflow eval was prepared but
  `execution_status=NOT_RUN`.
- **Leakage filter is exact-stem only** (39 of 300 items dropped for <40-char stems or appearing verbatim
  in a training message) — not semantic or source-family certification.
- n=261 (112 knowledge_recall + 149 scientific_qa); no CIs computed here.

## 6. Next (capability lever, now measurable)
1. ✅ Grader fixed — the measurement is now trustworthy.
2. **Fuller 9B concept-CPT pass** (beyond 300 steps) on the existing 593M concept mix, re-eval with the
   fixed grader vs the fact-heavy mid500 null and this bounded run — the direction is positive, so this is
   the lever to size the real knowledge lift. GPU spend; recipe = `run_cpt_domainpro.sh` (pulls
   `midtrain_domain_concept_norm2.jsonl`, REPLAY_FRAC 0.3). Launch only with the fixed grader in place (done).
3. Then the 27B capacity-ceiling comparison (background grasp scales with capacity).
4. Reconcile source-family holdout for a leakage-clean claim before external use.
