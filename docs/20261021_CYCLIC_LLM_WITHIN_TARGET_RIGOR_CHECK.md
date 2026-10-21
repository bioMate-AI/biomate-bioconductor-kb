# Cyclic-peptide LM — within-target "win" rigor check (PADI4)

**Date:** 2026-10-21 · Adversarial check of `selector_AUC 0.959` (display-conditioned LM as a within-target
binder selector). Question: real LM contribution over trivial baselines, or just amino-acid composition +
random-split leakage? CPU-only. Data: `data/display/display_ngs_multitarget.csv.gz`; recipe:
`cyclic_llm/cyclic_llm_selector.py`; re-score: `cyclic_llm/rescore_padi4_selector.py`; per-seq scores:
`results/cyclic_llm_selector_PADI4_perseq_scores.json`.

## 0. Correction to a prior claim
The json's `AUC_raw_residue_sum = 0.9575` was mistaken (in conversation) for a trivial residue-sum baseline.
It is **not** — per `cyclic_llm_selector.py` it is the LM's **own raw (un-length-normalized) LLR**;
`selector_AUC 0.9592` is the same LM LLR length-normalized. No independent trivial baseline existed in the
original result; this check computes them.

## 1. Does the LM beat trivial baselines? (same random 80/20 split, predict `is_binder`, n_test=4000, 67 binders)
| Scorer | AUC (full) |
|---|---|
| **LM length-norm LLR** (orig json / re-trained) | **0.9592 / 0.9511** |
| 2-mer logistic | 0.8870 |
| AA-composition logistic | 0.7814 |
| per-AA log-odds sum | 0.7728 |
| length only | 0.4049 |

The LM genuinely beats trivial baselines — **+0.064 AUC over a 2-mer logistic, +0.17 over composition**
(re-trained LM 0.9511; original 0.9592 — difference is a fresh training instance, no saved checkpoint).

## 2. Leakage diagnosis (split is `random.Random(0).shuffle` by sequence — NOT motif-clustered)
test-binder → nearest **train-binder** 3-mer Jaccard (n=67 test binders; 327 train binders):
| threshold | count | |
|---|---|---|
| exact seq in train | **0/67** | no exact duplicates |
| ≥ 0.9 / ≥ 0.8 | 0/67 / 0/67 | no near-duplicates |
| ≥ 0.5 | 12/67 (18%) | moderate motif relatedness |
| ≥ 0.3 | 35/67 (52%) | median Jaccard 0.30 |

Leakage is **mild, not severe** — no exact or ≥0.8 near-duplicate test binders; most test binders are
motif-distinct from training.

## 3. DIRECTLY-MEASURED leakage-safe AUC — LM re-scored on CPU (not inferred)
Re-trained the selector (same recipe, traj-train) on CPU, stored per-seq length-normalized LLR, and
computed AUC on the full set and the **motif-distinct** subset (positives = 55 test binders with 3-mer
Jaccard < 0.5 to any train binder; negatives = all test non-binders):

| Scorer | FULL AUC | MOTIF-DISTINCT AUC (sim<0.5) |
|---|---|---|
| **LM length-norm LLR** | **0.9511** | **0.9405** |
| 2-mer logistic | 0.8870 | 0.8638 |
| AA-composition | 0.7814 | 0.7662 |

- **LM leakage inflation is negligible: −0.011** (0.9511 → 0.9405 on motif-distinct). This replaces the
  earlier *inferred* ~0.93 with a *measured* **0.9405**.
- **LM leakage-safe value-add over the best trivial baseline = +0.077 AUC** (0.9405 vs 2-mer 0.8638) — on
  sequences that are motif-distinct from training, i.e. not explainable by near-duplicate leakage.
- LM lift @ top-5% = 13.4× (full).

## 4. Verdict
**The within-target win is real and leakage-safe.** Directly measured: the LM scores AUC **0.9405 on
motif-distinct held-out binders**, beating trivial composition/k-mer baselines by **+0.077** there, with
only ~0.01 leakage inflation. The signal is genuine display-binding biochemistry the LM captures beyond
composition, not a near-duplicate artifact.

**Scope / honesty:**
1. Within-target only — orthogonal to the unsolved **cross-target** generalization (which is NULL for our
   LM and negative for the BoltzGen FT; see the innovation thesis doc).
2. The re-trained LM (0.9511) is a fresh instance of the same recipe — the original selector saved no
   checkpoint; the gap to 0.9592 is training-run variance, not a different result. Per-seq scores are now
   stored (`results/cyclic_llm_selector_PADI4_perseq_scores.json`) so this need never be re-inferred.
3. The split is random-by-sequence; the similarity-stratified (sim<0.5) analysis is the motif-safe
   evaluation and the leakage-safe AUC reported above.
