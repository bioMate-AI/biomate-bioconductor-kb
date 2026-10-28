---
title: "A retrospective closed-loop evaluation of model-guided selection of permeable cyclic peptides from measured data"
author: "[Author list to be added]"
date: "Preprint, version 1 (computational study; prospective validation planned for version 2)"
---

## Abstract

Closed-loop design cycles that propose compounds, measure them and retrain are widely proposed for cyclic peptides, but claims of benefit are rarely tested against measured outcomes. We evaluated a design–test–learn loop retrospectively on 6,960 cyclic peptides with measured membrane permeability (PAMPA), revealing each peptide's measurement only after the loop selected it. Starting from 100 labelled peptides, the loop retrained a bootstrap ensemble of gradient-boosted regressors on fingerprints for 10 rounds of 50 selections, from an in-distribution and a scaffold-shifted start. Using a pooled "top 10% of permeability" outcome, the loop found far more hits than random selection (397 vs 50 in 500 selections in-distribution; 367 vs 107 scaffold-shifted), and a one-line N-methylation rule found 276 and 304. **However, 78% of all top-decile peptides (557 of 711) come from a single literature source, and 98% of the N-methylation rule's hits come from that source's series** (peptides averaging 5.7 N-methyl groups against 1.9 elsewhere). The pooled outcome therefore mostly measures finding one laboratory's series, an assay-and-series effect that is not within-laboratory permeability. We report this as a result in itself and re-run the loop with permeability normalised within each source (protocol amended before the re-run); those results replace the pooled ones as the primary outcome. In the pre-specified within-source re-run (hit = top 10% within each source; 30 seeds, 99% intervals for the knowledge comparisons), the greedy loop still beat random selection in both regimes (in-distribution 226.7 vs 50.0 hits in 500 selections, difference +176.7, 95% CI 146 to 209; scaffold-shifted 62.5 vs 29.9, difference +32.6, 95% CI 16 to 52), a smaller but source-independent gain. Because the first within-source run had two design flaws found by audit (knowledge signals on a pooled scale; chirality-blind fingerprints on a dataset in which about two thirds of peptides are stereoisomers), the knowledge-as-prior question and the loop-versus-rule comparison are reported from a corrected, pre-registered re-run (amendment L5; chirality-aware features, PAMPA labels, source-standardised knowledge, within-source rule baselines, a near-duplicate-aware sensitivity regime) **[L5 results to be inserted when the run completes]**.

## 1. Introduction

Optimising permeability is a central difficulty for oral cyclic peptides, and experiments are expensive, so selecting which peptides to test next matters. A model-guided loop is attractive, but its benefit depends on the data it starts with and on whether the next compounds resemble those already measured. Published permeability models are typically evaluated on held-out compounds, which does not test the thing a loop depends on: the cumulative yield of useful compounds as labels accumulate and the model is retrained. We ask a narrow question with measured data: does a model-guided loop find more permeable cyclic peptides per experiment than random selection, and does that survive a start on unfamiliar scaffolds?

## 2. Methods

**Data.** The public CycPeptMPDB database [1]: PAMPA permeability (log Papp) for cyclic peptides, with detection-floor values removed and duplicate structures averaged (6,960 peptides). Features were Morgan count fingerprints (radius 2, 2,048 bits).

**Loop.** Each run starts with 100 labelled peptides and a pool of the rest. In each of 10 rounds a policy selects 50 pool peptides, their measured values are revealed, and the model is retrained on all revealed labels. The model is a bootstrap ensemble of five gradient-boosted regressors. Policies: random; greedy (highest predicted mean); uncertainty-aware (mean plus one ensemble standard deviation); and an oracle that selects the true best (an upper bound, not a method).

**Regimes.** (A) In-distribution: the initial 100 are random. (B) Scaffold-shifted: the initial 100 are drawn only from the two largest literature sources, and the pool excludes all peptides sharing a Murcko scaffold with them.

**Knowledge-augmented arm.** A second loop used the fingerprints plus ten literature permeability descriptors (molecular weight, topological polar surface area, hydrogen-bond donors and acceptors, lipophilicity, rotatable bonds, N-methylated amide count, largest ring size, heavy-atom count, fraction of sp3 carbons), declared before the main result was read.

**Exploratory rule baseline.** After the main result, we ranked the pool once by a single descriptor (N-methyl count, low polar surface area, high lipophilicity or low donor count) and took the top 500, on the same seeds and pools, to ask how much a one-line rule achieves without learning.

**Outcome and statistics.** A hit is a peptide in the top 10% of measured permeability in the dataset (threshold fixed in advance). The primary outcome is the number of hits among the 500 loop selections, over 30 seeds (the seed fixes the initial set and bootstrap), with paired differences between policies using the same initial set and 95% percentile intervals over seeds. The claim that the loop beats random required the interval of (greedy or uncertainty-aware minus random) to exclude zero in both regimes.

![**Figure L1. Design of the retrospective closed loop.**](figures/figL1_loop_design.png)

## 3. Results

### 3.1 Primary result: within-source outcome (pre-specified re-run, 420 of 420 runs complete)

To remove the source confound, permeability was z-scored within each literature source and a hit was a peptide in the top 10% of its own source's distribution (amendment L3, fixed before the run). Over 30 seeds in each regime, the greedy fingerprint loop found 226.7 hits in 500 selections from the in-distribution start against 50.0 for random selection (difference +176.7, 95% CI 146.3 to 208.9), and 62.5 against 29.9 from the scaffold-shifted start (difference +32.6, 95% CI 15.7 to 51.8). The pre-specified claim that the loop beats random in both regimes was met, with a much smaller margin than the pooled analysis suggested, particularly after the scaffold shift. 

**Knowledge as prior or fusion.** The first within-source run (L3) standardised the knowledge signals over the pooled data while the labels were standardised within source: a scale mismatch in our design, found after the run and corrected by pre-registered amendment L5 (all knowledge signals standardised within source, plus chirality-aware fingerprints and the PAMPA label column; L4, which contained only the first change, never produced results because its spot instance was reclaimed). The L3 knowledge arms are therefore not evidence about knowledge and are not interpreted. **[L5 results: pending — to be inserted from `results/l5_aggregate.json`.]**

The pooled analysis below is retained for transparency and is superseded by 3.1 as the primary outcome.

**Caveat that applies to every pooled-label number in this section.** The top-decile outcome is dominated by one source (Figure not shown): 557 of 711 hits come from 878 peptides of a single laboratory, so the loop and the N-methyl rule largely locate that series (the N-methyl rule's top 500 selections were 89% from it in-distribution and 93% scaffold-shifted; 272 of 276 and 301 of 304 hits). The tables and figure below are retained for transparency and must not be read as within-laboratory permeability gains.

**Selection with a model beat random selection by a wide margin from both starts (Figure L2, Table 1).** From the in-distribution start, the greedy loop found 396.7 top-decile peptides in 500 selections on average, against 49.9 for random selection (difference +346.8 (95% CI 280 to 389)). From the scaffold-shifted start it found 366.7 against 106.6 (difference +260.1 (95% CI 125 to 318)). The uncertainty-aware policy behaved similarly (+345.4 (95% CI 312 to 377) and +265.0 (95% CI 210 to 314)). The pre-specified claim, that a loop policy beats random with an interval excluding zero in both regimes, was met.

| Policy | In-distribution start | Scaffold-shifted start |
|---|---|---|
| Random selection | 49.9 (34–71) | 106.6 (84–125) |
| N-methyl-count rule, no learning (exploratory) | 276.3 (269–283) | 304.0 (304–304) |
| Greedy loop, fingerprints | 396.7 (341–423) | 366.7 (234–415) |
| Uncertainty-aware loop, fingerprints | 395.4 (373–415) | 371.5 (318–411) |
| Greedy loop, fingerprints + rule features | 418.0 (378–444) | 327.0 (146–417) |
| Uncertainty-aware loop, fingerprints + rule features | 411.5 (368–436) | 347.2 (203–414) |
| Oracle (upper bound) | 500 | 500 |

**Table 1. Top-decile peptides found in 500 selections** (mean over 30 seeds, with the 2.5–97.5% range across seeds in parentheses). The oracle selects the best 500 by construction.

![**Figure L2. Retrospective loop results.** Top-decile peptides found in 500 selections from the two starting conditions. The N-methyl rule ranks the pool by N-methylation count with no learning and was added after the main result as an exploratory comparison.](figures/fig6_retrospective_loop.png)

**Adding literature permeability descriptors to the fingerprints did not help.** Relative to fingerprints alone, the knowledge-augmented loop changed the yield by +21.3 (95% CI -11 to 63) from the in-distribution start and -39.7 (95% CI -211 to 113) from the scaffold-shifted start (greedy policy; uncertainty-aware: +16.1 (95% CI -17 to 45) and -24.3 (95% CI -177 to 54)). All intervals include zero, so the pre-specified claim that the added rules help was not supported.

**A single classical rule recovers most of the yield without any learning (exploratory).** Ranking the pool by N-methylation count alone selected 276 top-decile peptides in the in-distribution setting and 304 in the scaffold-shifted setting, that is 70% and 83% of the greedy loop's yield. Rules based on TPSA, lipophilicity or hydrogen-bond donors alone did much worse (93, 30 and 34 in the in-distribution setting). The learned loop's advantage over the N-methyl rule is clear in-distribution (+120) but smaller and uncertain after the scaffold shift (+63, with seed-to-seed range 234–415).

## 4. Discussion and limitations

**Data and design audit of this study (verified 2026-10-28; files in `research/guangzhou_all_atom/cyclic_llm/loop_retro/` and `docs/20261028_CODE_DATA_EVAL_AUDIT_LOG.md`).** (i) The 6,960 peptides correspond to only 2,460 distinct stereo-free structures and 2,380 distinct Morgan fingerprints: about two thirds of the dataset are stereoisomers, which the original chirality-blind fingerprints could not distinguish; RDKit's chiral Morgan fingerprint itself separated only 48 of the 64 stereoisomers of a test macrocyclic hexapeptide, so stereochemistry remains incompletely represented. (ii) In the in-distribution regime, 22.9% of pool peptides have a fingerprint identical to an initial peptide and 60.7% share a stereo-free scaffold; the scaffold-shifted regime has none (0.000 on all three measures), so the in-distribution gain includes analogue-series effects and is accompanied by a near-duplicate-aware sensitivity regime. (iii) After within-source standardisation, 2020_Townsend still supplies 52.8% of top-decile hits (it contains 41% of peptides) and 2021_Kelly 22% (22% of peptides), mostly a dataset-composition effect; re-estimating each source's statistics from a random 30% subsample changes about 100 of 6,960 hit labels (hit-set Jaccard 0.867), an upper bound on the sensitivity to using all-label statistics. (iv) The generic `Permeability` column differs from `PAMPA` in 73 of 7,027 rows. (v) The exploratory N-methyl rule broke ties by dataset order, which is why its scaffold-shifted yield had zero variance; the corrected rule arms break ties at random. Each pick's source is recorded so that the share of any gain that is simply the largest series can be read directly.

Two results matter. First, a model-guided loop beats random selection in permeability data even when the outcome is normalised within source, but by a margin several-fold smaller than the pooled analysis implied; and the effect of literature knowledge is reported from the corrected run (Section 3.1). Second, and a warning for the field: in pooled literature permeability data a single laboratory's series accounts for most hits, so any loop, rule or model can appear to work by identifying that series. Evaluations must normalise within source (or hold out whole sources) before claiming gains. The statements below about the loop and the N-methyl rule refer to the pooled, confounded outcome.

A model-guided loop is far better than random selection at finding permeable cyclic peptides in measured data, including when the starting peptides share no scaffold with the pool. The comparison that matters for a practitioner is not random selection, however: a classical one-line rule (select the most N-methylated peptides) already recovers 70–83% of the loop's yield, and the loop's clear additional gain is in the in-distribution setting. Adding published permeability descriptors to the fingerprints did not improve the loop; in this data the fingerprints already carry that information.

A retrospective loop tests selection and learning logic against real measurements, but not wet-laboratory behaviour. All peptides were already measured, in different laboratories and conditions, so the pool is a literature-derived set; assay differences between sources, and analogue series that share a source, can make the task easier than a prospective campaign and can contribute to the in-distribution result. The scaffold exclusion removes shared Murcko scaffolds but not close analogues with different ring systems. The outcome is a cumulative count of top-decile peptides, which depends on the hit threshold (fixed before the runs). The N-methyl rule was examined after the main result and is exploratory. Fingerprint models are a deliberately simple baseline. A prospective test with newly synthesised peptides is planned for the next version.

## References

1. Li J. et al. CycPeptMPDB: a comprehensive database of membrane permeability of cyclic peptides. J. Chem. Inf. Model. (2023).
