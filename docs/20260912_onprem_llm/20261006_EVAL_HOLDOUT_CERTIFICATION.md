# On-prem 9B — eval-holdout leakage certification (source-family / paraphrase)

**Date:** 2026-10-06 · **Author:** Yaoyun Zhang (CPU-only data analysis)
**Scope:** Certify (or refute) that the on-prem 9B's training data is leakage-clean against the
frozen 261-item MCQA diagnostic used for the `+5.4pp` knowledge_recall headline
(`20261006_FULLER_CPT_EVAL_RESULTS.md`). This closes the gap flagged there and in
`20261003_SAME_DAY_TRAINING.md` / `20261003_CPT_RECOVERY_AND_TAKEOVER.md`:
the prior filter was an **exact-stem** drop (39 of 300) run against a *different*
training export — **not** a source-family or paraphrase audit against the actual
concept-SFT / CPT corpora.

## TL;DR verdict

| Check | Target corpus | Verdict | Real count |
|---|---|---|---|
| 1. Exact-match (stem verbatim in train) | concept-SFT (72,397) | **MINOR-OVERLAP** | **5 / 261** (1.9%), all `medmcqa` |
| 1. Exact-match | CPT concept mix (sampled) | **CLEAN (sampled)** | **0** in ~550 MB (~11% of concept + pmc_concept) + full background |
| 2. Near-duplicate / paraphrase | concept-SFT | **MINOR-OVERLAP** | **7 / 261** (2.7%) genuine item-leaks at token-Jaccard ≥0.8; remainder are template collisions |
| 3. Source-family holdout | concept-SFT vs eval | **CONTAMINATED (family level)** | eval MCQA families (MedMCQA/MedQA/SciQ/PubMedQA) are **all present** in SFT (26,992 rows); **no held-out split**; eval has **no provenance metadata** |
| 3. Source-family | CPT concept mix | **CLEAN (by source)** | CPT sources = PMC/DB/textbook only; no MCQA family; 0 stem hits in sample |

**Headline — is the +5.4pp defensible as leakage-controlled?** **Qualified YES.**
The gain is **not** an artifact of item leakage: it survives removal of every
overlapping item (**+3.8pp** on the exact/near-dup-free subset; **+5.7pp** on the
token-Jaccard<0.6 subset), and only **1 of the net +6 knowledge_recall items** lands on a
demonstrably-leaked base-wrong→domainpro-right flip. **However**, the eval is **not**
source-family-held-out from the SFT set (the same MedMCQA/MedQA/SciQ/PubMedQA pools feed
both), so the *absolute* scores reflect in-distribution familiarity and the holdout the
docs asked for is **not certified**.

---

## Data audited (pulled from S3, real SHA/row counts)

Bucket `s3://biomate-models-399683337364/biomate-core-local-trial/20260912`.

| Artifact | Path | Rows / size | Used for |
|---|---|---|---|
| Frozen eval | `eval/med_today_20261003/openbook.jsonl` | 261 rows (knowledge_recall 112, scientific_qa 149; grader `mcqa`) | target |
| Eval parent | `eval/objective_eval.jsonl` | 300 mcqa items (150+150), **no `source` field** | provenance |
| concept-SFT | `sft/multitask_sft_concept.jsonl` | 72,397 rows (sha `30c34f…d4ef`) | train (SFT) |
| CPT concept | `midtrain_corpus/midtrain_domain_concept_norm2.jsonl` | 2.8 GB — **sampled ~300 MB / 24,813 docs** | train (CPT) |
| CPT pmc | `midtrain_corpus/pmc_concept_corpus.jsonl` | 2.3 GB — **sampled ~250 MB / 20,566 docs** | train (CPT) |
| CPT background | `midtrain_corpus/background_corpus.jsonl` | 12,956 docs — **full** | train (CPT) |
| Headline preds | `eval/spot_fuller_20261006_024755/{domainpro,cpt1200}_constrained.json` | 261×2 arms | impact analysis |

Method: normalize = lowercase + strip punctuation + collapse whitespace. "Stem" = eval
prompt truncated before the first `A)…E)` option marker. All counts below are measured, not
estimated.

---

## Check 1 — Exact-match

**concept-SFT:** 5 eval stems appear **verbatim** (normalized) inside an SFT user message —
all sourced from `medmcqa`, task `knowledge_recall`:

| eval idx | stem | eval gold | SFT answer |
|---|---|---|---|
| 16 | "all can occur due to blunt trauma of eye except" | C | C) Sympathetic ophthalmitis ✓ |
| 46 | "best indicator for nutritional status for a child is" | C | C) Rate of increase of height and weight ✓ |
| 75 | "anaesthetic agent with vasoconstrictor is contraindicated in" | A | A) Digital block ✓ |
| 92 | "one of the following features can be used to define contracted pelvis" | A | A) Transverse diameter of inlet is 10 cm ✓ |
| 106 | "assessment of obesity by following measurement except" | D (Sullivan's index) | C) Sullivan's index — **same content, shuffled letter** |

4 of 5 carry the matching gold-answer *content*; the 5th (ev#106) is the same question with
a shuffled option order (gold content "Sullivan's index" still taught). These are all **>40
chars**, so the prior exact-stem filter *should* have dropped them — confirming that filter
ran against a different training file and **never touched `multitask_sft_concept.jsonl`.**

**CPT concept mix (sampled):** **0** eval-stem hits across ~300 MB of `midtrain_domain_concept_norm2`
+ ~250 MB of `pmc_concept_corpus` + the full `background_corpus`. Consistent with CPT sources
containing no MCQA corpus.

Verdict: **MINOR-OVERLAP (SFT 5/261 = 1.9%); CLEAN on the CPT sample.**

## Check 2 — Near-duplicate / paraphrase (token-Jaccard, stem-vs-stem)

Max token-Jaccard of each eval stem against all 72,397 SFT stems (inverted-index candidate
generation, exact Jaccard scoring):

| threshold | eval items ≥ thr |
|---|---|
| ≥1.0 | 5 |
| ≥0.9 | 6 |
| ≥0.8 | 11 |
| ≥0.7 | 14 |
| ≥0.6 | 27 |
| ≥0.5 | 43 |

median max-sim = 0.30, mean = 0.36.

Manual classification of the 11 items at ≥0.8:
- **7 genuine item-leaks** — exact stem, or same clinical vignette with the eval gold-answer
  *content* reproduced in the SFT answer (ev#4, 16, 46, 75, 92, 106 `knowledge_recall`;
  ev#218 `scientific_qa` "52-yo diabetes follow-up → 129 mg/dL", letter C matches).
- **~4 template collisions (NOT leaks)** — MedMCQA's stock phrasing ("all of the following
  are features of X except") collides lexically while the content differs: ev#44 *pyle* vs
  *wilson's* disease, ev#223 34-yo vs 19-yo GERD (different answer), etc. High Jaccard, no
  shared answer.

So the honest paraphrase-leak count is **7/261 (2.7%)**, not 11. No eval item exceeded 0.9
against a *different*-content SFT row.

Verdict: **MINOR-OVERLAP (7/261).** *Uncertified:* semantic paraphrase with <0.5 token
overlap (reworded facts) is invisible to lexical Jaccard; and the CPT paraphrase surface was
only exact-window-scanned on ~11% of the two large concept files.

## Check 3 — Source-family holdout (the specific flagged gap)

The eval set (`knowledge_recall` + `scientific_qa`, grader `mcqa`) derives from
`objective_eval.jsonl` (300 mcqa → 261 after the exact-stem drop). **That artifact carries no
`source`/`source_family` field** — provenance can only be established by content signature.

Content signature (verified by the exact/near-dup hits above and by inspection):
- `knowledge_recall` = **MedMCQA / AIIMS-style** medical MCQ (e.g. "Contraceptive of choice in
  a woman with Rheumatic heart disease"; "Bifurcation of trachea is at…").
- `scientific_qa` = **USMLE/MedQA-style** clinical vignettes + **PubMedQA** yes/no items.

The concept-SFT set explicitly labels these **same families** (from
`20261003_CONCEPT_SFT_STRUCTURAL_AUDIT.json` and re-verified in the file's `source` field):

| SFT `source` | rows | SFT `task` | eval family it feeds |
|---|---|---|---|
| `medmcqa` | 8,000 | knowledge_recall | eval knowledge_recall |
| `sciq` | 7,995 | knowledge_recall | eval knowledge_recall |
| `medqa` | 7,997 | scientific_qa | eval scientific_qa |
| `pubmedqa` | 1,000 | scientific_qa | eval scientific_qa |

**26,992 SFT rows are drawn from the identical source pools as the eval.** There is no
documented train/test split by item id between `objective_eval.jsonl` and these SFT shards;
the observed 5 exact + 7 near-dup item collisions are the direct evidence that the two were
sampled from one undivided MedMCQA/MedQA/SciQ/PubMedQA pool. **The eval is therefore NOT
source-family-held-out from the SFT training data.**

CPT concept mix sources (`pmc_fulltext` 166,724, `pmc_review` 23,562, `db_tool` 32,430,
`db_workflow` 20,785, `db_cryoem*`, `gtn`, `openstax`, `wikibook` — from
`midtrain_domain_concept.composition.json`) contain **no** MCQA family; the PMC evidence
*excerpts* the open-book prompts retrieve do overlap PMC content by design, which is
retrieval grounding, not answer leakage.

Verdict: **CONTAMINATED at the source-family level for SFT** (same corpora, no holdout, no
provenance metadata to prove otherwise). **CLEAN by source for CPT.**

---

## Impact on the +5.4pp headline (decisive per-item analysis)

From the fuller-run constrained predictions (`spot_fuller_20261006_024755/domainpro_constrained.json`;
arm `base` vs the domainpro arm — the file keys that arm `cpt800`, a stale template name, but
its scores 0.723 / 0.617 / 0.663 match the `domainpro (constrained)` headline row exactly;
flagged under honesty below). Net **knowledge_recall gain = +6 items** (0.670 → 0.723,
= +5.4pp; 11 base-wrong→right, 5 base-right→wrong).

Gain decomposed by eval-item train-overlap (max stem-Jaccard vs SFT):

| overlap bucket | n | base ✓ | domainpro ✓ | net | wrong→right |
|---|---|---|---|---|---|
| HIGH ≥0.8 (leak-suspect) | 8 | 4 | 6 | **+2** | 2 |
| MID 0.6–0.8 (mostly template collisions) | 16 | 10 | 9 | **−1** | 0 |
| LOW <0.6 (clean) | 88 | 61 | 66 | **+5** | 9 |
| **total** | 112 | 71→75 | | **+6** | 11 |

- Of the 7 genuine leaked items, **only 1** (ev#16) actually flipped base-wrong→domainpro-right.
  The rest were already correct in base (leakage bought nothing measurable) or wrong in both.
- **Leakage-controlled re-scores:**
  - Drop the 8 HIGH-overlap items → 104 clean knowledge_recall items: base 0.683 →
    domainpro 0.721 = **+3.8pp** (still positive).
  - Drop everything ≥0.6 → 88 LOW-overlap items: base 0.693 → domainpro 0.750 = **+5.7pp**.

The bulk of the gain (**+5 of +6 net, 9 of 11 flips**) is on LOW-overlap items absent from the
training data — a genuine domain-knowledge gain, not memorized test items.

---

## Honest limitations / what remains uncertified

1. **CPT is only sampled (~11%).** Exact-stem scan covered ~300 MB of 2.8 GB
   `midtrain_domain_concept_norm2` + ~250 MB of 2.3 GB `pmc_concept` + full `background`.
   0 hits there, but **paraphrase/near-dup leakage in the unscanned ~89%** is uncertified. Given
   CPT sources contain no MCQA corpus, exact MCQA-item leakage is improbable, but not proven.
2. **Lexical methods miss semantic paraphrase.** Token-Jaccard cannot catch a fact reworded
   below ~0.5 token overlap. A full embedding-based semantic audit of 27k MCQA SFT rows vs the
   261 eval items was **not** run (CPU-only, scope).
3. **No provenance metadata anywhere.** Neither `objective_eval.jsonl` nor the SFT rows carry a
   `source_family`/item-id split manifest, so family isolation cannot be *certified* — only
   refuted (which it is, by the content collisions). Absence of metadata ≠ absence of leakage.
4. **Artifact-hygiene flag:** the prediction file named `domainpro_constrained.json` labels its
   second arm `cpt800` and its `adapter` field reads `cpt ckpt-800`, conflicting with the
   `20261006` doc's "domainpro = CPT-1200 + SFT" description. Scores match the domainpro row, so
   I treat it as domainpro, but the run's internal naming should be reconciled before external use.
5. **Scope:** open-book MCQA diagnostic only (n=261, no CIs); not execution-task success.

## Recommended fixes (root-cause, per CLAUDE.md)

1. **Re-run the exact-stem + near-dup filter against `multitask_sft_concept.jsonl` itself** (not
   the old conversation-format export) and drop the 5 exact + 7 near-dup colliding items from
   SFT, or hold them out of eval. This closes item leakage deterministically.
2. **Add an item-id split manifest** between `objective_eval.jsonl` and the MedMCQA/MedQA/SciQ/
   PubMedQA SFT shards so source-family holdout is *certifiable*, not inferred.
3. **Report the leakage-controlled delta (+3.8pp on the dedup subset)** alongside the raw
   +5.4pp for any external claim, and state plainly that absolute scores are in-distribution.
</content>
