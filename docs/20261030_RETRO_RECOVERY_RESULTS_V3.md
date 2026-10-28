# Multi-target retrospective study — V3: validity gate, M3, and few-label adaptation baselines (2026-10-30)
Pre-registration: PREREG §15 (A7, gate + M3 outcome; `a6e07cd56`) and §16 (A8, H4b; reveal sets frozen `79276f09e`). Extends `docs/20261029_RETRO_RECOVERY_RESULTS_V2.md`. Code/data: `research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery/`.

## 1. Validity gate (required for every analysis)
Controls with no target information must be at chance: C1 atom-LM typicality (WS1 scorer, reproduced to 1e-16 on 200 compounds), C2 leave-fold-out multi-proxy logistic regression, C3 leave-fold-out Morgan-count logistic regression (not a matching variable), plus Bonferroni-adjusted single proxies. Unevaluable controls or < 8 families = unverifiable (a vacuous pass on a 1-target M3 attempt was caught and fixed with a test).
| benchmark | C1 | C2 | C3 | verdict |
|---|---|---|---|---|
| I (46 targets, 26 fam) | 0.503 [0.458, 0.550] | 0.559 [0.499, 0.619] | **0.584 [0.533, 0.636]** | not clean (C3; O-fraction 0.39, halogen 0.53) |
| M2 (20, 14) | **0.665 [0.551, 0.772]** | **0.690 [0.578, 0.795]** | **0.676 [0.541, 0.803]** | invalid (confirms WS1's finding) |
| M (299, 120) | 0.476 [0.439, 0.513] | 0.469 [0.427, 0.509] | **0.315 [0.279, 0.352]** (below chance) | invalid |
| I remaining items after reveal, k = 5 / 10 / 25 | 0.512 / 0.518 / 0.499 (at chance) | 0.564 / 0.564 / 0.527 | 0.587 / 0.567 / 0.595 (exceed chance) | not clean at every k |
**M3 (typicality + 18 other proxies + similarity matching) is not achievable:** loosest caliper keeps 257 positives / 15 families and C2 0.635 [0.516, 0.753], C3 0.647 [0.510, 0.778] still separate them; tighter calipers leave 70 → 6 positives (6 → 1 families). Power cost 98–100 % of eligible positives. Hypothesis (untested): a target's positives form a chemotype series, so any cross-target-decoy design stays separable by a compound-only classifier. Consequence: **the zero-shot family-held-out claim can only be made on I, under the control-adjusted rule (A7): an arm must beat the strongest of {B0–B4, C1–C3}**; no benchmark in this study passes the gate cleanly, and papers must say so.

## 2. H4b few-label adaptation — baselines (analysis I; frozen reveals: 45 / 44 / 39 targets, 26 / 25 / 21 families at k = 5 / 10 / 25; 5 seeds)
| k | NN (to revealed) AUROC | FP-k (fit on revealed only) | PT+k (pretrained LR + revealed, w = 20) | PT (no-target, other families) | random |
|---|---|---|---|---|---|
| 0 | – | – | – | 0.539 [0.478, 0.605] | 0.478 |
| 5 | **0.753 [0.715, 0.789]** | 0.750 [0.711, 0.787] | 0.672 [0.617, 0.724] | 0.537 | 0.490 |
| 10 | **0.822 [0.784, 0.856]** | 0.817 [0.777, 0.851] | 0.736 [0.688, 0.782] | 0.521 | 0.497 |
| 25 | **0.869 [0.835, 0.899]** | 0.861 [0.817, 0.897] | 0.823 [0.775, 0.865] | 0.517 | 0.507 |
Gain over zero-shot PT: NN +0.214 / +0.300 / +0.342 (all CIs exclude 0); top-10 precision NN 0.78 / 0.83 / 0.96 (random 0.56 / 0.55 / 0.71: I is positive-heavy, so P@10 and EF5 are weakly informative and AUROC is primary). Nothing beats NN: FP-k − NN = −0.004 / −0.005 / −0.008 (CIs include 0); PT+k is 0.05–0.09 below.
**What this means:** (i) few labels of the target help a lot (+0.21 to +0.34 AUROC), but the best method is plain nearest-neighbour to the revealed compounds — the gain is **analog lookup within a target's chemical series** (stereoisomer siblings of revealed compounds are removed; close analogs remain), not demonstrated target-biology learning. (ii) The no-target pretrained model stays at 0.52–0.54, so zero-shot compound-only transfer is near chance on this set despite C2/C3 showing the benchmark carries some compound-only signal. (iii) **The bar for any LLM few-label arm is NN / FP-k at the same k**, and the gain test is against its own k = 0 value; LLM score files are evaluated with `run_s3.py --k K` (`h4b_eval.py`, same remaining items, all-items and contamination-controlled).

## 3. Errors / checks in this pass
Vacuous gate pass fixed + test; PT+k convergence concern checked directly (65 iterations; two runs differ by ≤ 2.2e-5; pretrained models converge at 79–124 iterations); first run kept in `results/superseded/`. M2/I/M gate tables were computed after M2's failing control was known (A7 discloses the order). Not verified: that typicality missingness (very large compounds) does not interact with the gate; family structure is Pfam-based; I has 26 families.
## 4. Remaining gaps
LLM arms (WS1) and loop replay (WS2) not yet scored under H4b; GBM variants dropped for cost; S2 not executed; M3 not achievable → no clean zero-shot benchmark.

## Correction notice (appended 2026-10-31, A10/A11) — see `docs/20261030_RETRO_RECOVERY_RESULTS_V5.md`
Analysis I is family-disjoint but **not** compound-disjoint (1,093 of 9,432 rows, 11.6 %, share a compound with another fold). The M C3 value 0.315 above is a label-inversion artefact (corrected: 0.461 [0.423, 0.498] items scope; 0.515 [0.480, 0.549] any-pair scope). Validity is now an equivalence status, not "interval contains 0.5"; no benchmark is VALID. A censoring indicator alone separates I's classes (AUROC 0.206 [0.134, 0.280]). Benchmark counts: 16,195 compounds, 793 targets, 24,583 labelled pairs (not 17,120 / 851).
