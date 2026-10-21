# DeepSeek Benchmark Coverage Audit (LLM and LLM+harness)

**Date:** 2026-10-21
**Question:** Is DeepSeek carefully/comprehensively evaluated in our benchmarks — including
the LLM+harness configuration, and the latest large + small versions?
**Short answer:** Partially. The large model has a clean full RealBio sweep and a
bare-vs-harness split for routing; but the roster slug was stale, the small model is on
only two niche benchmarks, the bare-vs-harness comparison is not systematic, and the new
DrugDev decision suite has no DeepSeek results yet.

## 1. What IS covered (verified from result files)

**`deepseek-v4-pro` (LARGE flagship)** — full, clean RealBio 8-task sweep in
`evaluation/datasets/public_export/results/deepseek_deepseek-v4-pro/` (autofix 100, boin 20,
cross_domain_routing 200×{bare,catalog}, drug_discovery_e2e 15, param_prefill 170, pbpk 15,
protocol_thresholds 100, workflow_generation 40; ~0 errors). On the main leaderboard as
**"DeepSeek V4"**: routing 0.415 · autofix 0.800 · param_prefill_F1 0.621 · workflow_gen 0.500
· protocol_QC 0.420 · pbpk_2fold 0.067 · boin_mtd 0.167 · dd_spearman 0.667.

**LLM+harness signal that exists:**
- `cross_domain_routing_bare.jsonl` vs `cross_domain_routing_catalog.jsonl` (bare LLM vs
  catalog/harness-augmented routing) — for deepseek-v4-pro.
- `bioc_method_selection`: `_bare` vs `_kb` (KB/harness-augmented) for **both**
  `deepseek-v4-pro` AND `deepseek-v4.1-flash`.

## 2. Gaps (why it is NOT yet comprehensive)

1. **Roster slug was stale.** `models.yaml` listed `deepseek/deepseek-v4` (UNVERIFIED_SLUG,
   zero results); the real completed runs use `deepseek-v4-pro` and `deepseek-v4.1-flash`.
   → **FIXED this session:** roster now lists both proven slugs (`verified_by_results`).
   A fresh sweep on the old slug would have run the wrong/nonexistent model.
2. **Small model not comprehensive.** `deepseek-v4.1-flash` appears only in
   `bioc_method_selection` + `nextflow_coding`. It is **absent from the main RealBio 8-task
   leaderboard** and every other benchmark. "Latest large + small" is only half-done.
3. **LLM+harness comparison is not systematic.** Bare-vs-harness (`_bare` vs `_kb`/`_catalog`)
   exists only for routing + bioc_method_selection, **not across the full RealBio suite** and
   **not for the DrugDev decision suite**. So "performance of LLM+harness" for DeepSeek is
   spotty, not a clean matrix.
4. **DrugDev decision suite: no DeepSeek (or any model) results.** The 9 new decision
   archetypes (`decision_benchmark`, 30 tasks) are brand-new and have never been swept.

## 3. Plan to make it comprehensive (GATED — live OpenRouter sweep, costs budget)

Target matrix = **{deepseek-v4-pro, deepseek-v4.1-flash} × {bare, +harness} × {RealBio 8
tasks + DrugDev decision suite}**.

1. **Verify the two slugs** against the live list (`run_all.py --list-provider-models`) and
   confirm these are the current latest large + small (the `verified_by_results` status is
   evidence-by-use; the OpenRouter-list confirmation is still pending — needs web/API budget,
   exhausted this session).
2. **Sweep `deepseek-v4.1-flash` on the full RealBio 8-task suite** (it is missing) so the
   small model sits on the main leaderboard next to the large one.
3. **Add a systematic bare-vs-harness pass** for both DeepSeek models across the tasks where
   the harness carries real lift (routing/selection/param — per the harness-task-split
   design), not just the two benchmarks that have it today.
4. **Add the DrugDev decision suite to the sweep roster** so both DeepSeek models get scored
   on the 9 practical archetypes (`run_decision_benchmark.py` already iterates
   `DECISION_DATASETS`; it needs the model roster wired in + a live BioMate endpoint).

None of this is run speculatively — it is a real API/compute spend and needs the correct
confirmed slug first.

## 4. Done this session (offline)

- Corrected `models.yaml`: replaced the stale `deepseek-v4 (UNVERIFIED_SLUG)` with
  `deepseek-v4-pro` + `deepseek-v4.1-flash` (`verified_by_results`), with inline notes on the
  large/small split and the small-model leaderboard gap.
- This audit doc.

See `project_drugdev_benchmark_series`, `project_biomni_realbio_run`,
`project_llm_harness_task_split`, `project_kb_dividend_finding`.
