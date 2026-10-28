# Multi-target retrospective study — V4: analog-distance strata, cluster power, gate framing (2026-10-30)
Registered in PREREG §17 (A9, commit `c97e79237`) before the strata and power analyses ran. Extends `docs/20261030_RETRO_RECOVERY_RESULTS_V3.md`. Prior art: `docs/20261030_PRIOR_ART_PEPBENCHMARK_PROTAC_CEILING.md`. Code/results: `retro_recovery/{13_h4b_strata.py,14_power.py}`, `results/{h4b_strata.json,h4b_strata_items_summary.csv,power.json}`.

## 1. Analog-distance strata of the few-label gain (analysis I, 5 seeds; AUROC, family-cluster 95 % CI)
Bins by maximum Tanimoto of each remaining compound to ANY revealed compound of its target (stereoisomer-sibling removal, registered in A8, removed **0** items: analysis I keeps one compound per flat structure per class, so no siblings exist within a target — `stereosibling_items_removed_total` = 0; the 'stereo-sibling' stratum the committee asked for is therefore empty by construction and close analogs here are non-stereo analogs at Tanimoto ≥ 0.70). Share = fraction of remaining items in the bin.
| k | bin | share | targets / families | random | NN | FP-k | PT+k | PT (zero-shot) | transferable gain: FP-k − PT | PT+k − PT |
|---|---|---|---|---|---|---|---|---|---|---|
| 5 | close ≥ 0.70 | 0.33 | 43 / 25 | 0.487 | 0.859 | 0.862 | 0.797 | 0.511 | +0.351 [+0.259, +0.448] | +0.286 [+0.203, +0.378] |
| 5 | medium 0.50–0.70 | 0.37 | 40 / 22 | 0.451 | 0.685 | 0.664 | 0.618 | 0.520 | +0.145 [+0.054, +0.238] | +0.099 [+0.061, +0.137] |
| 5 | remote 0.30–0.50 | 0.26 | 32 / 17 | 0.498 | 0.608 | 0.622 | 0.588 | 0.559 | **+0.064 [−0.002, +0.135]** | **+0.029 [−0.003, +0.069]** |
| 5 | very remote < 0.30 | 0.04 | 10 / 9 | 0.489 | 0.697 | 0.646 | 0.549 | 0.549 | +0.096 [−0.082, +0.296] | −0.001 [−0.013, +0.011] |
| 10 | close | 0.46 | 43 / 24 | 0.501 | 0.871 | 0.876 | 0.819 | 0.543 | +0.333 [+0.265, +0.402] | +0.277 [+0.216, +0.338] |
| 10 | medium | 0.38 | 36 / 19 | 0.515 | 0.745 | 0.715 | 0.677 | 0.533 | +0.182 [+0.052, +0.293] | +0.144 [+0.091, +0.199] |
| 10 | remote | 0.16 | 27 / 14 | 0.516 | 0.596 | 0.578 | 0.602 | 0.550 | +0.028 [−0.072, +0.124] | +0.052 [+0.000, +0.117] |
| 10 | very remote | 0.01 | 3 / 3 | – | – | – | – | – | not evaluable (3 families) | |
| 25 | close | 0.62 | 39 / 21 | 0.501 | 0.895 | 0.897 | 0.869 | 0.520 | +0.377 [+0.300, +0.449] | +0.349 [+0.268, +0.420] |
| 25 | medium | 0.30 | 29 / 15 | 0.508 | 0.729 | 0.748 | 0.690 | 0.519 | +0.229 [+0.070, +0.389] | +0.171 [+0.073, +0.270] |
| 25 | remote | 0.07 | 11 / 4 | 0.495 | 0.561 | 0.548 | 0.694 | 0.634 | −0.086 [−0.271, +0.099] | +0.060 [+0.020, +0.097] (4 families) |
| 25 | very remote | 0.00 | 1 / 1 | not evaluable | | | | | | |
**Reading.** (i) The few-label gain is large only where a revealed analog is close (≥ 0.50): AUROC 0.86–0.90 close, 0.66–0.75 medium, vs 0.55–0.63 remote. (ii) In the remote bin the gains over zero-shot are +0.03 to +0.06 with CIs that include or just reach 0 at k = 5 and 10 (FP-k +0.064 [−0.002, +0.135]; PT+k +0.029 [−0.003, +0.069]); at k = 25 the remote bin holds 7 % of items in 4 families. (iii) The very-remote bin (< 0.30) is nearly empty (4 % at k = 5, ≤ 1 % at k ≥ 10): **there are almost no truly dissimilar compounds within a target's own set, so transfer to dissimilar chemotypes cannot be tested on I**. (iv) **By the registered rule (A9: transferable only if the lower bound is > 0 in both the remote and very-remote bins and the arm is not worse than NN), no few-label gain is demonstrated to be transferable.** The portion of the overall NN gain that survives in the remote bin (+0.05 to +0.10 over random) is small and partly reflects the typicality/compound-only signal (C2/C3 at 0.56–0.59, V3). (v) NN is never worse than the learned arms in close/medium bins; the shape of the result is analog lookup.

## 2. Cluster-based power (unit = family; `results/power.json`)
MDE = 2.8·σ_d/√n_families (80 % power, two-sided α = 0.05; normal approximation).
| contrast | n families | σ of family-level difference | MDE (AUROC) | families needed for δ = 0.05 |
|---|---|---|---|---|
| I: S1d profile − strongest baseline (B3_nn_neg) | 26 | 0.201 | **0.111** | 128 |
| I: S1b-induction − B3_nn_neg | 26 | 0.216 | 0.118 | 146 |
| I: S1c-induction − B3_nn_neg | 26 | 0.249 | 0.137 | 195 |
| M2: S1d − B3_nn_neg | 14 | 0.247 | 0.185 | 192 |
| H4b k=5: NN − PT(k=0) / PT+k − PT / FP-k − PT | 26 | 0.162 / 0.107 / 0.162 | 0.089 / 0.059 / 0.089 | 83 / 36 / 82 |
| H4b k=10: NN − PT / PT+k − PT | 25 | 0.138 / 0.129 | 0.077 / 0.072 | 60 / 53 |
| H4b k=25: NN − PT / PT+k − PT | 21 | 0.137 / 0.148 | 0.083 / 0.090 | 59 / 69 |
| H4b NN − FP-k (k = 5 / 10 / 25) | 26 / 25 / 21 | 0.031 / 0.041 / 0.035 | 0.017 / 0.023 / 0.021 | 4 / 6 / 4 |
**Reading.** (i) The primary zero-shot analysis I can only detect an arm-vs-strongest-baseline difference of ≈ **0.11 AUROC** (S1d) with 26 families; a 0.05 improvement would need ≈ 130 families. So the null results on I and M2 are **not evidence of no effect** for effects below ≈ 0.11–0.19. (ii) The H4b gains over zero-shot (+0.21 to +0.34) exceed the MDE (0.06–0.09) several-fold, so they are well powered; (iii) NN − FP-k differences are estimated precisely (MDE ≈ 0.02): the two are equivalent within about 0.02 AUROC at every k. (iv) ICC of per-target AUROC within families: S1d on I 0.23 (effective independent targets ≈ 39 of 46), on M2 0.76 (≈ 15 of 20): targets in the same family are not independent, which is why families are the unit. ICC values for the near-constant arms (S1a, S1b-KB: AUROC ≡ 0.5 on most targets) are not meaningful and their MDEs (0.018–0.084) are artefacts of near-zero variance; ignore them.

## 3. Framing: the validity-gate failure as a result (committee request)
Established by A7/V3: (a) a no-target typicality score separates M2's positives from decoys (0.665) after similarity matching; (b) compound-only classifiers separate I's positives from inactives across held-out families (C3 0.584); (c) the best attempted correction (M3: 19-proxy matching incl. typicality) retained 257 of ≈ 17.9k eligible positives (98.6 % lost) and still failed C2/C3; tighter calipers left 1–7 targets. Candidate contribution: **a reproducible audit protocol (no-target controls C1–C3 + single proxies, family-cluster intervals, unverifiable-by-default rule) and the finding that, for public cyclic-peptide binding data at this scale, no decoy construction we tried yields a benchmark that passes it.** Limits to state with it: one data collection (BindingDB + ChEMBL; frozen set 16,195 compounds, 14,599 flat structures, 793 targets with labelled pairs, 24,583 labelled pairs = 20,562 positive + 4,021 inactive — corrected in A11; '17,120 / 851' was the pre-freeze profile), our matching constructions only (BDNegSamp-style matching was not tested), Pfam-Jaccard families, and the gate's own low power when families are few (it can only certify what its intervals can exclude: ≈ ±0.06–0.10 on 14–26 families).

## 4. Errors / checks in this pass
Strata job slowed by machine load (load average > 200; no hang). Bin edges and arms were fixed in A9 before running; arms reuse `11_h4b_run.py` unchanged (imported). The strata table's stereo-sibling count is reported in the json, not asserted here. Prior-art note lists exactly which parts of each paper were read.

## Correction notice (appended 2026-10-31, A10/A11) — see V5
Same standing statement as V3: analysis I is family-disjoint but not compound-disjoint (11.6 % of rows share a compound with another fold); the αvβ6 "2 targets (2 families)" subset is one antigen (complex and β6-alone share 70 of 77 compounds; v2 folds merge them: B3 0.900 → 0.828 on that subset). Power figures in §2 were computed on v1 families (26 on I); on folds_v2 I has 23 families, which raises the minimal detectable effect accordingly (×√(26/23) ≈ +6 %).
