---
title: "A retrospective closed-loop evaluation of model-guided selection of permeable cyclic peptides from measured data"
author: "[Author list to be added]"
date: "Preprint, version 1 (computational study; prospective validation planned for version 2)"
---

## Abstract

Closed-loop design cycles that propose compounds, measure them and retrain are widely proposed for cyclic peptides, but claims of benefit are rarely tested against measured outcomes. We evaluated a design–test–learn loop retrospectively on 6,960 cyclic peptides with measured membrane permeability (PAMPA), where each peptide's measurement was revealed only after the loop selected it. Starting from 100 labelled peptides, a loop retrained a bootstrap ensemble of gradient-boosted regressors on molecular fingerprints for 10 rounds of 50 selections, and was compared with random selection, with greedy and uncertainty-aware policies, and with an oracle, from two starting conditions: an in-distribution start and a scaffold-shifted start in which the pool excludes the starting scaffolds. **[Result to be inserted from the pre-specified run: permeable peptides found in 500 selections per policy, paired differences with 95% intervals, both regimes.]** The design, hit definition, policies, seeds and claim rule were fixed before any run.

## 1. Introduction

Optimising permeability is a central difficulty for oral cyclic peptides, and experiments are expensive, so selecting which peptides to test next matters. A model-guided loop is attractive, but its benefit depends on the data it starts with and on whether the next compounds resemble those already measured. Published permeability models are typically evaluated on held-out compounds, which does not test the thing a loop depends on: the cumulative yield of useful compounds as labels accumulate and the model is retrained. We ask a narrow question with measured data: does a model-guided loop find more permeable cyclic peptides per experiment than random selection, and does that survive a start on unfamiliar scaffolds?

## 2. Methods

**Data.** The public CycPeptMPDB database [1]: PAMPA permeability (log Papp) for cyclic peptides, with detection-floor values removed and duplicate structures averaged (6,960 peptides). Features were Morgan count fingerprints (radius 2, 2,048 bits).

**Loop.** Each run starts with 100 labelled peptides and a pool of the rest. In each of 10 rounds a policy selects 50 pool peptides, their measured values are revealed, and the model is retrained on all revealed labels. The model is a bootstrap ensemble of five gradient-boosted regressors. Policies: random; greedy (highest predicted mean); uncertainty-aware (mean plus one ensemble standard deviation); and an oracle that selects the true best (an upper bound, not a method).

**Regimes.** (A) In-distribution: the initial 100 are random. (B) Scaffold-shifted: the initial 100 are drawn only from the two largest literature sources, and the pool excludes all peptides sharing a Murcko scaffold with them.

**Outcome and statistics.** A hit is a peptide in the top 10% of measured permeability in the dataset (threshold fixed in advance). The primary outcome is the number of hits among the 500 loop selections, over 30 seeds (the seed fixes the initial set and bootstrap), with paired differences between policies using the same initial set and 95% percentile intervals over seeds. The claim that the loop beats random required the interval of (greedy or uncertainty-aware minus random) to exclude zero in both regimes.

![**Figure L1. Design of the retrospective closed loop.**](figures/figL1_loop_design.png)

## 3. Results

**[To be completed from the pre-specified run: Figure L2 (hits found by policy in each regime with 95% intervals), the paired differences versus random, and the share of oracle yield recovered.]**

## 4. Discussion and limitations

A retrospective loop tests selection and learning logic against real measurements, but not wet-laboratory behaviour: all peptides were already measured, in different laboratories and conditions, so the pool is a literature-derived set, not a synthesis campaign, and assay differences between sources may act as noise or as a confound in the scaffold-shifted regime. The outcome is a cumulative count of top-decile peptides, which is sensitive to the hit threshold; the threshold was fixed before the runs. Fingerprint models are a deliberately simple baseline; the aim is to test the loop, not to optimise the model. A prospective test with newly synthesised peptides is planned for the next version.

## References

1. Li J. et al. CycPeptMPDB: a comprehensive database of membrane permeability of cyclic peptides. J. Chem. Inf. Model. (2023).
