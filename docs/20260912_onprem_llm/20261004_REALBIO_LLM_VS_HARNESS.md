# RealBio: LLM alone vs LLM + harness (the system bar)

**Date:** 2026-10-04
**Ask:** LLM score and LLM+harness score on RealBio — the bar for LLM optimization.
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

**Still pending:** the **full-corpus** domain-pro (CPT 3000+1000 steps, training now, TAG `_full_20261004`)
— the test of whether *much more* domain CPT (vs the bounded sft) can close the ~15pp capacity gap to
frontier+catalog. If it too lands ≈ base, the conclusion is firm: on-prem = cost/compliance play, use the
best base the hardware allows + the harness; don't expect domain-adaptation of a small model to move the
system bar.
