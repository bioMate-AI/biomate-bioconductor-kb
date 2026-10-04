# RealBio: LLM alone vs LLM + harness (the system bar)

**Date:** 2026-10-04
**Ask:** LLM score and LLM+harness score on RealBio — the bar for LLM optimization.
**Primary metric (what we optimize for):** **LLM + harness (catalog / full-product mode)** — the number
the shipped system actually produces. The **bare** (LLM-alone) column is a *diagnostic* only: it shows how
much the harness contributes, but it is never the product's operating mode, so it does not gate decisions.
Every model is judged on its catalog/LLM+harness score.
**Source:** scored `results/<model>/<task>.jsonl` via the shared `score.py` (evaluation/datasets/public_export).
Routing has a `_bare` (LLM from own knowledge) vs `_catalog` (LLM given the retrieved candidate list =
the harness's retrieval layer) split — the cleanest LLM-vs-LLM+harness contrast. Other tasks are run
catalog-assisted; the full product harness (C2) is the 2026-08-17 leaderboard row.

## The three levels (routing, n=200)
| Model | LLM bare (own knowledge) | LLM + catalog (retrieval) | full BioMate harness (C2) |
|-------|-------------------------:|--------------------------:|--------------------------:|
| base Qwen3.5-9B | **0.18** | **0.815** | — |
| sft (our tuned 9B) | **0.285** | **0.805** | — |
| Claude Opus-5 (frontier) | 0.615 | 0.960 | — |
| **BioMate product (LLM mixture)** | — | — | **0.965** |

## Full per-task: base vs sft (our tuning), catalog-assisted
| Task (metric) | base (9B) | sft (9B) | Δ (sft−base) |
|---------------|----------:|---------:|:-----------:|
| routing — catalog (acc) | 0.815 | 0.805 | −0.010 |
| routing — bare (acc) | 0.18 | 0.285 | +0.105 |
| param_prefill (F1) | 0.664 | 0.657 | −0.007 |
| protocol_QC (acc) | 0.43 | 0.43 | 0.000 |
| autofix (cat-acc) | 0.87 | 0.85 | −0.020 |
| boin (MTD exact) | 0.778 | 0.778 | 0.000 |
| pbpk (within-2-fold) | 0.067 | 0.0 | −0.067 |
| drug_discovery (Spearman) | 0.70 | 0.70 | 0.000 |
| workflow_gen (acc) | 0.50 | 0.50 | 0.000 |
*(`qwen3.8-27b` excluded — predictions were `None`, a failed run, like the leaderboard's gpt-5.3 exclusion.)*

## Findings (the bar, answered)
1. **The harness is the differentiator, not the LLM.** Routing: the catalog/retrieval layer lifts the 9B
   from **0.18 → 0.815** (+63pp) and Opus from 0.615 → 0.960 (+35pp). Hand any LLM the harness's
   retrieved context and routing jumps into the high band.
2. **Our tuning (sft) gives no end-to-end advantage over base.** With the harness (catalog), sft ≈ base
   on every task (routing 0.805 vs 0.815; param 0.657 vs 0.664; autofix 0.85 vs 0.87; pbpk 0.0 vs 0.067
   — sft slightly *worse* on three, equal on four). The only place sft > base is **bare** routing
   (0.285 vs 0.18) — a mode the product never uses. **Net: the bounded SFT does not improve BioMate.**
3. **Model capacity still matters a little, even +harness, but tuning doesn't buy it.** Frontier+catalog
   (Opus 0.960) still beats 9B+catalog (~0.81) by ~15pp — so a *bigger/better* base helps; but *tuning a
   9B* (sft) did not close that gap. The gap is capacity, not domain-adaptation.
4. **LLM-direct tasks** (no catalog help): boin 0.778, dd 0.70 (both ≈ base), pbpk ~0, protocol 0.43 —
   tuning neutral here too.

## Bottom line
On RealBio, **LLM+harness ≫ LLM-alone** (the harness carries it), and **our tuned small model ≈ the
stock base end-to-end** — the bounded domain-adaptation adds nothing measurable to BioMate's score. This
is the definitive on-RealBio confirmation of the task-split thesis.

**Still pending — the decision row (LLM+harness only):** the **full-corpus** domain-pro (CPT 3000+1000
steps, TAG `_full_20261004`, on-demand box `i-042991001f74464a1`, training as of 2026-10-04 05:23 UTC on the
validated normalized concept mix). The row we add is its **catalog / LLM+harness** RealBio score across
routing + all tasks — NOT its bare score. The question it answers, in the metric that matters: *does much
more domain CPT lift the LLM+harness number above base's 0.815 (routing) and close the ~15pp gap to
frontier+catalog (0.96)?*
- If full-corpus catalog ≈ base catalog (≈0.81, like the bounded sft did): conclusion is firm — on-prem =
  cost/compliance play; use the best base the hardware allows + the harness; small-model domain-adaptation
  does not move the system bar.
- If full-corpus catalog materially exceeds base catalog: domain CPT *does* pay off end-to-end, and the
  recipe (full-corpus CPT, not bounded SFT) is the lever worth scaling.

**Eval procedure for the pending row (so it is apples-to-apples on LLM+harness):** when CPT+SFT finish,
serve `base_domain_full_20261004` (the CPT-merged base) + the `full_full_20261004` SFT adapter at an
OpenAI-compatible endpoint, point the RealBio **catalog** runner at it (same retrieval layer as base/sft),
score with `score.py`, add the catalog column. The bare column is optional diagnostic, run only if cheap.
