# Integrin subtype selectivity of RGD-type ligands: a multi-target, same-assay benchmark

STATUS: PRE-REGISTRATION SECTION (tasks, nulls, hyper-parameters) written BEFORE any model was fitted.
Results and the verdict are appended below the line "RESULTS" after the fits (see end of file).

## 0. Data sources (all values verbatim, IC50 in nM)

| key | paper | access | how extracted |
|---|---|---|---|
| kapp2017 | Kapp TG et al., Sci Rep 2017;7:39805, PMID 28074920, PMC5225454 (CC BY) | Europe PMC fullTextXML | Tables 1 and 2 are JPEG images in the XML (`<graphic>` only, no `<tr>` cells). Images downloaded from the PMC CDN (kept in `src_raw/`), values transcribed BY HAND (visual read, two passes at 1.3x zoom) into `data/kapp2017_table{1,2}_transcribed.tsv`. This is the single largest parsing risk; there is no OCR cross-check (tesseract is not installed). |
| quigley2023 | Quigley NG et al., RSC Med Chem 2023, PMID 38099056, PMC10718521, Table 1 (text table in XML) | Europe PMC XML | parsed from XML `<tr>` cells (`data/quigley2023_table1.tsv`) |
| tomassi2021 | Tomassi S et al., J Med Chem 2021, PMID 33961417, PMC8279406, Table 1 (text table in XML) | Europe PMC XML | parsed from XML (`data/tomassi2021_table1.tsv`) |

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
