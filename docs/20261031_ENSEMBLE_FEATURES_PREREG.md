# Idea A pilot: do simulated-ensemble (physics) features carry a lab-independent permeability signal? Pre-registration (2026-10-28 night, committed BEFORE any label-vs-feature analysis)

Status: **pre-registration + data findings. No ensemble-feature/label analysis has been run.** The only label look so far: agreement of the published tables' PAMPA values with our corrected annotation (join QA, below). This is a go/no-go for further compute, never paper evidence.

## 1. What was found while excavating (primary sources opened 2026-10-28)
| item | finding | source |
|---|---|---|
| CREMP (main) | 36,198 homodetic 4-6-mers, CC BY 4.0, pickle 28.95 GB, sdf 20.53 GB; **does not contain CycPeptMPDB peptides** (earlier excavation: 0 of 8,466 SMILES match). The S3 copy `datasets/cremp_partial/` is incomplete (sdf 13.96 GB vs 20.53 GB). | zenodo.org/records/7931445 (API metadata) |
| **CREMP-CycPeptMPDB** | **3,258 CycPeptMPDB macrocycles, 8.68 M unique conformers (27.8 M incl. rotamers; median 8,279 per peptide), CREST/GFN-xTB ensembles, with CycPeptMPDB permeability annotations. CC BY 4.0.** pickle 11.58 GB, sdf 8.33 GB. Sci Data 2024, doi 10.1038/s41597-024-03698-y. | zenodo.org/records/13334335; summary file `summary_cycpeptmpdb.csv` (md5 2833a05eb88159d096b0b7202f20f87c, 3,258 rows, columns incl. CycPeptMPDB_ID, smiles, permeability, ensemble energies) |
| **CycPeptMPDB-4D** (published 2026-07-09, Liu et al., Singapore) | 5,160 peptides with explicit-water and hexane MD; descriptor CSV with `Source`, `PAMPA`, per-solvent average Rg, RMSD (all/backbone), 3D SASA, NPSA, PSA, water desolvation free energy. CC BY 4.0. CSV md5 e4b957982bd572aba5029963804e0524 (1.89 MB; trajectories 1.7 GB zip not downloaded). | zenodo.org/records/21274695 |
| AnewDPSA (2026-09-02, Yu & Guo) | processed MD feature tables for CycPeptMPDB training + external sets ("regime-aware" cross-environment descriptors), code; 5.5 MB. CC BY 4.0. md5 f8156cab32a13f9f06b7cefd03e4f365. Not used as features here (prior-art overlap; kept for a later comparison). | zenodo.org/records/22249744 |
**Prior-art consequence:** simulated two-solvent ensemble descriptors for CycPeptMPDB permeability have been published (4D, AnewDPSA). We therefore claim nothing about the features; the only open question is whether they help under **laboratory shift**, which these papers (as far as extracts show; not verified) do not test.

## 2. Join to our corrected CycPeptMPDB set (6,960 labelled peptides, 41 corrected sources) and power
- 4D: 4,918 labelled peptides joined, source label agreement 100 %, PAMPA agreement r = 0.9998 (max abs diff 0.51 from the database's own value rounding/aggregation). **Only 5 sources**: Townsend 2,761; Kelly 1,396; Furukawa-2016 662; Naylor 50; Wang 49.
- CREMP-CycPeptMPDB: 3,000 labelled peptides joined (permeability r = 0.987), 22 sources but **Townsend 2,450, Furukawa-2016 283, then 49/45/44/17/16/14/14/11/10/9/8/6/6/5/5/4/1/1/1/1**: only 5 sources have >= 30 peptides and 2 have >= 100. The subset is biased to smaller peptides (mean 6.54 monomers vs 8.05; TPSA 162 vs 202; N-methyl 1.33 vs 2.37) and has 638 flat structures for 3,000 peptides (stereoisomer groups).
- **Consequence:** neither table supports a lab-cluster inference with >= 5 informative held-out labs. By the rule in §6 the formal gate is **UNDERPOWERED**; this pilot can only be **descriptive per-lab** (leave-one-lab-out for the 5 labs with >= 40 joined peptides). Computing the 11.6 GB CREMP ensembles would not add labs (same two big labs) and is **not done** (saves a spot job of about USD 1-2); revisit only if a larger lab-diverse ensemble table becomes available.

## 3. Features (fixed now from physical reasoning; not selected by label correlation)
From `CycPeptMPDB-4D.csv`, per peptide: Water_avgGR, Hexane_avgGR, Water_avgRMSD_All, Water_avgRMSD_BackBone, Hexane_avgRMSD_All, Hexane_avgRMSD_BackBone, Water_Desolvation_Free_Energy, {Water,Hexane}_3D_{SASA,NPSA,PSA}. Derived (defined now): dPSA = Water_3D_PSA - Hexane_3D_PSA; dPSA_frac = Water_3D_PSA/Water_3D_SASA - Hexane_3D_PSA/Hexane_3D_SASA; dRg = Water_avgGR - Hexane_avgGR; dRMSD = Water_avgRMSD_All - Hexane_avgRMSD_All. Feature set **E** = all of the above (no further selection).

## 4. Arms (HistGradientBoostingRegressor, max_iter 150, learning_rate 0.1, random_state 0 — the settings of the committed stratification analysis; no tuning)
D = the 2D descriptor families of `stratification/common.py` (physchem, ring_topology, nme_pattern, chirality, composition); F = chirality-aware Morgan count fingerprint (r2, 2048, useChirality); E; **D+E**; F+E. All arms trained and evaluated on the **same 4D-joined subset** (the full-set 2D baselines of the committed analysis are reported separately for reference only).

## 5. Protocol
Labels: PAMPA log Papp; training labels z-scored within training sources (`source_normalize`, sources < 20 pooled), computed on the training sources only; evaluation = Spearman between prediction and raw PAMPA **within the held-out lab** (monotone-invariant to the lab's own scaling). **Primary: leave-one-lab-out** over the labs with >= 40 joined peptides (Townsend, Kelly, Furukawa-2016, Naylor, Wang); the training set is all other joined peptides. Secondary (reference): flat-structure-grouped 5-fold within the pooled set. Uncertainty: per-lab 95 % CI by cluster bootstrap over flat structures (B = 1000, seeded); no across-lab CI is claimed (5 labs). Reported: per-lab Spearman for every arm, paired difference (D+E minus best of D, F, D+F-free baselines; best chosen per lab by the committed order D, F), and the count of labs with a difference >= +0.03.

## 6. Decision rule (fixed now)
- **SUPPORTED (exploratory, 5 labs)** only if D+E beats the best 2D arm (D or F) by >= +0.03 Spearman in >= 4 of 5 held-out labs AND the mean paired difference is >= +0.03 AND the per-lab 95 % CI lower bound is > 0 in >= 3 of 5 labs; **NOT SUPPORTED** if D+E is within ±0.03 or below in >= 3 labs; otherwise **MIXED**.
- **Formal gate (lab-cluster CI lower bound > 0) = UNDERPOWERED** whatever the numbers, because fewer than 5 informative labs per budget are available beyond the three large ones; a miss is worded "no gain detectable", never "no gain". This pilot may motivate further compute only if SUPPORTED; it can never be cited as paper evidence.

## 7. Controls (must pass or the run is invalid)
1. Shuffled labels (within-source permutation, 5 seeds): mean held-out Spearman within ±0.05 of 0 for every arm.
2. Planted: replace the label of every peptide by z(dPSA) + 0.5 N(0,1) (computed per source); D+E must recover it (held-out Spearman >= 0.5) and D alone must not exceed D+E - 0.2 (the signal lives in E).
3. Decoy: permute the E columns across peptides (row shuffle, 5 seeds); D+E-decoy must be within ±0.02 of D alone on the mean over labs.

## 8. Caveats stated up front
Simulated ensembles come from a fixed force field and solvents, not from the assays; labels are noisy (between-report spread 0.867 ± 0.631 log units vs 0.206 ± 0.191 within, per the survey; unverified extract); 4D coverage is biased (5,160 of 8,466; 56 % Townsend); one pooled-lab group dominates training when other labs are held out; MD descriptors may encode size and polarity already in D (the planted control addresses recoverability, not novelty).

## 9. Results (run 2026-10-28 night, local CPU, spend USD 0; code `research/guangzhou_all_atom/cyclic_llm/ensemble_features/run_ideaA.py`, outputs `results/ideaA_controls.json`, `results/ideaA_results.json`)
**Controls (run first, all passed):** shuffled labels, mean held-out Spearman over labs D -0.003, E +0.015, D+E +0.023 (all within ±0.05); planted dPSA label: E 0.814, D+E 0.814, D 0.122 (recovered, signal lives in E); decoy (E columns row-permuted): D+E 0.411 vs D 0.409 (within ±0.02).
**Real contrast, leave-one-lab-out, 4,918 joined peptides (HistGBM fixed settings), held-out Spearman on raw PAMPA within the held-out lab:**
| held-out lab (n) | D | F | E | D+E | F+E | D+E minus best 2D [flat-cluster 95 % CI] |
|---|---|---|---|---|---|---|
| Townsend (2,761) | 0.327 | 0.354 | 0.055 | 0.340 | 0.351 | -0.013 [-0.089, 0.062] (vs F) |
| Kelly (1,396) | 0.285 | 0.464 | 0.149 | 0.350 | 0.324 | -0.113 [-0.240, 0.018] (vs F) |
| Furukawa-2016 (662) | 0.398 | -0.009 | 0.078 | 0.326 | 0.036 | -0.072 [-0.128, -0.018] (vs D) |
| Naylor (50) | 0.243 | 0.272 | 0.250 | 0.206 | 0.361 | -0.066 [-0.287, 0.149] (vs F) |
| Wang (49) | 0.792 | 0.452 | 0.761 | 0.763 | 0.548 | -0.029 [-0.131, 0.064] (vs D) |
| mean over labs | 0.409 | 0.307 | 0.259 | 0.397 | 0.324 | -0.059 |
**Verdict (pre-registered rule): NOT SUPPORTED** (0 of 5 labs with a difference >= +0.03; mean paired difference -0.059). Formal gate: **UNDERPOWERED** (5 labs, 2 of them n ~ 50), so a miss means "no gain detectable", not "no gain".
Descriptive notes (not part of the rule): (i) the "best 2D arm" is chosen per lab after seeing the held-out score, which is conservative against E; against D alone the differences are Townsend +0.013, Kelly +0.065, Furukawa -0.072, Naylor -0.037, Wang -0.029, i.e. mixed in sign; (ii) E alone is weak (mean 0.259; Wang 0.761 on 49 peptides is the exception); (iii) pooled flat-grouped 5-fold (reference only, not lab-shifted): D 0.650, F 0.714, E 0.457, D+E 0.645, F+E 0.688; (iv) the lab-shifted Spearman for every arm is far below the grouped one, consistent with the earlier leave-labs-out finding.
**Decision:** no-go on further compute for ensemble features as a lab-independent signal on this data. Not computed: the 11.6 GB CREMP-CycPeptMPDB ensembles (would add the same two large labs only), AnewDPSA features, per-conformer physics. Not evidence for the paper.
