# DRAFT (v1, computational preprint) — Selecting the right pose from cyclic-peptide co-folding samples

Status 2026-10-27: Introduction, Methods and Limitations are written from committed artifacts. **Results and Abstract numbers are placeholders ("⟨…⟩") until the one-shot evaluation (`stageB_eval.py`, PREREG A2/A3/A4/A5) has run. Nothing in ⟨⟩ may be filled by hand.** Wet-lab validation is deferred to v2.

## Title (working)
A ground-truth-free pose selector for co-folded cyclic-peptide complexes, evaluated post-cutoff across receptors under a pre-registered protocol

## Abstract (template)
Co-folding models (Boltz-2, AlphaFold3-class) produce many samples per complex, but cyclic peptides are a case where the model's own top-ranked sample is a weak guide: ring closure is not enforced (about 75% of samples in our pilot had a valid ring) and, in a 26-complex pilot, the default pick was no better than a random sample (80.8% vs 80.3% DockQ ≥ 0.23) while the best-of-25 oracle reached 96.2%. We built a ground-truth-free selector (within-complex z-scored confidence, ring-geometry, clash and consensus features; L2 logistic regression) and evaluated it once on ⟨N_test⟩ post-cutoff experimental cyclic-peptide complexes from ⟨K⟩ receptor clusters, against six pre-registered baselines. Top-1 success (DockQ ≥ 0.23) was ⟨S⟩ for the selector versus ⟨strongest baseline⟩ for the strongest baseline (paired receptor-cluster bootstrap difference ⟨Δ, CI⟩); on receptors absent from training ⟨novel-receptor result⟩. ⟨Outcome sentence per the pre-registered claim rule — either "the selector is best on both" or "it is not; here is what is and is not recoverable".⟩

## 1. Introduction
1. Cyclic peptides bind protein surfaces that small molecules cannot, and co-folding models now predict peptide–protein complexes. Practitioners pick one sample per complex, usually by the model's confidence score.
2. For cyclic peptides this choice matters more than for linear ones: Boltz-2 `cyclic: true` does not enforce covalent closure, non-canonical residues enter as CCD modifications, and many complexes have a high random-sample success rate that hides selection error.
3. Sample selection for co-folding has been studied for protein–protein and linear protein–peptide complexes (confidence metrics versus DockQ; see Related work). Cyclic-peptide–specific selection, with ring geometry as a feature and evaluation on receptors unseen by the selector, has not been reported to our knowledge (not claimed as "first"; the search was not systematic).
4. Contribution: (i) a post-cutoff cyclic-peptide complex benchmark built from deposited covalent-link records (884 complexes in the manifest; capped evaluation subset reported below); (ii) a ground-truth-free selector; (iii) a pre-registered, one-shot evaluation with receptor-cluster bootstrap and a novel-receptor subset; (iv) an honest account of what the default pick does and does not get right.

## 2. Methods
### 2.1 Data
- Manifest: 884 PDB complexes from deposited covalent-link records; deposit cutoff 2023-10-01. Training set = pre-cutoff complexes; evaluation set = post-cutoff. Receptor clusters at 40% identity (`receptor_cluster40`); complexes of one receptor cluster are never treated as independent.
- Two tiers, never merged: STRICT (canonical-residue peptides) and non-canonical (CCD modifications).
- Leakage: Boltz-2 training cutoff taken as 2023-06 from secondary sources (unverified); post-cutoff by stated dates, not provably unseen.
### 2.2 Co-folding
Boltz-2 2.2.1, 25 diffusion samples per complex, seed 0, ColabFold MSA server for receptors, empty peptide MSA, no template or pocket conditioning, ground-truth coordinates never provided. Runs on AWS spot GPUs (16 GB) and an NVIDIA GB10 (ARM, torch 2.14+cu130); DockQ for one complex was identical across the two hardware platforms (9CDT_2).
### 2.3 Metrics
Primary: top-1 success = DockQ v2 of the selected sample ≥ 0.23 (also ≥ 0.49), peptide as ligand against the receptor chain with most native contacts. Chains are renamed identically in prediction and truth, so no chain-mapping search is used.
### 2.4 Selector
Features per sample (26, all ground-truth-free): Boltz confidences (confidence_score, ipTM, pTM, interface pLDDT, …), closure-bond and angle deviation, clash count, interface contact density, and consensus features (mean peptide RMSD to the other samples, largest pose cluster). Features are z-scored within complex; L2 logistic regression (C default) trained on TRAIN to predict DockQ ≥ 0.23; at test time the argmax within each complex is chosen. A code-level assertion rejects any ground-truth column (`iRMSD`, `LRMSD`, `DockQ`, …); an earlier feature screen of mine did leak those columns and was excluded.
### 2.5 Baselines (fixed a priori)
Default `confidence_score` (high), ipTM (high), pTM (high), interface pLDDT (high), ring strain (low), clash count (low). Reference rows: random-sample expectation and oracle best-of-N.
### 2.6 Statistics and claim rule
Paired receptor-cluster bootstrap (4,000 resamples), 95% percentile CI of selector minus the strongest baseline, where the strongest baseline is chosen on the test set (conservative). The claim "selector is best" requires CI lower bound > 0 on ALL test complexes AND on the novel-receptor subset (receptor cluster absent from training) at DockQ ≥ 0.23. Otherwise the result is reported as not supported.
### 2.7 Pre-registration and amendments
Protocol committed before any structure was generated. Amendments, all made before any Stage B sample was scored: A1/A2 selector and claim rule; A3 compute strategy; A4 test capped at 1,200 and train at 600 true tokens (compute limit: 4 test complexes excluded, 34 train complexes excluded); A5 evaluation trigger (all test done, or 6 h after the commit) with train = whatever finished by then. Test complexes not generated by the trigger are listed, not dropped silently.

## 3. Results (placeholders)
- 3.1 Pilot (n=26 of 40; 14 did not run: 2 YAML-typing bugs since fixed, 8 PDB components missing from Boltz's library, 4 GPU-OOM). Reported as-is: default 80.8% [65, 96], ipTM 76.9%, random 80.3%, oracle 96.2% [88, 100]; oracle − default = 15.4 pp (CI 3.8–30.8), so the pre-registered no-headroom stop rule did not trigger. Headroom is 4 complexes. Within-complex ipTM AUROC 0.56.
- 3.2 Stage B primary: table of ⟨success of S, each baseline, random, oracle⟩ at DockQ ≥ 0.23 and ≥ 0.49 — ⟨from `results/stageB_eval.json`⟩.
- 3.3 Novel-receptor subset — ⟨…⟩.
- 3.4 STRICT vs non-canonical tiers — ⟨…⟩.
- 3.5 Selector coefficients (top features) — ⟨…⟩; ring-validity rate of selected vs default samples — ⟨…⟩.
- 3.6 Failure analysis: complexes where no sample succeeds (oracle failures) and where S loses to default — ⟨…⟩.

## 4. Limitations (known now)
- Single co-folding model (Boltz-2); Chai-1 not run.
- Compute caps (A4) bias the test set toward smaller complexes; the largest (≥1,200 tokens) are excluded and listed.
- Unverified training cutoffs; residual leakage via homologous receptors is possible (receptor-cluster overlap is reported).
- 8 pilot complexes with missing CCD components (the newest depositions) are not runnable; the evaluated set is skewed toward older, canonical entries.
- High random-sample base rate (~80% in the pilot) limits headroom and widens CIs.
- No wet lab in v1. Hashed, pre-registered wet-lab predictions are to be added in v2.

## 5. Related work (to cite; no novelty claims)
MFBind, MF-LAL, LLMol, Pepti-Agent, PepThink-R1, UnibindMD, cofolding-guided cyclic design with ncAAs, AfCycDesign, RFpeptides, protein–peptide AF-Multimer/AF3 benchmarks. Links and one-line notes: `docs/20261026_PRIOR_ART_INTEGRATED_CLAIM.md` (abstract-level reads; add full-text reads before submission).

## 6. Outputs needed to finish
`results/stageB_eval.json`, scored train/test jsonl, test-exclusion list, figures (success bars with CIs, headroom/oracle plot, feature coefficients), supplementary pre-registration + amendment log (`PREREG.md`).
