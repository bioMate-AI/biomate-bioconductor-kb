# Integrin subtype selectivity of RGD-type ligands: a multi-target, same-assay benchmark

STATUS: Sections 0-1 (tasks, nulls, hyper-parameters) were written and committed (adac13af4) BEFORE any model was fitted. Section 2 (deviations), 3 (results) and 4 (verdict) were added after the fits.

## 0. Data sources (all values verbatim, IC50 in nM)

| key | paper | access | how extracted |
|---|---|---|---|
| kapp2017 | Kapp TG et al., Sci Rep 2017;7:39805, PMID 28074920, PMC5225454 (CC BY) | Europe PMC fullTextXML | Tables 1 and 2 are JPEG images in the XML (`<graphic>` only, no `<tr>` cells). Images downloaded from the PMC CDN (kept in `src_raw/`), values transcribed BY HAND (visual read, two passes at 1.3x zoom) into `data/kapp2017_table{1,2}_transcribed.tsv`. This is the single largest parsing risk; there is no OCR cross-check (tesseract is not installed). |
| quigley2023 | Quigley NG et al., RSC Med Chem 2023, PMID 38099056, PMC10718521, Table 1 (text table in XML) | Europe PMC XML | parsed from XML `<tr>` cells by build_matrix.py (src_raw/quigley2023_PMC10718521.xml) |
| tomassi2021 | Tomassi S et al., J Med Chem 2021, PMID 33961417, PMC8279406, Table 1 (text table in XML) | Europe PMC XML | parsed from XML by build_matrix.py (src_raw/tomassi2021_PMC8279406.xml) |

Verification of the series quoted in the brief (they all agree with the primary text):
* Quigley Table 1 matches every value in the brief (FF/YF/FY/YY, avb6/avb8/avb3/a5b1). The printed FF a5b1 CI "(115-193)" does not contain the point estimate 226 (typo, as warned); CIs are not used anywhere.
* Tomassi Table 1 matches the brief (cmpd 1-6). Note: PMC8279406 is titled "Halting the Spread of Herpes Simplex Virus-1: The Discovery of an Effective Dual avb6/avb8 Integrin Ligand"; and PMC10718521 is titled "Complexity of avb6-integrin targeting RGD peptide trimers ..." - the IDs are right, the table is the one described.
* Tomassi's table also lists cilengitide (avb3 1.4, a5b1 22) and RTDLDSLRT (avb6 38, avb8 122) from ITS assay; these differ from Kapp (cilengitide avb3 0.61, a5b1 14.9; RTDLDSLRT avb6 29.5, avb8 320). They are stored in matrix.csv (source=tomassi2021) as additional rows of the same ligand, NOT merged.

## 1. Pre-registered tasks (fixed before fitting)

Primary dataset = Kapp 2017 only (one lab, one assay, 34 ligands x 6 integrins). The Quigley and Tomassi series come from other labs/assay runs; they are never mixed into the primary model fits (inter-lab offset is itself measured, task X below).

Response: pIC50 = 9 - log10(IC50 nM). Censoring: "> 10000" -> right-censored, bound pIC50 <= 5.0. Training convention: censored cells are imputed AT the bound (5.0) (judgment call; biases true values up, i.e. censored ligands look slightly more active than they are). Evaluation convention: PRIMARY metrics use UNCENSORED held-out cells only; SECONDARY metrics use all cells with censored truth set to 5.0 (floor). Model integrins: avb3, avb5, avb6, avb8, a5b1. aIIbb3 is in matrix.csv but is excluded from models (28/34 of its cells are censored; it is only informative for 3 platelet ligands + cilengitide; this is a judgment call, reported).

Tasks.
* (a) LOLO. Hold out a whole ligand (all integrin cells). Predict its pIC50 on each of the 5 integrins. Metrics (on uncensored held-out cells): RMSE, Spearman rho and Pearson r of predicted vs observed, pooled and PER INTEGRIN.
* (a2) Cell-masking completion (adds the "promiscuity" and SVD nulls that are meaningless when a whole ligand is hidden). Hold out one (ligand, integrin) cell; the ligand's other integrins are visible. Same metrics.
* (b) LOIO. Hold out one whole integrin column; predict every ligand's pIC50 on it from the other 4 integrins' data (+ integrin descriptors). Metrics per held-out integrin: Spearman rho across ligands (primary, because the column mean is unknowable), and RMSE (secondary).
* (c) Selectivity. S_j = log10(IC50_j / IC50_avb6) for j in {avb3, avb5, avb8, a5b1}, defined only where both cells are uncensored (primary). LOLO prediction of S_j (= pred pIC50_avb6 - pred pIC50_j). Metrics: RMSE, Spearman, and sign accuracy (is avb6 preferred over j?).
* (d) Pairwise-order concordance with noise floor. d1: for each integrin, all ligand pairs whose observed pIC50 differ by >= 0.3 log units (uncensored-vs-uncensored, or uncensored at pIC50 >= 5.3 vs censored); concordance = fraction of pairs ordered correctly by LOLO predictions (tied predictions count 0.5). d2: within a ligand, pairs of integrins differing by >= 0.3 (selectivity direction), LOLO predictions.

Nulls (must be beaten; computed with the identical protocol):
* N1 per-integrin mean of training ligands (also the "structure-blind" baseline; LOLO a, c, d).
* N2 per-integrin median of training ligands.
* N3 promiscuity: ligand mean pIC50 over the OTHER integrins (a2, b). (Not applicable to LOLO: nothing of the held-out ligand is visible.)
* N4 rank-1 SVD matrix completion (a2): iterative rank-1 imputation on the 34x5 matrix with per-column centring, held-out cell treated as missing.
* N5 for LOIO: grand mean of the other columns (constant -> rho undefined; reported as 0 by convention) and N3.
* Chance for (d) = 0.5.

Uncertainty: percentile bootstrap, 2000 resamples over LIGANDS (predictions fixed, metrics recomputed; differences vs null are paired on the same resample). A task is called POSITIVE only if the 95% CI of (model minus best null) excludes 0 in the favourable direction; NEGATIVE if the CI excludes 0 unfavourably; otherwise NULL (inconclusive). n is tiny; "NULL" almost always means "underpowered", not "no effect".

Models (all hyper-parameters fixed here, a priori, NOT tuned on any fold):
* M1 (LOLO, structure): RDKit Morgan count fingerprint (radius 2, 2048 bits, log1p), ridge (alpha=1.0) fitted per integrin on centred pIC50 (equivalent to fingerprint x integrin one-hot ridge). Restricted to ligands with a structure (ligands.csv, tiers A/B). Compared to nulls on that same subset.
* M2 (LOLO, structure): Tanimoto-kernel GP / kernel ridge (lambda=0.1) on the same subset, per integrin, centred.
* M3 (LOLO, low-rank with side information): reduced-rank ridge regression (fingerprint -> 5 integrin outputs, ridge alpha=1.0, rank r=1 truncation via SVD of the fitted values).
* M4 (a2): M3-style plus the ligand's visible cells is NOT built (too few structures); a2 uses N3/N4 vs. a rank-1 model only (N4 is the model).
* M5 (LOIO): integrin kernel regression. K_int(j,k) = sequence-identity-derived kernel between heterodimers (global-alignment identity of beta-subunit N-terminal 450 aa and alpha-subunit N-terminal 600 aa, from UniProt FASTA; mean of the two identities; NOTE: these are crude windows, not domain annotations). Prediction for held-out j: sum_k softmax(K_int(j,k)/T, T=0.05) * (ligand's pIC50 on k  - mean_k) + mean over other columns. M5b: product kernel Tanimoto x K_int GP (lambda=0.1) on structure-bearing ligands, using other-integrin cells of all those ligands.
Per-integrin results are reported for everything; pooled numbers are secondary.

Honesty rules: whole ligand is the held-out unit for LOLO; nothing is tuned on test folds; ligands without an unambiguous structure are excluded from structure models but kept in the matrix statistics and structure-blind nulls/models.

## 2. Deviations from the pre-registration (all found after the first run; stated, not hidden)

1. LEAVE-ONE-OUT MEAN ARTIFACT. The first run gave the per-integrin-mean null (N1) a Spearman of exactly -1.0 and a pairwise concordance of 0.0: a leave-one-out mean is a perfectly anti-monotone function of the held-out value. That is a statistical artifact, not a meaningful null. I therefore (i) kept N1's RMSE as the null for all RMSE comparisons (unaffected in spirit), (ii) judged rank metrics (rho, d1 concordance) against CHANCE (0 and 0.5) instead of against N1, and (iii) for the selectivity task (c) compared rho against N1 directly (non-constant there, driven by integrin offsets). This changed which comparisons look "positive" in the first run (the first run's rho "POSITIVE" was entirely this artifact and was discarded). The decision was made on statistical grounds before looking at whether it helped any model; verdicts below use the corrected rules.
2. d2 (within-ligand integrin order) is compared to N1 (integrin-mean order, legitimate), not to chance.
3. M4 was dropped as a separate model; (a2) just compares the rank-1 SVD (N4) with N1 and N3.
4. POST-HOC diagnostic added (posthoc_cluster_out.py, NOT pre-registered): leave-chemotype-out for the structure models, because the first results looked like within-cluster interpolation.

## 3. Results (results.json has everything; CI = 95% percentile bootstrap over ligands, 2000 resamples)

Matrix: Kapp 2017 = 34 ligands x 6 integrins = 204/204 cells filled (29 ligands Table 1 + 5 Table 2). 89 of 204 cells are right-censored ("> 10000"); aIIbb3 is 28/34 censored. Restricted to the 5 modelled integrins: 170 cells, 60 censored; uncensored per integrin avb3 25, avb5 23, avb6 23, avb8 10, a5b1 29. Extra series (separate source, not mixed in models): Quigley 4 ligands x 4 integrins = 16 cells (0 censored); Tomassi 6 ligands (+ cilengitide, RTDLDSLRT rows) = 20 cells (3 censored). Total matrix.csv = 240 cells. Structures: 16 of 34 Kapp ligands have a SMILES (7 tier A PubChem-retrieved with CID, 9 tier B built by me from sequence/name convention); 18 have none.

### (a) LOLO (whole ligand held out)
Structure-blind, all 34 ligands: N1 RMSE 1.178 [0.937, 1.396]; N2 (median) 1.215 [0.921, 1.465]. There is no structure-free model that can do better than N1 by construction; this is the floor.
Structure subset (16 ligands, same fold structure for model and nulls; best null = N1 trained on all other 33 ligands, RMSE 0.743 [0.492, 0.956]):

| model | pooled RMSE (uncensored) | diff vs best null | mean per-integrin rho |
|---|---|---|---|
| M1 ridge Morgan | 0.558 [0.275, 0.797] | -0.186 [-0.315, -0.093] | 0.33 [-0.10, 0.62] |
| M2 Tanimoto GP | 0.574 [0.295, 0.813] | -0.170 [-0.291, -0.083] | 0.26 [-0.18, 0.61] |
| M3 reduced-rank-1 | 0.597 [0.394, 0.764] | -0.146 [-0.247, -0.031] | 0.28 [-0.07, 0.53] |

Per integrin (M1 vs N1-all34 RMSE; rho): avb3 0.367 vs 1.021 (rho 0.88); avb5 0.577 vs 0.627 (rho -0.01); avb6 0.671 vs 0.715 (rho 0.57); avb8 0.421 vs 0.236 (worse; n<=2-3 cells); a5b1 0.624 vs 0.591 (worse; rho 0.21). The pooled RMSE gain is carried almost entirely by avb3. Sensitivity (tier A only, n=7): M1 RMSE 1.087 [0.275, 1.779] vs N1 1.606 [1.342, 1.881]; CIs overlap heavily, no claim.
POST-HOC leave-chemotype-out (hold out ALL linear RGD peptides / ALL cyclic RGD pentapeptides): structure models are WORSE than the plain mean. Linear peptides held out: N1 0.60 vs M1 1.29, M2 0.87. Cyclic pentapeptides held out: N1 1.43 vs M1 2.31, M2 1.93. ("other" cluster has only 2 uncensored cells: uninformative.) So the apparent LOLO gain is within-chemotype interpolation (a held-out linear peptide has 7 near-identical linear siblings in training), not generalisation to a new scaffold.

### (a2) Cell masking (one cell hidden, ligand's other 4 integrins visible), all 34 ligands
N1 RMSE 1.178 [0.938, 1.399]; N3 promiscuity 1.379 [1.234, 1.523] (worse than N1 by 0.20 [-0.03, 0.41], NULL); N4 rank-1 SVD 1.211 [0.858, 1.538] (vs N1 +0.03 [-0.17, 0.20] NULL; vs N3 -0.17 [-0.53, 0.18] NULL). Mean per-integrin rho: N3 0.09 [-0.19, 0.40], N4 -0.01 [-0.35, 0.31]: indistinguishable from 0. The matrix does NOT show a low-rank "promiscuity" structure that predicts a hidden cell better than the integrin mean.

### (b) LOIO (whole integrin held out)
Primary metric = mean over the 5 held-out integrins of Spearman across ligands (uncensored).
All 34 ligands: N3 promiscuity 0.09 [-0.20, 0.38]; M5 sequence-kernel 0.14 [-0.12, 0.42]; M5 - N3 = +0.05 [-0.13, 0.20] -> NULL. Secondary (censored set to 5.0, ties): N3 0.17, M5 0.36 [0.14, 0.56], M5 - N3 = +0.19 [0.08, 0.31] (nominally POSITIVE, but secondary, one of two LOIO metrics, and it reflects only that M5 weights avb3/avb5 neighbours more heavily). Per held-out integrin (M5 rho): avb3 0.66, avb5 0.36, avb6 -0.08, avb8 0.01, a5b1 -0.26. Held-out avb6 and a5b1 are NOT predictable from the other integrins (a5b1 shares no alpha subunit and its beta is distant; avb6 is the target of interest). The integrin kernel (sequence-window identity; avb3-avb5 0.79, avb6-avb8 0.71, a5b1-avX 0.47-0.50) has only 5 points: any integrin-descriptor claim is not statistically supportable.
Structure subset (16): N3 0.48 [0.23, 0.69], M5 0.50 [0.33, 0.72], M5b product-GP 0.51 [0.33, 0.74]; differences vs N3 +0.03 [-0.05, 0.20] / +0.04 [-0.05, 0.20] -> NULL.

### (c) Selectivity log10(IC50_j / IC50_avb6), LOLO
Only 63 uncensored pairs across 34 ligands (avb3 17, avb5 15, avb8 10, a5b1 21); only 24 pairs among the 16 structure ligands (avb8: 2). N1 (all 34): RMSE 1.43 [0.96, 1.83], sign accuracy 0.67 [0.60, 0.73]. Structure models vs best null (N1, S-only train): M1 RMSE +0.05 [-0.60, 0.47], sign acc +0.08 [-0.20, 0.38], rho +0.13 [-0.15, 0.34]; M2 similar; M3 no better -> NULL (underpowered).

### (d) Pairwise concordance (|dpIC50| >= 0.3)
d1 (ligand pairs within an integrin; 2037 pairs all-34, 365 on the 16-subset). Structure subset: M1 0.715 [0.546, 0.884] (vs chance 0.5: +0.22 [0.05, 0.38], POSITIVE); M2 0.682 [0.527, 0.855] (+0.18 [0.03, 0.36], POSITIVE); M3 0.674 [0.470, 0.862] (NULL). Same caveat as (a): dominated by within-chemotype pairs; the pair counts are not independent (ligands are reused).
d2 (integrin order within a ligand; 117 pairs on the subset): M1 0.940 [0.866, 1.0] vs N1-all34 0.880 [0.856, 0.894]: +0.06 [0.00, 0.11] -> NULL. Integrin identity alone (N1) already orders the integrins 0.77 (all 34, [0.70, 0.84]) to 0.88 of the time.

### X. Cross-lab / assay noise floor (descriptive)
8 same-compound cells measured by Kapp vs another lab (Quigley FF assumed = Kapp c(FRGDLAFp(NMe)K) - same scaffold, not verified in text; Tomassi cilengitide, RTDLDSLRT): mean |delta log10(IC50)| = 0.29, max 0.49 (a5b1 for FF: 73 vs 226 nM; avb3 for FF: 1200 vs 424 nM, opposite direction). The 0.3 log-unit pair floor is therefore about the typical inter-lab disagreement, not a conservative margin. This is why the extra series were never mixed into the model fits.
Descriptive selectivity of the extra series (avb6 vs others) is in results.json (X_extra_series_selectivity); n=4 and n=6, no modelling claim.

## 4. VERDICT (blunt)

| task | verdict | evidence |
|---|---|---|
| (a) LOLO, pooled RMSE on 16 structure ligands | POSITIVE but NOT a generalisation claim | RMSE 0.56 vs 0.74 (diff -0.19 [-0.32, -0.09]); gain is mostly avb3 and disappears (turns negative) in post-hoc leave-chemotype-out |
| (a) LOLO, per-integrin rank (rho) | NULL | mean rho 0.33 [-0.10, 0.62]; only avb3 (0.88) is convincing |
| (a2) cell completion, rank-1 SVD / promiscuity vs integrin mean | NULL (neither beats N1) | RMSE 1.21 / 1.38 vs 1.18 |
| (b) LOIO, primary (uncensored Spearman) | NULL | M5 0.14 vs promiscuity 0.09, diff +0.05 [-0.13, 0.20]; avb6 and a5b1 held out are not predictable (rho -0.08, -0.26) |
| (b) LOIO, secondary (floor-imputed) | nominally POSITIVE, weak | +0.19 [0.08, 0.31]; not primary |
| (c) selectivity avb6 vs others | NULL (underpowered) | 24-63 usable pairs; no structure model beats mean |
| (d1) pairwise order, within integrin | POSITIVE vs chance, with the (a) caveat | 0.72 [0.55, 0.88] |
| (d2) integrin order within ligand | NULL | +0.06 [0.00, 0.11] over integrin means |

Overall: the large same-assay matrix does NOT rescue a general avb6 selectivity model. What is real: (i) a chemotype-level signal (linear vs cyclic vs non-peptide RGD mimetics have very different avb3/a5b1 potencies) that fingerprints capture when sibling chemotypes are in training, and (ii) integrin means already give most of the within-ligand ordering. What is not shown: prediction for a new scaffold, avb6/avb8 specific SAR, selectivity prediction, or cross-integrin transfer to avb6. n is too small (34 ligands, 16 with structures, 10 uncensored avb8 cells) for any claim about avb6 selectivity SAR.

## 5. What would be needed for a stronger claim
1. A structure for every ligand (the 18 without SMILES include all the avb6/avb8-selective leads: A20FMDV2, RTDLDSLRT, Mol11, c(FRGDLAFp(NMe)K), JSM6427, c(phgisoDGRk), 44b, sn243, NC100717). Fetching them from the primary papers' SI would triple the structure-bearing avb6 data.
2. Many more congeneric avb6-selective series with the same assay (hundreds of compounds, not 34): the Notni/Kessler/Tomassi/Quigley series measured on one platform, with raw IC50 (not just ranges) and the censoring flagged.
3. Treat censoring properly (Tobit/survival likelihood) instead of floor imputation once a larger set exists.
4. Scaffold-split evaluation as the PRIMARY protocol (leave-chemotype-out), not LOLO within clusters.
5. Structure-based integrin descriptors (binding-site residue environment from cryo-EM/crystal structures, e.g. beta6/beta8 specificity-determining loop) instead of whole-sequence-window identity, plus >5 integrins (add avb1, a8b1, a4b1... only if same-assay data exist).
6. Independent verification of the Kapp transcription (the tables are images; OCR/second human pass) and of Table 2 vs the SI.

## 6. Parsing doubts / judgment calls
* Kapp Tables 1-2 are images: manual transcription; two read passes, a spot test file asserts counts (29+5 ligands x 6) and censoring (89 cells), but values are only as good as my reading. SDs are printed '±' (SD of replicate measurements as printed) and are not used.
* '>10000' vs '> 10000' (sn243, c(FRGDLAFp(NMe)K)) both parsed as censored at 10000.
* Tomassi '>5000' means censored at 5000 (pIC50 bound 5.30); in the Kapp-only models these never enter.
* Ligand identity across papers (Kapp c(FRGDLAFp(NMe)K) vs Quigley FF) is an assumption; they are separate rows.
* The Kapp footnote about Mol11 "(S)-enantiomer" is kept in the name only as 'Mol11'.
* Structures: tier B SMILES are my construction (free termini, L-amino acids; cyclic c(RGDfV) derived from PubChem c(RGDfK)); the paper may use capped termini. Linear-peptide SMILES errors would affect the within-cluster conclusions only mildly (they are near-identical to each other either way).
* Tomassi and Quigley PMIDs/PMCIDs given in the brief are correct for the quoted tables, although the paper titles are about HSV-1 dual avb6/avb8 ligands and RGD trimers respectively.
* LOLO N1 is evaluated with a leave-one-out mean, which is slightly pessimistic for RMSE (the true-mean RMSE would be a little lower); the same holds for the structure models' intercept.

## 7. Files
`matrix.csv` (240 long-format cells, verbatim string in column `verbatim`), `ligands.csv` (46 ligand ids; SMILES provenance), `build_matrix.py`, `build_ligands.py`, `integrin_seq.py`, `analysis.py` (all tasks; ~3 min), `posthoc_cluster_out.py`, `tests/test_parser.py` (`python3 -m pytest -q tests`), `results.json`, `posthoc_cluster_out.json`, `data/` (Kapp transcriptions, PubChem responses), `src_raw/` (Europe PMC XML, the two table images (CC BY, Kapp 2017), UniProt FASTA).
