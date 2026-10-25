# A target-agnostic, structure-based predictor of radioligand renal retention generalizes across molecular targets

**Preprint draft — v0.2 (2026-10-24; count/class-consistency pass). Computational study; prospective wet-lab validation declared as future work.**

*Authors:* [to be completed] · *Correspondence:* [to be completed]

---

## Abstract

Renal retention is the dose-limiting toxicity of peptide-receptor radioligand therapy: filtered radiopeptides are reabsorbed in the proximal tubule and the residualizing radiometal is trapped, so for most targeted radioligands the kidney, not the tumour, caps the deliverable activity. The determinants are mechanistically understood — glomerular filtration followed by megalin/cubilin-mediated reabsorption, modulated by net charge, molecular size, cleavable linkers and albumin binding — yet this knowledge is applied empirically, one construct at a time, and **no model predicts a radioligand's renal retention from its structure in a way that transfers across molecular targets.** We assemble the first structured, renal-protection-stratified, cross-target radioligand renal-biodistribution dataset (163 constructs across eleven target classes, each with provenance, structure, and a mandatory renal-protection flag) and show, under a leave-one-target-out protocol, that renal retention is **structure-learnable and generalizes to target classes absent from training** (mean within-held-out-target Spearman ρ = 0.27, 95% CI [0.01, 0.51], permutation p = 0.036), whereas the field-standard net-charge heuristic does not (ρ = −0.05, p = 0.73). Ablations show net charge is the dominant feature but imaging timepoint, modality, residualizing metal and cleavable linker each contribute. We formalize the experimentally-established two-route (cationic-megalin / anionic) reabsorption biology into an interpretable mechanistic grey-box model, and frame radioligand property prediction as a **target-specific binding × target-agnostic pharmacokinetic decomposition** that explains why a renal-retention model can be learned once and reused across programs. The predictor is preliminary — effect sizes are modest and confidence intervals wide at this scale — but it establishes cross-target structural learnability of radioligand renal retention and provides the dataset, evaluation protocol and interpretable model to build on. Data and code are released.

---

## 1. Introduction

Radioligand therapy (RLT) delivers a cytotoxic radionuclide to tumour cells via a target-binding vector. Its therapeutic index is frequently set not by tumour uptake but by the **kidney**: small filtered radiopeptides are reabsorbed in the proximal tubule by the megalin/cubilin endocytic system and the residualizing radiometal–chelate is retained in lysosomes, so published ^177Lu-labelled αvβ6 peptides, for example, have tumour-to-kidney absorbed-dose ratios below 1, and the only in-human αvβ6 RLT administration to date gave a kidney dose of 0.66 Gy/GBq — above the ^177Lu-PSMA-617 benchmark of 0.42 Gy/GBq.

The biology of this retention is mature. Glomerular filtration followed by megalin-mediated reabsorption is established across structurally unrelated radiopeptides (ref. Vegt 2011, below); the modulating levers — net charge, molecular size, basic-residue content, cleavable linkers, albumin binders, and amino-acid/gelofusine co-infusion — are individually quantified; and the charge dependence is known to be **non-monotonic**: renal uptake is lowest near net charge −1 and rises at both positive and strongly negative charge (ref. Bapst & Eberle 2017), with highly anionic poly-glutamate minigastrins among the most retained radiopeptides. Two distinct reabsorption routes — a cationic, lysine-inhibitable route and an anionic, poly-glutamate-inhibitable route — have been demonstrated experimentally (ref. Melis 2007).

Despite this, renal optimization remains empirical medicinal chemistry. The computational-prediction literature does not fill the gap: structure-based renal predictors exist only for conventional small-molecule drugs, predict whole-body clearance, and are target-blind (e.g. Dave & Morris 2015); radioligand kidney-dose models that are genuinely radiopharmaceutical are driven by per-patient PET imaging and are single-target (PSMA), so they cannot evaluate a molecule that has not been synthesized and imaged (e.g. Yazdani 2025; Abdollahi 2025, preprint). Mechanistic PBPK models carry a kidney compartment but treat retention as a lumped, fixed-fraction or empirical parameter fit per case, encode charge at most as a qualitative label, and are fit to a single target class (e.g. Zaid 2021; Kletting 2016).

**The open problem** is therefore a model that takes a radioligand's molecular structure and predicts its kidney retention (or tumour-to-kidney ratio) and that **generalizes across molecular targets**. This is plausible precisely because renal handling, unlike target binding, is a shared physicochemical process: the same megalin system reabsorbs radiopeptides for unrelated receptors. We make this explicit as a decomposition — a radioligand's in-vivo behaviour factorizes into a *target-specific binding* term and a *target-agnostic pharmacokinetic (renal)* term — and test whether the renal term can be learned from structure and transferred to unseen targets.

**Contributions.** (1) The first structured, cross-target, renal-protection-stratified radioligand renal-biodistribution dataset (163 constructs, eleven target classes). (2) Evidence, under leave-one-target-out evaluation with leakage control and uncertainty quantification, that radioligand renal retention is structure-learnable and generalizes across targets, while the net-charge heuristic does not. (3) An interpretable mechanistic grey-box that formalizes the known two-route reabsorption biology, and the PK–binding decomposition framing. We are explicit about what is *not* novel (the charge non-monotonicity and the two-route biology are prior art, cited) and about the study's preliminary scale.

---

## 2. Results

### 2.1 A cross-target, protection-stratified renal-biodistribution dataset

We curated kidney biodistribution for 163 radioligand constructs spanning eleven target classes — PSMA, SSTR2, GRPR, FAP, integrin αvβ6, integrin αvβ3, MC1R, CCK2, NTS1, GLP-1R and FOLR1 — from primary literature, through a citation-integrity gate that quarantines any record lacking a resolvable DOI/PMID, a renal label, or a renal-protection annotation. Each construct carries structure (one-letter sequence and/or canonical SMILES), chelator, radiometal, albumin-binder and cleavable-linker flags, and a **mandatory renal-protection status that is never imputed** (mixing amino-acid/gelofusine-protected with unprotected measurements silently corrupts any charge model). We treat each (construct, timepoint) measurement as one observation with imaging timepoint as a covariate, yielding 103 charge-computable mouse %ID/g observations; absolute labels are never pooled across units (Gy/GBq vs %ID/g) or across timepoints. Net charge at pH 7.4 is computed deterministically (Henderson–Hasselbalch on the sequence for peptides; a chelator-aware group-contribution calculation on SMILES for small molecules), or taken from the paper when charge is set by terminal modifications not encoded by sequence.

### 2.2 The net-charge heuristic does not generalize across targets

Under leave-one-target-out (LOTO) cross-validation — train on all target classes but one, predict the held-out class, score by the mean within-held-out-target Spearman correlation (the estimand for ranking constructs within an unseen target; pooling across classes is confounded by per-class scale) — the field-standard **signed net-charge heuristic has mean-per-class ρ = −0.05 (95% CI [−0.34, 0.18], permutation p = 0.73): no better than chance.** This is the expected consequence of the known charge non-monotonicity: a single signed-charge term cannot rank retention when both cationic and anionic ligands are retained.

### 2.3 Radioligand renal retention is structure-learnable and transfers across targets

A learned model on interpretable physicochemical features (net positive/negative charge, residualizing metal, albumin binder, cleavable linker, imaging timepoint, modality) **generalizes to unseen target classes: mean-per-class ρ = 0.27 (95% CI [0.01, 0.51], permutation p = 0.036)** under identical LOTO (Fig. 2), with cluster bootstrap by construct (so multimers/replicates of one molecule cannot leak between folds). Per-class, held-out generalization is strong for GRPR (ρ = 0.80), CCK2 (0.68) and MC1R (0.62), moderate for αvβ3 (0.41) and SSTR2 (0.25), and fails for GLP-1R and NTS1 (see §2.6). This is, to our knowledge, the first demonstration that radioligand renal retention can be predicted from structure for a target class held out of training.

### 2.4 An interpretable mechanistic grey-box formalizes the two-route biology

We cast the experimentally-established reabsorption biology into a differentiable grey-box: log kidney %ID/g as a sum of a saturable cationic (megalin) route in net positive charge, a saturable anionic route in net negative charge, a residualizing-metal term, an albumin-binder term, a cleavable-linker term, a timepoint term and a small-molecule-route term. Fit across all targets, every term takes a physically sensible sign (both charge routes positive — reproducing the known U-shaped charge dependence as explicit mechanism; residualization and albumin binding increase retention), and the two fitted Michaelis constants are in a physiological range. Under LOTO the grey-box is directionally positive (mean-per-class ρ = 0.17, 95% CI [−0.07, 0.37], p = 0.20) but **not statistically significant at this sample size and does not outperform the black-box model**; its value is interpretability and mechanistic transparency, not predictive superiority. We report this plainly rather than over-claim.

### 2.5 Ablations: charge dominates, but every covariate contributes

Removing feature groups from the learned model and repeating LOTO (mean-per-class ρ, full model = 0.27): removing **net charge** collapses performance (Δ = −0.42), confirming charge as the dominant determinant; removing **imaging timepoint** (Δ = −0.26) validates modelling retention as a function of time rather than pooling; removing **modality** (peptide vs small molecule; Δ = −0.17), **cleavable linker** (Δ = −0.11) and **residualizing metal + albumin binder** (Δ = −0.08) each degrade generalization. No single non-charge covariate is sufficient, but each is necessary — consistent with the mechanistic picture.

### 2.6 Quasi-prospective temporal validation, and where transfer fails

Training on constructs published up to 2021 and testing on 2022–2026 constructs gives modest positive generalization (pooled ρ = 0.12; held-out αvβ3 ρ = 0.58, SSTR2 0.40), a weaker signal than the LOTO result and an honest indicator of the data's heterogeneity. Transfer fails systematically for two classes: **NTS1** (ρ ≈ −0.9 for every model, including the black box), where the Demotensin analogues differ in retention at essentially identical net charge — retention is driven by metabolic stabilization, not charge, which no current feature captures; and **GLP-1R**, where retention is dominated by a cleavable-linker effect under-identified at n = 2 cleavable constructs. These failures delimit the model's applicability domain: it predicts charge- and residualization-driven retention, not retention set by non-charge structural factors.

### 2.7 Robustness to sequence-level leakage

Because the RGD motif is shared between αvβ3 and αvβ6, leave-one-target-out still permits sequence overlap across folds. Under a stricter **leave-one-sequence-cluster-out** split (single-linkage clustering by sequence 3-mer Jaccard ≥ 0.5; small molecules by chemotype; 23 clusters, 15 held out, n = 95), the learned model still exceeds the net-charge heuristic (pooled Spearman 0.13 vs 0.07). The margin is smaller than the target-out estimate, consistent with modest generalization, but the direction is preserved — the signal is not an artifact of near-duplicate constructs.

### 2.8 In-silico design application: the model recovers the field design rule

Because the renal term is target-agnostic, the predictor ranks renal-engineering modifications for a radioligand whose **binder is held constant** (here the αvβ6 RGD binder; target affinity/selectivity preserved by construction). Fitting the mechanistic grey-box on all data and scoring a net-charge × chelator grid at a fixed preclinical readout (4 h, residualizing ^177Lu), predicted kidney retention is **minimized near net charge −1 to 0 (≈5–6 %ID/g) and rises at both charge extremes** — the known U-shaped design rule recovered as an emergent property of the fitted model, now ranked quantitatively. A brush-border-cleavable linker (an established additional −70 to −77% lever; Trachsel 2023, Bendre 2020) is **not** scored by the model because, in the present dataset, the only cleavable constructs are GLP-1R exendins with high kidney uptake, perfectly confounding the cleavable flag with that class; it is applied as a known orthogonal lever rather than inferred. A prospective, synthesis-backed demonstration is future work (§4).

---

## 3. Methods

**Dataset curation.** Primary-literature search across eleven target classes; extraction restricted to values stated in tables or verbatim text, with a separately-flagged, lower-confidence figure-digitized tier used only in sensitivity analysis. Every record carries DOI/PMID provenance, species, timepoint and a mandatory renal-protection flag; duplicates are resolved on (construct, DOI); the same construct measured in multiple tumour models is aggregated to one point (median) to avoid pseudo-replication.

**Charge computation.** Peptides: Henderson–Hasselbalch net charge at pH 7.4 over ionizable side chains and termini, plus the metal-complex charge of the chelator. Small molecules: group-contribution Henderson–Hasselbalch over SMARTS-matched ionizable groups, with the entire chelator macrocycle excluded and replaced by the metal-complex charge. Paper-stated net charge overrides computation where terminal modifications (acetylation, succinylation) are not sequence-encoded.

**Models.** Baselines: signed net charge, |net charge|. Learned model: gradient-boosted trees on the interpretable feature set. Mechanistic grey-box: a bounded-Michaelis, ridge-regularized two-route saturable model fit by least squares on log %ID/g.

**Evaluation.** Leave-one-target-out cross-validation; primary metric mean within-held-out-target Spearman; cluster bootstrap by construct for 95% CIs; within-class permutation tests for p-values; models compared on a common set of classes all can rank. Temporal split by publication year. Ablation by feature-group removal. All seeded and reproducible via the released `renal_paper_results.py`.

---

## 4. Discussion

We show that radioligand renal retention — the central dose-limiting liability of RLT — is learnable from molecular structure and **generalizes to target classes never seen in training**, something the field's net-charge heuristic cannot do. The result is enabled by a cross-target dataset and by framing renal retention as a target-agnostic pharmacokinetic term, biologically justified by the shared megalin mechanism. We deliberately scope the claims: the charge non-monotonicity and the two reabsorption routes are prior art, which our mechanistic model formalizes rather than discovers; the effect sizes are modest with wide confidence intervals; the interpretable grey-box does not beat the black box at this scale; and transfer fails where retention is set by non-charge factors (NTS1 stabilization, GLP-1R linker cleavage).

**Limitations.** Sample size is in the low hundreds of observations. Much published kidney biodistribution exists only in figures: a bounded figure-digitization attempt (two independent readers, gridline interpolation, explicit read-uncertainty, records held in a separate sensitivity tier) yielded only seven defensible records, all for sequence-null (non-canonical) GRPR/SSTR constructs that do not enter the charge-computable analysis, leaving the primary result unchanged; most figure-only sources were access-gated. Systematic scale-up therefore requires un-gated figure access and dedicated digitization tooling with human QC, not automated reading. We also observed a data-quality hazard relevant to the field: in two papers, text/supplementary values retrieved programmatically contradicted the plotted figures, so figure reads were treated as authoritative. Species, tumour model and protocol differ across sources and are modelled as covariates but leave residual batch effects; the mouse-%ID/g to human-Gy/GBq bridge is not closed here.

**Future work.** (i) Scale the dataset to 400–600 constructs via systematic figure digitization with an explicit read-error model; (ii) strengthen the mechanistic model against PBPK and black-box baselines under sequence-cluster and temporal cross-validation; (iii) **prospective validation**: synthesize a predicted low-renal-retention αvβ6 series (binder held constant, affinity and selectivity preserved), radiolabel, and measure kidney %ID/g and tumour-to-kidney ratio against prediction. The present study provides the dataset, protocol and model required for that program.

---

## 5. Data and code availability

Dataset (`renal_seed_corpus.jsonl`; figure-digitized sensitivity tier `renal_figure_tier.jsonl`), charge models (`renal_features.py`, `renal_smiles_charge.py`), mechanistic model (`renal_mechmodel.py`), evaluation (`renal_surrogate.py`, `renal_eval.py`), reproducible results pipeline (`renal_paper_results.py`), design loop (`renal_design.py`) and figure generation (`make_figures.py` → `figures/`) are released. Figures: **F1** dataset composition by target class; **F2** cross-target generalization with 95% CIs (learned vs grey-box vs net-charge); **F3** model-guided design U-shape; **F4** feature ablations. Every data record carries primary-source provenance.

## 6. References (verified; to be formatted to journal style)

1. Vegt E, et al. Renal toxicity of radiolabeled peptides and antibody fragments. *J Nucl Med* 2010;51(7):1049–1058. DOI 10.2967/jnumed.110.075101.
2. Vegt E, et al. Reducing renal uptake of radiolabeled peptides using … megalin. *EJNMMI* 2011;38(4):623–632. DOI 10.1007/s00259-010-1685-9.
3. Melis M, et al. Indication for different mechanisms of kidney uptake of radiolabeled peptides. *J Nucl Med* 2007;48(4):596–601. PMID 17401097.
4. Bapst JP, Eberle AN. Radiolabeled α-MSH peptides … net charge and renal uptake. *Front Endocrinol* 2017;8:93. DOI 10.3389/fendo.2017.00093.
5. Dave RA, Morris ME. Quantitative structure–pharmacokinetic relationships for renal clearance. *Drug Metab Dispos* 2015;43(1):73–81. DOI 10.1124/dmd.114.059857.
6. Yazdani E, et al. ML prediction of kidney/lesion absorbed dose for ^177Lu-PSMA-617. *Int J Radiat Oncol Biol Phys* 2025;123(4):891–908. DOI 10.1016/j.ijrobp.2025.05.014.
7. Zaid NRR, et al. A PBPK model for in vivo alpha-particle generators targeting NETs in mice. *Pharmaceutics* 2021;13(12):2132. DOI 10.3390/pharmaceutics13122132.
8. Kletting P, et al. Optimized peptide amount and activity for ^90Y-DOTATATE therapy. *J Nucl Med* 2016;57(4):503–508. DOI 10.2967/jnumed.115.164699.
9. Bendre S, et al. Met-Val-Lys brush-border-cleavable linker for radiopeptides. *Molecules* 2020;25(17):3854. DOI 10.3390/molecules25173854.

*(Construct-level primary sources — ~60 papers underlying the 163-construct dataset — are enumerated in the dataset provenance records.)*
