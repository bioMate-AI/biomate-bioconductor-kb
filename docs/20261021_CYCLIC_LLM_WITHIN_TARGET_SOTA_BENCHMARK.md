# Cyclic-peptide LM — within-target selector: SOTA / success-rate benchmark

**Date:** 2026-10-21 · The user set the bar: a within-target "win" is only acceptable if it is **SOTA or
high success rate**, not merely beating our internal baselines. This benchmarks our display-NGS binder
selector (LM length-normalized LLR) honestly against (a) an **abundance/enrichment null**, (b) a trivial
sequence baseline, and (c) the external SOTA for ML-on-display binder prediction.

**Verdict up front: the within-target LLM "win" does NOT survive benchmarking.** It is not SOTA and not a
high-success selector. Two findings kill it:
1. The eval is **near-circular**: `is_binder` is essentially a threshold on display `enrichment_log2fc`, so a
   trivial **read-count / enrichment sort scores AUC ≈ 1.0 on all four targets** — the "trivial null" beats
   the LM everywhere.
2. The sequence-only LM is **erratic and below the null on every target** (AUC 0.266–0.997), including
   **below chance on hPCSK9 (0.266)**.

## 1. The decisive result — abundance/enrichment null (same motif-distinct eval set)

| target | n (motif-distinct) | binders | **LM AUC** | **count-null AUC** | **enrichment-null AUC** |
|---|---|---|---|---|---|
| PADI4 | 3988 | 55 | 0.941 | **1.000** | **1.000** |
| Abeta42 | 3691 | 37 | 0.997 | **0.999** | **1.000** |
| hIAPP | 3919 | 128 | 0.588 | **1.000** | **1.000** |
| hPCSK9 | 2734 | 134 | 0.266 | **0.867** | **0.997** |

`is_binder` is derived from enrichment (`enrichment_log2fc`), which is recorded for every test sequence, so
sorting the test set by its own read count / enrichment trivially recovers the label (AUC ≈ 1.0). **The LM
does not beat this null on any target — it is worse on all four.** This is the degree/abundance-null failure
mode we warned about: the within-target eval largely measures "can a sequence model re-derive an
abundance-defined label," and even at that the LM is unreliable.

(Caveat, stated fairly: the abundance null is only available for *displayed* sequences. The deployable use
of a selector is scoring *novel* sequences with no read count — but this held-out-display eval does **not**
test that use; its test sequences are display sequences with counts. So the eval neither beats the trivial
null nor demonstrates the deployable capability.)

## 2. LM per-target metrics (motif-distinct, leakage-safe; score = length-normalized LLR)

| target | AUC | AUPRC | top-5% precision (recall) | top-1% precision |
|---|---|---|---|---|
| PADI4 | 0.941 | 0.337 | 0.166 (0.60) | 0.333 |
| Abeta42 | 0.997 | 0.629 | 0.201 (1.00) | 0.611 |
| hIAPP | 0.588 | 0.130 | 0.123 (0.19) | 0.385 |
| hPCSK9 | 0.266 | 0.057 | 0.037 (0.04) | 0.148 |

Strong on 2/4 (PADI4, Abeta42), ≈chance on hIAPP, below chance on hPCSK9. Even the two "strong" AUCs sit
below their own abundance null. From the prior 4-target rigor check, the LM also fails to robustly beat a
2-mer logistic (wins 2/4; the 2-mer never drops below 0.60, the LM ranges 0.27–0.98).

## 3. External SOTA bar (ML on display NGS → binder prediction)

There is **no single public leaderboard** for within-target cyclic-peptide binder ranking from display NGS;
the closest published analogs are sequence→binder classifiers trained on next-generation phage/mRNA-display
data:
- **PDL1Binder** — ensemble-SVM predictor of PD-L1-binding peptides from next-generation phage display
  (Jul 2022, Front. Microbiol.). Directly on-task (NGS display → ML binder classifier). Exact AUC/accuracy
  on its independent test set: **unverified** (not recovered from the available sources). [1]
- **FcBinder** — ML model predicting Fc-segment-binding peptides from display data. [2]
- **mRNA vs yeast display ML binder-design comparison** — mRNA display detected 83–86% of binders; reports
  computational metrics for predicting experimental binding; a referenced interface binder-prediction task
  reached **AUC ≈ 0.73**. [3]
- A **Bayesian ML model on deep-sequencing display data** identified improved variants with target-specific
  affinity (EC50 80–277 nM). [4]

**Even granting a SOTA bar of AUC ≈ 0.73–0.9 / meaningful validated hit rate, the comparison is moot here:**
our selector does not clear the **trivial abundance null** on its own eval, so a SOTA comparison cannot be
claimed in our favor. On the two targets where the LM is strong (PADI4 0.94, Abeta42 0.997) it would look
SOTA-competitive *on AUC alone* — but only against a benchmark its own trivial null already saturates, so the
AUC is not evidence of a real capability.

## 4. Verdict

- **Is the within-target LLM win SOTA / high-success?** **No.** It does not beat the abundance/enrichment
  null on any target; it is erratic across targets (below chance on hPCSK9); and it does not robustly beat a
  2-mer logistic. The "AUC 0.94" headline reflected an eval with no abundance null and one strong target.
- **What is the honest status?** The within-target eval is compromised by label-circularity (abundance ⇒
  `is_binder`). A within-target LLM win **cannot be claimed** as SOTA or high-success on this evidence.
- **To make a defensible within-target claim would require** a non-circular label (independent measured
  affinity, not enrichment) and evaluation on *novel* sequences (no read count), vs the abundance null and an
  external SOTA method on a shared split — none of which the current eval provides.

**Sources**
- [1] PDL1Binder — https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9335124/
- [2] FcBinder — https://www.vde-verlag.de/proceedings-en/566630007.html
- [3] mRNA vs yeast display ML binder design — https://pmc.ncbi.nlm.nih.gov/articles/PMC12919099/
- [4] Bayesian ML on deep-sequencing display — https://pmc.ncbi.nlm.nih.gov/articles/PMC9872955
