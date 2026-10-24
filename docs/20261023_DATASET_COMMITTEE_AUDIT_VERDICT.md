# Training-data committee audit — verdict (gate before RL)

**Date:** 2026-10-23 · **Auditor:** row-level committee of top LLMs via OpenRouter
(`evaluation/local_trial/audit_committee_dataset.py`): claude-opus-5.5, gpt-6.1-sol,
gemini-3.1-pro-preview (deepseek-v4-pro returned non-JSON — excluded). Each model judged 20 sampled
rows/dataset against strict per-row rubrics (query realism, gold correctness, negative validity,
restraint). Triggered by the directive to **audit design + quality before spending GPU**.

## Verdict (2 rounds: initial → after fixes)

| Dataset | query_realistic / chosen_correct | negative_valid | Verdict |
|---|---|---|---|
| Param (2,741) | gold_sensible **1.0**, restraint **0.95** | — | **CLEAN — train-ready** |
| Routing **nf-core** subset (~1,811) | real task descriptions ("Antibody-based protein-DNA profiling (ChIP-seq)") | — | **CLEAN — train-ready** |
| Routing **Bioconductor** subset (~7,337) | **0.15–0.20** — package-name / internal-id "descriptions", no task stated | — | **NOT train-ready** |
| DPO routing-confusable (4,058) | chosen **1.0** | **0.30–0.85** (disputed) | partial — dedup fixed, negatives still mixed |
| DPO exec-grounded (1,833) | chosen **0.6–0.7** | **0.25–0.30** | WEAK — noisy domain/IO labels, some rejected also-valid |

## What the audit caught + fixed

1. **69% of routing queries were raw param-schema dumps** ("Looking for a pipeline to -
   key_parameters: study.name=…") — many Bioconductor workflows store a param template in
   description/annotation_v2. The ORIGINAL 9.4k had the same latent leak; scaling amplified it.
   **Fixed:** `_is_prose` guard → 0% leak. But it exposed the deeper issue below.
2. **The deeper issue (not fully fixable by filtering):** even non-dump Bioconductor descriptions are
   *package names / identifiers* ("a4"), not task prose → routing queries from them stay unrealistic
   (0.15–0.20). Only the **nf-core** workflows (~1,811) have genuine task descriptions.
3. **DPO path-variant duplicates** ("rejected is the same subworkflow, different path") — **fixed**
   with a `_stem()` identity (drops path-prefix variants); require a shared-tool negative (dropped
   the random fallback the committee flagged as too-easy).
4. **Exec-grounded pairs** carry noisy domain labels (e.g. a mass-spec tool labelled epigenomics) and
   some rejected are actually valid alternatives → low-tier; keep small or drop.

## Honest train-ready core vs. the gap

- **Train-ready now (committee-clean): ~4.5k** = param (2,741) + nf-core routing (~1,811) + the
  shared-tool DPO pairs whose queries come from that clean subset.
- **The gap (the real "volume" the DB can't give for free): ~7.3k Bioconductor subworkflows** have no
  usable task description, so they can't yield realistic routing/DPO data by text-mining alone.

## Required proper fix for quality-at-scale (the leverage)

Generate a **realistic one-line task description for each description-poor workflow** with a top LLM
(input = workflow name + tools_used + params_schema + domain; output = a natural task sentence),
persist it to the catalog, then regenerate routing/DPO from those and **re-audit**. This converts the
7.3k package-name workflows into clean training signal — the right way to use "a big system with many
resources" for volume WITHOUT the quality defect. It is an LLM-generation pass (cost + a third
committee round), not free text-mining.

## Recommendation

- **Do NOT train routing/DPO on the Bioconductor subset as-is** (committee-gated).
- **Option A:** train now on the committee-clean ~4.5k core (param + nf-core routing + its DPO pairs).
- **Option B (recommended for scale):** run the LLM-description-generation pass over the ~7.3k
  description-poor workflows, regenerate, re-audit → then train on a large *clean* corpus.
