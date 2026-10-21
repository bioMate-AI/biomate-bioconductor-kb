# Cyclic-peptide LM — within-target "win" rigor check (PADI4)

**Date:** 2026-10-21 · Adversarial check of the claim `selector_AUC 0.959` (display-conditioned LM as a
within-target binder selector). Question: is it a real LM contribution over trivial baselines, or just
amino-acid composition + random-split leakage? CPU-only, no retraining; numbers traced to
`data/display/display_ngs_multitarget.csv.gz` and `cyclic_llm/cyclic_llm_selector.py`.

## 0. Correction to a prior claim
The result json's `AUC_raw_residue_sum = 0.9575` was mistaken (in conversation) for a trivial residue-sum
baseline. It is **not** — reading `cyclic_llm_selector.py`, it is the LM's **own raw (un-length-normalized)
LLR**; `selector_AUC 0.9592` is the same LM LLR length-normalized. **No independent trivial baseline existed
in the original result.** This check computes the missing baselines.

## 1. Does the LM beat trivial baselines? (same random 80/20 split, predict `is_binder`, n_test=4000, 67 binders)
| Scorer | AUC |
|---|---|
| **LM length-norm LLR** (json) | **0.9592** |
| LM raw-sum LLR (json) | 0.9575 |
| 2-mer logistic | 0.8870 |
| AA-composition logistic | 0.7814 |
| per-AA log-odds sum | 0.7728 |
| length only | 0.4049 |

**The LM genuinely beats the trivial baselines** — +0.07 AUC over a 2-mer logistic, +0.18 over
composition. The task is *substantially* (not fully) captured by k-mer composition; the LM adds a real,
modest margin on top.

## 2. Leakage diagnosis (split is `random.Random(0).shuffle` by sequence — NOT motif-clustered)
test-binder → nearest **train-binder** 3-mer Jaccard (n=67 test binders; 327 train binders):
| threshold | count | |
|---|---|---|
| exact seq in train | **0/67** | no exact duplicates |
| ≥ 0.9 | 0/67 (0%) | no near-duplicates |
| ≥ 0.8 | 0/67 (0%) | |
| ≥ 0.5 | 12/67 (18%) | moderate motif relatedness |
| ≥ 0.3 | 35/67 (52%) | median Jaccard 0.30 |

**Leakage is mild, not severe** — no exact or ≥0.8 near-duplicate test binders; most test binders are
motif-distinct from training (median 3-mer Jaccard 0.30).

## 3. Leakage-stratified baseline AUC (2-mer logistic; LM per-seq scores not stored → baseline only)
| subset | 2-mer baseline AUC | n_pos |
|---|---|---|
| LEAKY (sim ≥ 0.5) | 0.9931 | 12 |
| motif-DISTINCT (sim < 0.5) | **0.8638** | 55 |
| full test | 0.8870 | 67 |

The baseline retains **0.864** on motif-distinct binders (only ~0.02 below its full-set 0.887) → the
within-target signal is **genuine composition/biochemistry, not a leakage artifact**. Leakage inflates the
baseline by only ~0.02.

## 4. Verdict
**The within-target win survives scrutiny — it is real.** The LM beats trivial composition/k-mer baselines
by a meaningful margin (0.959 vs 0.887/0.781), and the signal is not a leakage artifact (no near-duplicate
test binders; baseline holds 0.864 on motif-distinct sequences). Genuine LM value-add over the best trivial
baseline ≈ **+0.07 AUC** on the full set.

**Caveats (honest):**
1. The LM's own leakage-robustness is **inferred, not directly measured** — per-sequence LM LLR scores are
   not stored, and re-scoring needs the model on GPU (out of scope here). I directly stratified only the
   2-mer baseline (small ~0.02 leakage inflation); the LM's motif-distinct AUC is *expected* ~0.93 by
   analogy but was not recomputed. To close this, re-score the motif-distinct subset with the trained LM.
2. The split is **random-by-sequence**, not motif-clustered. A cluster-held-out split is the cleaner design;
   the similarity-stratified analysis is the no-retrain approximation and shows leakage is mild here.
3. This is **within-target** only — orthogonal to the unsolved cross-target generalization (NULL/negative).
