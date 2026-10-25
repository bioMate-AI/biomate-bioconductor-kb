# Cross-domain in-cell peptide-binding prediction: PCA2 and PCA1 of Lemieux et al. 2026

Status: PROTOCOL PRE-WRITTEN BEFORE ANY MODEL WAS FIT (section 2). Results are appended in section 5 after the run.
Data: Landry lab, doi 10.64898/2026.09.21.752983, repo github.com/Landrylab/Lemieux_et_al2026 (CC BY-NC-ND).
Raw files are kept outside the repo (scratchpad); this directory holds only code, tests and derived summary numbers.

## 1. What PCA2 actually contains (inspected before the protocol)

- PCA2 does NOT contain many domains. In-cell PPI selection data (MTX condition) exist for exactly **3 binding domains**
  (PBD 363 = TJP1 PDZ3, Q07157; PBD 366 = TIAM1 PDZ1, Q13009; PBD 385 = PDLIM4 PDZ1, P50479; pools P4/P5/P6).
  Authors state the DMSO condition carries no PPI signal (3_filter_replicate.R), and pool P3 is DMSO-only, so it is not used.
- Each of the 3 domains is screened against all 3 peptide families (motifs PRM_0363/0366/0385, each a 10-mer),
  as single and double mutational variants of the motif ("full 3 x 3 domain x family matrix"). 1,625 peptides are measured in all three domains.
- The 7 domains of PCA1 are 4 SH3 (152 SHO1, 246 ARHGAP26, 250 EPS8L1, 299 SNX9) + 3 PDZ (363, 366, 385), i.e. NOT "7 SH3" as the earlier session
  wrote. PCA2 re-measures the 3 PDZ of PCA1, so the union of all in-cell data in the repo is still **7 distinct domains**.
- Reference/control peptides (family "reference"), stop-codon variants, and 3 stray family-246 rows in pool P5 are dropped.
- Exact table counts: see `table_summary.json` and section 5.
- **Consequence stated up front: with 3 (PCA2) or 7 (union) domains the cross-domain question remains underpowered.**
  A CI over domains with n=3 is nearly uninformative (t df=2); with n=7 it is weak. Everything below is the best valid analysis under that limit.

## 2. Pre-registered protocol

**Score.** `med_norm` = median over outlier-filtered replicates (>=2 of 3) of the normalised T2 selection coefficient in MTX
(0 = negative-reference level, 1 = positive-reference level), identical to the authors' `med_score_filtered.csv`.
Noise estimate = SD/sqrt(n) across replicates of the per-replicate (codon-averaged) normalised coefficient. PCA1 score = `med_norm` of `med_ppi_score.csv` (no replicate noise computed).
Peptides = mutational variants (1-2 substitutions) of the family motif; the wild-type motif is reconstructed from the (pos, max) annotations.

**Held-out unit = a whole domain** (leave-one-domain-out, LODO). No row of the test domain (any family, any experiment) is used in training.
Stricter variants (both fixed now): (S1) additionally drop every training domain with > **30 %** global-alignment identity (BLOSUM62, Biopython PairwiseAligner,
identity = matches / length of shorter sequence) to the test domain; (S2) leave-class-out: train only on the other domain class (SH3 -> test PDZ; PDZ -> test SH3).

**Analyses.**
- A: PCA2 only, 3 PDZ, LODO, test set = all peptides of the held-out domain (3 families, ~1,650 peptides); also cognate-family subset and a
  "domain-specific residual" (score minus mean over train domains of the same peptide). Learning curve k = 1, 2 train domains.
- B: 7-domain LODO on PCA1 cognate variants as test set (same test set as the earlier 0.265 -> 0.319 benchmark); training = other domains' PCA1 rows
  (B1, comparable with the earlier result) or PCA1 + PCA2 rows (B2). Learning curve: for each held-out domain, k = 1..6 train domains, all subsets if <= 30 else 30 random subsets (seed fixed).
  For 363/366/385 the PCA2 cognate rows are also scored as an independent re-measurement (B3).
- C: earlier benchmark re-computed: PWM alone, PWM + measured availability, PWM + predicted availability (availability model fit on train-domain peptides only), on 7 domains.

**Metrics.** Per held-out domain Spearman, 95% bootstrap CI over peptides (500 resamples); mean over domains with (i) t-interval and (ii) bootstrap CI over domains.
Differences model - best null are computed per domain, and the same CIs over domains are applied to the difference.

**Nulls to beat** (all fit/computed without any test-domain score):
(a) promiscuity = mean score of the same peptide across train domains (defined only where peptides are shared: analysis A);
(b) additive position-specific model: mean over train domains of per-domain ridge fits on C-terminus-aligned one-hot residues;
(c) in-vitro PWM score of the test domain (phage-display PWM supplied in the repo) where available;
(d) hydrophobicity/charge availability-style model: ridge on peptide hydropathy, net charge, aromatic count, number of substitutions and substituted-residue delta hydropathy/volume/charge, fit pooled on train domains.
"Best null" = null with the highest mean rho over test domains in that analysis (chosen on test results, which favours the null, so the criterion is conservative).

**Models** (each fit on train domains only; hyper-parameters fixed now, never tuned on test): ridge alpha = 10 on standardised features throughout.
(i) additive position-specific ridge, pooled, with domain and family offsets (offsets dropped for an unseen domain; family offset = train-domain mean when the family is seen);
(ii) low-rank domain x (position,aa) factorisation: per-train-domain ridge weight matrix W (D x F) = mean + rank r = min(2, D-1) SVD reconstruction; test-domain weights =
softmax(sim/tau)-weighted average of train-domain reconstructions, tau = 0.1, sim = BLOSUM62 alignment score normalised by sqrt(self-scores) between domain sequences (the domain side-information);
(iii) HistGradientBoosting (depth 3, 200 iterations, lr 0.05, seed 0) on [peptide features ++ domain features: mean hydropathy, net charge, length, aromatic fraction, G+P fraction, SH3/PDZ indicator].
No protein language model is run (not needed; no GPU, and with <= 7 domains domain embeddings cannot be learned anyway).

**Verdict rule.** POSITIVE: best model beats best null with the CI of the per-domain difference over domains excluding 0 (and bootstrap-over-peptides CI of its rho excluding 0).
NEGATIVE: best model's mean rho <= 0, or it is below the best null with CI excluding 0. NULL otherwise. If n_domains <= 3 the CI is flagged UNDERPOWERED and no POSITIVE is claimed from it.
Minimum domains needed: read from the learning curve (does mean rho keep rising with k, and is the rise distinguishable from a plateau?).

## 3. Files
`common.py` (scales, domain table with UniProt accessions, stats), `build_table.py` (clean table + summary), `models.py` (features, nulls, models, splitter),
`run_analysis.py` (all analyses, writes `results.json`, `learning_curve.png`), `tests/` (table builder, splitter, permutation sanity).
Run: `PCA_RAW=<dir with PCA1/, PCA2/ downloads> PYTHONPATH=<biopython> python3 run_analysis.py`.

## 4. (reserved)

## 5. Results
(appended after the run)
