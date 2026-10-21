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

---

## 5. Second target — 2-target within-target replication (Abeta42)

**Target choice.** FIKK13 (the only other *same-platform* thioether target) is too sparse — after dedup only
~40 unique binders, giving **8 test binders** at the 20% split (< the 10-binder floor). So the 2nd target is
**Abeta42** (`cyclization = disulfide/head-to-tail`, a *different* chemistry from PADI4's thioether). Two
chemistries is actually a stronger generality statement; the chemistry is reported honestly. Default log2fc
bucketing (no `trajectory_Abeta42.json`); same leakage-safe protocol otherwise. CPU, no spend.
Artifacts: `results/cyclic_llm_selector_Abeta42_{perseq_scores,leakagesafe}.json`, `runs_selector/selector_Abeta42.pt`.

| Scorer | FULL AUC (237 binders) | MOTIF-DISTINCT AUC (sim<0.5, 37 binders) |
|---|---|---|
| LM length-norm LLR | 0.9872 (lift5 12.3×) | 0.9792 |
| 2-mer logistic | 0.9858 | 0.9786 |
| AA-composition | 0.9335 | 0.8837 |

Leakage: 237 test binders, **84% ≥0.5** 3-mer Jaccard to a train binder (median 0.50) — a *much tighter*
motif family than PADI4 (18%, median 0.30). Only 37 test binders are motif-distinct.

### Two-target summary (motif-distinct, leakage-safe)
| Target (chemistry) | LM AUC | 2-mer AUC | **LM − 2-mer** | composition AUC |
|---|---|---|---|---|
| PADI4 (thioether) | 0.9405 | 0.8638 | **+0.077** | 0.766 |
| Abeta42 (disulfide) | 0.9792 | 0.9786 | **+0.001** | 0.884 |

### Honest verdict (2-target)
- **The within-target binder-RANKING signal replicates at 2 targets across 2 chemistries** (LM AUC
  0.94–0.98, leakage-safe). As a *ranking capability*, the within-target result holds.
- **BUT the LM's VALUE-ADD over a trivial 2-mer baseline does NOT replicate.** It is real on PADI4
  (+0.077) and **essentially zero on Abeta42 (+0.001 — the 2-mer logistic ties the LM)**. On Abeta42 the
  binders form a tight motif family a 2-mer baseline already separates at 0.979, leaving no headroom for
  the LM. So "the LM beats trivial baselines within-target" is a **PADI4-specific** finding, not a general
  one — a 2-mer baseline is competitive-to-equal elsewhere.
- **Implication for the paper:** claim the within-target binder-ranking capability (2 targets, 2
  chemistries) honestly, but do **not** claim the LM categorically beats trivial baselines — report the
  per-target value-add (+0.077 / +0.001) as-is. The LM's advantage is target-dependent and, on a tight
  motif family, absent.

---

## 6. Motif-diversity probe — does LM value-add track binder diversity? (4 targets, CPU)

Hypothesis (to test, not assume): the LM beats k-mer baselines when binders are motif-**diverse**, and adds
~nothing on a tight single-motif family a k-mer already separates. Qualifying targets (≥10 test binders
after dedup): **PADI4, Abeta42, hIAPP, hPCSK9** (4/5; FIKK13 disqualified at 8 test binders). Same
leakage-safe motif-distinct protocol; diversity = 1 − (fraction of test binders ≥0.5 3-mer-Jaccard to a
train binder), higher = more diverse. Per-seq scores + checkpoints stored for all four
(`results/cyclic_llm_selector_{T}_*`, `runs_selector/selector_{T}.pt`). All CPU (`python3.14`), no spend.

| target | chemistry | diversity | LM AUC (md) | 2-mer | comp | **value-add** (LM−best baseline) | LM full |
|---|---|---|---|---|---|---|---|
| PADI4 | thioether | 0.82 | 0.941 | 0.864 | 0.766 | **+0.077** | 0.951 |
| Abeta42 | disulfide | 0.16 | 0.979 | 0.979 | 0.884 | **+0.001** | 0.987 |
| hIAPP | disulfide | 0.74 | 0.585 | 0.605 | 0.602 | **−0.021** | 0.690 |
| hPCSK9 | photo-xlink | 0.88 | 0.260 | 0.865 | 0.815 | **−0.605** | 0.343 |

**Spearman(diversity, value-add) = −0.40 (n=4)** — the *wrong sign* for the hypothesis, and driven by
hPCSK9 (the MOST diverse target, where the LM has the WORST value-add and is **below chance**, AUC 0.26).

### Verdict — the hypothesis is refuted, and a stronger negative falls out
1. **"LM helps on motif-diverse binders" is REFUTED** (not merely unsupported): the diversity↔value-add
   rank correlation is −0.40 across the 4 targets, opposite the predicted direction. (n=4, so the −0.40 is
   itself not a law — but it certainly does not support the hypothesis.)
2. **The bigger, firmer negative: the LM has NO robust within-target advantage over a trivial 2-mer
   baseline across targets.** LM beats the best baseline on only **2/4** (PADI4 +0.077; Abeta42 +0.001 ≈
   tie), ties-to-loses on hIAPP (−0.021), and **fails below chance on hPCSK9 (0.26 vs 2-mer 0.865)**. The
   2-mer logistic is the more robust selector: its AUC never drops below 0.60 ({0.864, 0.979, 0.605,
   0.865}), whereas the LM is erratic ({0.941, 0.979, 0.585, 0.260}).
3. **Even within-target *ranking* only holds on 2/4** (PADI4, Abeta42 strong; hIAPP weak at 0.69; hPCSK9
   failed at 0.34 full). So the earlier "within-target win replicates" statement must be narrowed: it
   replicates on 2 of 4 targets and fails on 2.

### Honest implications for the paper
- Do **not** claim a general within-target LM advantage. The defensible statement is narrow and must name
  the failures: *"On 2 of 4 display targets the enrichment-conditioned LM ranks held-out binders strongly
  (AUC 0.95/0.99) and beats trivial k-mer baselines on one (PADI4, +0.077); on the other two it matches or
  underperforms a 2-mer logistic, and on hPCSK9 it is below chance."*
- A **trivial 2-mer logistic is the more robust within-target selector** across these targets than the LM —
  a result worth reporting on its own, and a caution against an LM-centric framing.
- Caveats: n=4 targets; **PADI4 is the only traj-train target** (possible confound — though Abeta42 reaches
  0.987 with default bucketing, so traj-train is not obviously the differentiator); hPCSK9's below-chance
  failure (photo-crosslink chemistry) may have a target-specific cause but is a real negative as-is.
