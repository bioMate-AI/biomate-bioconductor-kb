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

## 4. Clarifications made after the protocol was frozen (disclosed, none touched test-fold fitting)
- The t-interval over domains is the decisive CI in the verdict rule (the bootstrap over n<=7 domains is anti-conservative; both are in results.json).
- First run of S1/S2 accidentally omitted the PWM null from "best null"; fixed to include null (c) before interpreting; numbers below are from the final run.
- A bug (`Series.max` method shadowing the `max` column) in wild-type reconstruction was fixed before the final run; it did not change the motif backbones.
- The percent-identity measure (matches / shorter length over a gapped BLOSUM62 global alignment) is inflated for unrelated domains (0.23-0.39 for all pairs, see `identity` in results.json), so the 30 % rule drops the pairs 152/246/299 SH3 only; S2 (leave-class-out) is the stricter and more meaningful test.
- Exploratory extra (not in the pre-registered best-null rule): (e) promiscuity + PWM linear stack.

## 5. Results (all numbers from `results.json`, `postprocess.json`; Spearman rho, mean over held-out domains, [t 95% CI over domains])

### 5.1 Data actually available
| | domains | (domain,peptide) pairs | notes |
|---|---|---|---|
| PCA2 in-cell PPI (MTX) | **3** (PDZ 363 TJP1-PDZ3, 366 TIAM1-PDZ1, 385 PDLIM4-PDZ1) | 4,932 (1,654 / 1,653 / 1,625) | 1,656 unique peptides; 1,625 measured in all 3 domains; 3 families x ~550 variants (1-2 substitutions of a 10-mer motif) per domain |
| PCA1 in-cell PPI | 7 (4 SH3: 152 SHO1, 246 ARHGAP26, 250 EPS8L1, 299 SNX9; 3 PDZ: same as above) | 2,748 (380-400 per domain, cognate family only) | |
| Union | **7** | | PCA2 adds no new domains; it adds the non-cognate 3 x 3 pairing and an independent re-measurement |
Noise: median replicate SE 0.04 on a score of SD 0.30; reliability 0.91-0.98 (noise ceiling r ~0.96-0.99), so noise is not the limiting factor. PCA1 vs PCA2 re-measurement of the same (PDZ, cognate peptide) pairs: Spearman 0.83 / 0.89 / 0.61 (363 / 366 / 385, n ~ 400), i.e. batch/experiment differences, not replicate noise, bound reproducibility.
Correction to the earlier session: the 7 PCA1 domains are 4 SH3 + 3 PDZ, not 7 SH3.

### 5.2 Analysis A: PCA2, 3 PDZ, LODO (UNDERPOWERED, n=3 domains, train k = 2)
All peptides of the held-out domain: PWM (in vitro) 0.76 [0.31, 1.22]; promiscuity -0.26; additive position -0.29; physchem -0.43; models (i) -0.28, (ii) -0.15, (iii) -0.51.
The negative values are not noise: pooled over the 3 families, the held-out domain's own cognate family is high while that family is low in the other (train) domains, so any model that transfers the other domains' preferences is anti-correlated at the family level. Cross-domain transfer therefore fails exactly on the domain-specific part of the signal; only the domain's own in-vitro PWM captures it (domain-specific residual: PWM 0.81, models 0.19 / 0.37 / -0.26).
Cognate family only: PWM 0.42, models 0.26 / 0.21 / 0.12, promiscuity 0.18, additive 0.24. Non-cognate families: all ~0.4 (promiscuity 0.39, additive 0.42, model (ii) 0.57), i.e. peptide-intrinsic ranking is transferable but is just promiscuity.
Learning curve A (k = 1, 2 of 2 possible): everything falls from k=1 to k=2 except model (ii) (-0.19 -> -0.15); uninformative.
Shuffled test labels: mean rho between -0.007 and +0.005 for every predictor (30 permutations x 3 domains).

### 5.3 Analysis B: 7-domain LODO, PCA1 cognate test set (k = 6 train domains)
| predictor | mean rho [t CI over 7 domains] |
|---|---|
| (c) PWM in vitro (best null) | 0.241 [0.026, 0.456] |
| (b) additive position | 0.119 [-0.030, 0.267] |
| (d) physchem | -0.018 [-0.148, 0.112] |
| (i) additive + offsets | 0.199 [0.124, 0.274] |
| (ii) low-rank + BLOSUM-kernel domain side info | 0.252 [0.097, 0.407] |
| (iii) gradient boosting | 0.205 [0.075, 0.335] |
Model minus best null: (i) -0.042 [-0.206, 0.122]; (ii) +0.011 [-0.198, 0.220]; (iii) -0.036 [-0.216, 0.144]. No model beats the in-vitro PWM.
Adding the PCA2 rows to the training set (B2): (i) 0.274, (ii) 0.275, (iii) 0.272; minus PWM: +0.033 [-0.168, 0.235], +0.034 [-0.161, 0.228], +0.031 [-0.178, 0.240]. The gain is concentrated in the PDZ test domains (e.g. 363: 0.22 -> 0.42), where the PCA2 training rows contain the same peptide variants measured in sister PDZ domains (peptide promiscuity), not new-domain generalisation.
Strict variants: S1 (drop train domains > 30 % identity): (ii) 0.266, minus PWM +0.025 [-0.134, 0.185]. S2 (train on the other class only): (i) 0.123, (ii) 0.135, (iii) 0.073 vs PWM 0.241; (ii) minus PWM -0.106 [-0.204, -0.008] (significantly worse). Cross-fold transfer (SH3 <-> PDZ) is essentially absent.
B3 (PCA2 cognate rows of the 3 PDZ as test, PCA1 train): models -0.14 to 0.02 vs PWM 0.42 (n=3).

### 5.4 Learning curve (B1; mean over 7 held-out domains, up to 20 random train subsets per k)
| k | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| (i) additive + offsets | 0.149 | 0.185 | 0.203 | 0.206 | 0.203 | 0.199 |
| (ii) low-rank | 0.149 | 0.214 | 0.240 | 0.242 | 0.249 | 0.252 |
| (iii) GBM | 0.098 | 0.115 | 0.146 | 0.171 | 0.191 | 0.205 |
| (b) additive position | 0.104 | 0.107 | 0.111 | 0.115 | 0.117 | 0.119 |
| (d) physchem | 0.129 | 0.106 | 0.054 | -0.004 | -0.020 | -0.018 |
| PWM reference (no training) | 0.241 | | | | | |
Gains k = 3 -> 6: (i) -0.003, (ii) +0.012 [-0.009, 0.033], (iii) +0.059 [-0.029, 0.148]. Models (i) and (ii) plateau at ~0.20 / ~0.25 from k = 3 (the extra domains add ~0 per domain); only the GBM is still rising at k = 6 but its gain CI includes 0 and it remains below the PWM. Figure: `learning_curve.png`.

### 5.5 Did the earlier 7-domain conclusion (0.265 -> 0.319) change?
Re-computed on the same PCA1 7 domains: PWM 0.241 [0.026, 0.456]; PWM + measured availability 0.327 [0.140, 0.513]; PWM + predicted availability (deployable) 0.311 [0.118, 0.505]; availability alone 0.160. This reproduces the earlier numbers within ~0.03 (0.265 / 0.319 / 0.286): marginal gain from availability (+0.07-0.09, CI over 7 domains includes the effect). **PCA2 contains no additional domains, so the conclusion does not change.** On the 3 PDZ of PCA2 (cognate rows, n=3): PWM 0.415, PWM + measured availability 0.457 (CIs span 0). In-cell-trained cross-domain models (0.25-0.27 at k=6) are still below PWM + availability (0.31-0.33).

## 6. Verdict
**NULL for cross-domain in-cell binding prediction** (with a NEGATIVE result for the domain-specific component).
- Models trained on other domains' in-cell data reach rho ~0.20-0.27 on a held-out domain's own variants. That equals, but never significantly exceeds, the in-vitro PWM (0.24); difference CIs over domains straddle zero in every configuration (B1, B2, S1) and are significantly negative for leave-class-out (S2) and, with the caveat n=3, for the pooled-family PCA2 analysis (A), where only the held-out domain's own PWM carries the family-level specificity.
- What does transfer is peptide-intrinsic / within-motif variant effects (promiscuity-like, availability-like). What does not transfer is domain-specific specificity, which is the part a cross-domain predictor must supply.
- The pre-registered rule for POSITIVE (beat best null with CI over domains excluding 0) is not met anywhere.

**How many domains would be needed.** The curve is already flat at k = 3-6 for the additive/low-rank models, so more domains of the same kind do not obviously help; the limit is the unlearnable domain-specific component, not the training-set size. If a true improvement over the PWM existed, the CI over domains could exclude zero only with enough held-out domains: from the observed SD of the per-domain model - PWM difference (0.18-0.23), about **~15-23 domains for a true gain of 0.10, ~50-80 for 0.05, and ~140-220 for 0.03** (50 % power approximation; `postprocess.json`). A realistic minimum for a decisive test is therefore **>= 20-25 domains** (and a domain-side model that can actually learn pocket features, which needs many more than 7 training domains), versus 7 available (3 for PCA2).

## 7. Caveats
Test sets are within-motif variants (1-2 substitutions of one motif per domain), so rho measures variant ranking inside a family, not discovery of new binders. Domain side information (BLOSUM kernel, composition descriptors) cannot be learned from <= 6 domains by construction. Fixed hyper-parameters, no tuning. Data (CC BY-NC-ND) is not redistributed; derived per-peptide tables stay in the scratchpad.
