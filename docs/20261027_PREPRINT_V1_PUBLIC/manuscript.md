---
title: "Co-folding confidence does not select the best cyclic-peptide pose: a pre-registered post-cutoff evaluation of feature-based selectors, and an audit of how split design inflates binder prediction"
author: "[Author list to be added]"
date: "Preprint, version 1 (computational study; experimental validation planned for version 2)"
---

## Abstract

Co-folding models generate many candidate structures per complex, and users usually take the one the model ranks first. For cyclic peptides this choice is fragile: covalent ring closure is not enforced by the model (about 75% of sampled structures in our pilot had a valid ring), non-canonical residues enter as chemical modifications, and the best of 25 samples can be far better than the one the model prefers. In a 26-complex pilot, the model's own top pick succeeded (DockQ ≥ 0.23) in 80.8% of complexes, indistinguishable from a randomly chosen sample (80.3%), whereas the best of 25 samples succeeded in 96.2%. We developed a ground-truth-free selector that scores each sample from model confidences, ring-closure geometry, steric clashes and agreement among samples, and we evaluated it once, under a protocol fixed in advance, on experimental cyclic-peptide complexes deposited after the training cutoff, against six fixed baselines, with uncertainty estimated by bootstrapping over receptor clusters. On 104 post-cutoff complexes (68 from receptors absent from training), the model's own pick succeeded in 57.7% and a random sample in 59.6%, whereas the best of 25 samples succeeded in 76.9% (oracle minus default 19.2 points, 95% CI 8.8 to 28.5). The selector did not outperform the strongest baseline (59.6% vs 60.6%; difference -1.0 points, 95% CI -4.6 to +2.1), so the pre-registered claim was not supported. Separately, applying the same evaluation discipline to a previously reported display-based binder predictor, we found that on three of five targets a bag-of-k-mers logistic regression matched the language model on random splits (AUC 0.986 vs 0.990 on Abeta42; 0.698 vs 0.689 on hIAPP) and fell sharply when whole mutant families were held out (hIAPP 0.52, hPCSK9 0.65, FIKK13 0.42); on PADI4, where binders are not clustered into families, the baseline held up (0.86) and the language model may add value. Reliability claims for peptide predictors therefore need split-appropriate evaluation against trivial baselines before they can be used to drive design decisions.

## 1. Introduction

Cyclic peptides bind protein surfaces that are difficult for small molecules to address, and modern co-folding models can now predict peptide–protein complexes from sequence [1]. In practice a user draws several samples from such a model and keeps one, typically the sample with the highest model confidence. The quality of that single choice determines whether a predicted pose is usable for design and ranking.

Cyclic peptides make this choice harder than it is for linear peptides or protein–protein complexes. The model's cyclisation flag does not enforce a covalent closure, many deposited cyclic peptides carry non-canonical residues that must be supplied as chemical components, and the fraction of samples that are already acceptable can be high, which hides selection error behind a ceiling effect. Confidence-versus-quality relationships have been studied for protein–protein and linear protein–peptide complexes [2,3]; here we ask the question for experimentally determined cyclic-peptide complexes, using ring geometry as an explicit selection signal and evaluating on receptors the selector has not seen.

We make four contributions. (i) A post-cutoff set of experimental cyclic-peptide complexes defined from deposited covalent-link records. (ii) A selector that uses only information available without the experimental structure. (iii) A one-shot evaluation with a fixed claim rule, six fixed baselines, bootstrapping over receptor clusters, and an analysis restricted to receptors absent from training. (iv) An audit showing that the same discipline changes the conclusion for a previously reported display-based binder predictor, which we include because the failure mode (near-duplicate sequences on both sides of a random split) is common in peptide machine learning.

## 2. Results

### 2.1 Study design

Figure 1 summarises the study. Complexes deposited before 2023-10-01 were used only to fit the selector; complexes deposited on or after that date were used once for evaluation. For each complex, 25 structures were sampled from a co-folding model given the receptor sequence and the peptide sequence with its ring topology, never the experimental coordinates. Each sample was scored with features that do not use the experimental structure, and the selector chose one sample per complex. Success was defined as DockQ [4] of the chosen sample ≥ 0.23 (acceptable) or ≥ 0.49 (medium).

![**Figure 1. Study design.** Complexes are split by deposition date. The selector is fit on earlier complexes only and evaluated once on later complexes against six fixed baselines and two reference rows. Uncertainty is estimated by bootstrapping over receptor clusters.](figures/fig1_study_design.png)

### 2.2 The model's default pick is no better than a random sample in a pilot

In a pilot of 26 complexes (25 samples each), the sample with the highest model confidence succeeded in 80.8% of complexes (95% CI 65–96), ipTM-ranked selection in 76.9%, and a randomly chosen sample in 80.3% in expectation, whereas the best of 25 samples succeeded in 96.2% (88–100; Figure 2). The oracle-minus-default gap was 15.4 percentage points (CI 3.8–30.8), which exceeded the pre-specified 10-point threshold for proceeding. The whole gap came from four complexes in which the default pick failed but another sample succeeded. ipTM discriminated weakly within complexes (mean within-complex AUROC 0.56), and its pooled AUROC (0.68) largely reflects differences in difficulty between complexes. Only 75% of all samples had a valid closed ring, and the proportion was as low as 24% in some complexes.

![**Figure 2. Pilot headroom.** Top-1 success (DockQ ≥ 0.23) for the model's default pick, ipTM, a random sample (expectation), and the oracle best of 25 samples. The oracle uses the experimental structure and is an upper bound.](figures/fig2_pilot_headroom.png)

Fourteen of 40 planned pilot complexes did not run (two input-typing errors, since corrected; eight whose chemical components are absent from the model's bundled library; four exceeding GPU memory), and the missing complexes are not random: they skew toward the newest depositions and the largest receptors. The pilot is therefore a feasibility estimate and not evidence about the whole population.

### 2.3 Primary evaluation of the selector

The test set contained 104 post-cutoff complexes from 52 receptor clusters; 68 of them came from 40 receptor clusters absent from the training set (155 complexes, 91 clusters). Nine of the 113 planned test complexes were not generated before the pre-specified evaluation time and are excluded and listed in the supplement. The selector was fit once on the training and validation complexes and evaluated once on the test set (Table 1, Figure 3).

| Method | All test complexes, DockQ ≥ 0.23 (n=104) | Receptors absent from training, ≥ 0.23 (n=68) | All, DockQ ≥ 0.49 (n=104) |
|---|---|---|---|
| Model confidence (default) | 57.7 | 52.9 | 44.2 |
| ipTM | 58.7 | 52.9 | 45.2 |
| pTM | 56.7 | 50.0 | 46.2 |
| Interface pLDDT | 60.6 | 52.9 | 43.3 |
| Ring strain (low is better) | 60.6 | 51.5 | 43.3 |
| Clash count (low is better) | 57.7 | 52.9 | 44.2 |
| Random sample (expected) | 59.6 | 51.1 | 45.3 |
| **Selector S2 (primary)** | 59.6 | 51.5 | 43.3 |
| Selector S0 (original specification) | 61.5 | 52.9 | 44.2 |
| Oracle, best of 25 (upper bound) | 76.9 | 67.6 | 57.7 |

**Table 1. Top-1 success (%) on the post-cutoff test set.** Selector S2 is the pre-specified primary selector (logistic regression on three pLDDT features); S0 is the original specification (26 features, trained on all samples), reported alongside as registered.

![**Figure 3. Primary result.** Top-1 success (DockQ ≥ 0.23) for each selector, baseline, the random expectation and the oracle, on all test complexes and on receptors absent from training. Titles give the difference between the selector and the strongest baseline with 95% intervals from a receptor-cluster bootstrap.](figures/fig3_primary_result.png)

**The pre-registered claim was not supported.** The primary selector S2 succeeded in 59.6% of test complexes, against 60.6% for the strongest baseline (interface pLDDT); the difference was -1.0 percentage points (95% CI -4.6 to +2.1). On receptors absent from training the difference was -1.5 points (-8.7 to +4.4), and at DockQ ≥ 0.49 it was -2.9 points (-7.8 to +2.6). The original specification S0 was likewise indistinguishable from the best baseline (+1.0 points, −4.3 to +5.8).

**There is substantial headroom that none of the signals captured.** The oracle succeeded in 76.9% of complexes, which is 19.2 points above the model's default pick (95% CI 8.8 to 28.5). The model's default pick (57.7%) was no better than a randomly chosen sample (59.6%), as in the pilot, but the base rate was much lower than in the pilot (80%) and in the older training complexes (84%).

**What the training data say about why.** In the 155 training and validation complexes, 109 had every sample acceptable and only 42 had a mixture, so only a quarter of the complexes carry any selection signal. In the informative training complexes, failing samples were gross misses, not near-misses (median DockQ 0.03). Consensus among samples had an unstable sign: in complexes where fewer than half of the samples were correct, the correct pose was the minority and agreement with the other samples pointed the wrong way. Ring-closure validity did not predict pose correctness (valid-ring samples succeeded 50% of the time and invalid-ring samples 53%). Peptide and interface pLDDT had the most consistent sign but only modest within-complex discrimination (mean within-complex AUROC 0.66 and 0.61). These training-set analyses guided the selector's design (Supplementary Table S1) and are descriptive.

### 2.4 Split design determines how reliable a binder predictor appears

A display-conditioned language model had been reported to rank held-out binders in phage and mRNA display pools with AUC between 0.69 and 0.99. That evaluation used a random split of unique sequences. Display pools contain families of near-identical sequences, so a random split places family members on both sides. We measured this directly in five target pools (Figure 4). In the Abeta42 pool, all binders fall into 11 families and a single family holds 96.8% of them; 99.6% of test binders had a training binder within one substitution. In hIAPP one family holds 80.6% of binders (35% of test binders within one substitution of a training binder). A bag-of-1/2-mer logistic regression, which has no capacity for sequence context, reached AUC 0.986 on the Abeta42 random split (language model: 0.990) and 0.698 on hIAPP (0.689). When families were held out, the same baseline fell to 0.957 on Abeta42, 0.521 on hIAPP and 0.653 on hPCSK9 (random split 0.841), and to 0.415 (below chance) on FIKK13, where 47% of binders lie in one family. PADI4 behaved differently: its binders are almost all singletons (308 of 314 families), few test binders have a close training relative (22%), and the baseline held up on the family-disjoint split (0.865 random, 0.864 family-disjoint) against 0.968 reported for the language model. For PADI4 a real advantage of the language model over the trivial baseline is therefore plausible, although the two numbers come from different test samples and about half of PADI4 labels showed signs of amplification artefacts, so the comparison needs the same split and cleaned labels. For the other targets, on these splits the language model offered no measurable advantage over a trivial baseline. Figure 5 illustrates why: a random split rewards memorising a motif, whereas family-disjoint and receptor-disjoint splits test the generalisation a designer needs.

![**Figure 4. Reliability audit.** AUC of a k-mer logistic regression on the original random split (grey) and on a family-disjoint split (orange), compared with the language model as originally reported (blue) for five display targets. Dashed line: chance.](figures/fig4_reliability_audit.png)

![**Figure 5. Split strategies.** Filled points are training and open points are test sequences; colours indicate receptors and circles indicate sequence families. A random split leaks family members across the boundary.](figures/fig5_split_strategies.png)

**[To be completed: the language model re-evaluated on the same family-disjoint splits and cleaned labels, so that the PADI4 comparison is like for like.]**

### 2.5 Retrospective closed-loop evaluation on measured permeability

**[To be completed from the pre-specified run: a retrospective design–test–learn loop on the CycPeptMPDB permeability data [5], in which each assay result is revealed only after the loop selects the peptide. Greedy and uncertainty-aware policies are compared with random selection in an in-distribution start and a scaffold-shifted start; Figure 6.]**

## 3. Discussion

The pilot indicates that the model's default confidence is a weak guide to the best sample for cyclic peptides, with ring closure not guaranteed, and it identifies where a selector could help (about 15 percentage points of headroom in a population with a high base rate). The primary evaluation shows that this headroom is real but not accessible with the signals we tested: neither model confidences, ring-closure geometry, clash counts, pose consensus nor a trained combination of them picked better samples than the model's own pick or than a random sample. The gap is a selection problem in which the correct pose is often the minority among samples, which limits consensus-based approaches exactly where they are needed. Signals independent of the co-folding model's own confidence (for example physics-based interface energies or a second, independent structure predictor) are the obvious next candidates and were not tested here.

The binder-prediction audit makes a general point that applies beyond this study. A predictor's apparent reliability depends on how test examples relate to training examples. When the data come as families of near-duplicates, random splits measure memorisation. Because design decisions are made on new families and often on new targets, reliability should be measured under splits that match that question, and every learned model should be compared with a trivial baseline on the same split. The numbers in Figure 4 are a reminder that a high AUC on a random split can be reproduced without any learning beyond residue counts.

### Limitations

(1) A single co-folding model was used. (2) Computational limits restricted the evaluation to complexes of at most 1,200 tokens and the training set to at most 600 tokens; the excluded complexes are listed in the supplement, and the evaluated set is biased toward smaller complexes. (3) The model's training cutoff was taken from secondary sources, and residual leakage through homologous receptors deposited earlier is possible; receptor-cluster overlap is reported. (4) Complexes whose chemical components are absent from the model's library could not be run, and these skew toward the newest depositions. (5) The pilot contains 26 complexes and has wide intervals. (6) DockQ success measures agreement with a deposited structure, not binding affinity. (7) The retrospective loop and the display audit use previously measured data and do not replace prospective experiments. Experimental validation will be added in the next version, together with predictions recorded in advance.

## 4. Methods

**Complexes.** Experimental complexes were defined from deposited covalent-link records in the Protein Data Bank (884 complexes in the source list). Receptors were grouped at 40% sequence identity (receptor clusters). Two tiers were kept separate: peptides with canonical residues only, and peptides containing non-canonical residues supplied as chemical components. Training used complexes deposited before 2023-10-01; evaluation used complexes deposited on or after that date.

**Structure sampling.** A co-folding model [1] (version 2.2.1) generated 25 diffusion samples per complex (seed 0), with receptor alignments from a public server, no peptide alignment, no templates and no pocket or contact conditioning. Receptor chains and the peptide (non-canonical residues as chemical-component modifications; cyclisation as head-to-tail or as explicit bonds) were renamed to single-letter chains identically in prediction and reference. Sampling ran on 16 GB cloud GPUs and on a 128 GB unified-memory workstation; DockQ for one complex was identical on both platforms.

**Metrics.** DockQ v2 [4] with the peptide as ligand against the receptor chain with the most native contacts. Primary: top-1 success, DockQ of the selected sample ≥ 0.23; secondary: ≥ 0.49.

**Features and selector.** Twenty-six features per sample were computed without the experimental structure: model confidences (confidence score, ipTM, pTM, interface pLDDT and related), ring-closure bond-length and angle deviations from ideal, steric clash counts, interface contact density, and consensus features (mean peptide RMSD to the other samples of the complex and the size of the largest pose cluster). Features were z-scored within each complex. An L2-regularised logistic regression was trained on the training complexes to predict DockQ ≥ 0.23; at evaluation, the highest-scoring sample per complex was chosen. Any column derived from the experimental structure was rejected by an explicit check.

**Baselines.** Model confidence (higher is better), ipTM, pTM, interface pLDDT (higher), ring strain and clash count (lower), with directions fixed in advance. Reference rows: the expected success of a randomly chosen sample, and the oracle (best of 25 by DockQ), which is not a method.

**Statistics and claim rule.** Paired bootstrap (4,000 resamples) over receptor clusters, 95% percentile intervals. The strongest baseline was chosen on the test set (conservative). The statement "the selector is best" required the interval of the selector-minus-strongest-baseline difference to exclude zero on all test complexes and on the subset of receptors absent from training, at DockQ ≥ 0.23. Otherwise the result is reported as not supported.

**Protocol and amendments.** The protocol, selector, baselines and claim rule were fixed before any structure was generated. Subsequent amendments were made before any evaluation sample was scored and are listed in Supplementary Table S1.

**Display-based binder audit.** Display pools for five targets (public sequencing data) were reduced to unique sequences of 6–14 residues. We reproduced the original split (shuffled unique sequences, 20% test), measured the distance from each test binder to the nearest training binder (Hamming distance), trained a logistic regression on 1- and 2-mer counts, and repeated the analysis on a family-disjoint split in which sequences connected by single substitutions form one group and whole groups are held out.

**Retrospective loop.** Permeability measurements from CycPeptMPDB [5] (PAMPA assay, duplicate structures averaged) served as the assay. Starting from 100 labelled peptides, a loop ran for 10 rounds of 50 selections with an ensemble of gradient-boosted regressors retrained each round, comparing random, greedy and uncertainty-aware selection over 30 seeds. A hit was defined as the top 10% of measured permeability.

## Data and code availability

Complex lists, the amendment log, the evaluation outputs and the analysis code will be deposited in a public repository on publication of this preprint.

## References

1. Boltz-2 co-folding model. Passaro S. et al. bioRxiv (2025).
2. Benchmark of AlphaFold-Multimer and AlphaFold3 with scoring functions for protein complexes. bioRxiv, doi:10.1101/2024.11.11.622992.
3. Benchmark of AlphaFold-like methods for protein–peptide complexes. bioRxiv, doi:10.1101/2025.06.18.660495.
4. Mirabello C, Wallner B. DockQ v2: improved automatic quality measure for protein multimers, nucleic acids and small molecules. Bioinformatics (2024).
5. Li J. et al. CycPeptMPDB: a comprehensive database of membrane permeability of cyclic peptides. J. Chem. Inf. Model. (2023).
6. Related work on cyclic-peptide design and multi-fidelity or agentic pipelines: arXiv:2402.10387; arXiv:2508.14765; bioRxiv doi:10.1101/2026.10.20.760329; Nat. Chem. Biol. doi:10.1038/s41589-025-01929-w; Nat. Commun. doi:10.1038/s41467-025-59940-7.

## Supplementary Table S1. Amendments to the protocol (all made before any evaluation sample was scored)

| ID | Change | Reason |
|---|---|---|
| A1–A2 | Selector specification, claim rule and predictions recorded in full before generation of evaluation data | Remove analyst freedom |
| A3 | Compute strategy changed to use two hardware platforms | GPU memory and spot-capacity limits |
| A4 | Evaluation set limited to complexes of ≤ 1,200 tokens; training set to ≤ 600 tokens (4 test and 34 training complexes excluded; listed) | Run time grows faster than linearly with size; not outcome-dependent |
| A5 | Evaluation triggered when all evaluation complexes finished, or after a fixed 6-hour window; training uses all training complexes finished by then; missing evaluation complexes reported | Fix the timing of the one-shot evaluation |
| A6 | Second selector variant S1 trained only on complexes with mixed outcomes; regularisation chosen by receptor-grouped cross-validation on training data | Complexes with all-equal labels carry no ranking information |
| A7 | Four feature sets and a rule for adopting a new primary selector (cross-validation gain ≥ 1.5 points) | Training-set diagnostics: consensus features had an unstable sign; ring validity was uninformative |
| A8 | Contrastive selector tested; validation set of later-finishing training complexes; primary selector chosen by tie-break (S2: three pLDDT features) | Validation set was uninformative (5 informative of 20), so the choice rests on cross-validation and parsimony |
