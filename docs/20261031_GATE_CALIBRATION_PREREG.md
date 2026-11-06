# Calibrated validity gate: pre-registration (committed before any calibration fit or validation run)

Scope: a method step for paper 1. The registered gate (A11: equivalence within +-0.05 at 90 %, bias flag at the 98.3 % family-cluster percentile interval, ~24 controls) was measured by the positive control (`20261031_GATE_POSITIVE_CONTROL_PREREG.md`, results section; `gate_positive_control/results/gpc_summary.json`) to flag 24.5 % (V-I, 26 families) and 32.5 % (V-M2, 14 families) of planted-valid benchmarks as biased, while detecting planted shortcuts at AUROC 0.60-0.65 with probability about 1.00. The audit (`committee_raw/20261030c/audit_gates_data_criteria.md`, A1 and rules 5-6) recommended null-calibrated critical values or a family-cluster permutation test with a margin derived from decisions. This document fixes the calibrated procedure, the data split between calibration and validation, the margin derivation and the acceptance criteria. Nothing below was chosen after seeing a validation result. Compute: EC2 spot only.

## 1. Where the registered gate's false alarms come from (known before this document; from the positive-control results)
Per primary control the false-flag rate under a true AUROC of 0.5 is 0.00-0.15 against a nominal 0.017; the gate also evaluates 18-22 secondary controls whose flags accumulate. Two defects: (i) the family-cluster percentile bootstrap is anti-conservative at 14-26 clusters; (ii) multiplicity over ~24 controls. The calibrated gate corrects each one empirically.

## 2. Procedure (a): null-calibrated, max-statistic gate (PRIMARY; the one judged by the acceptance criteria)
Input: the compact gate record of a benchmark (per control: point estimate p_k, interval [lo_k, hi_k] at its registered level, number of families n_k), exactly as produced by `gpc_lib.run_A11_like` and `compact`.
1. Standardise each control: SE_k = (hi_k - lo_k) / (2 z_level_k), with z_level_k = Phi^-1(1 - (1 - level_k)/2) and level_k the level at which that control's stored interval was computed (primary: 1 - 0.05/3; the 18 standard secondary controls: 1 - 0.05/18; the four item-level controls C4_censored_label, C5_assay_IC50_only, C5_assay_has_Ki_or_Kd, C5_assay_has_EC50 on I-type sets: 1 - 0.05/22). z_k = (p_k - 0.5) / SE_k. Controls with hi = lo, a missing interval or n_k < 8 are not evaluable.
2. Dispersion calibration: kappa_k = sqrt(mean(z_k^2)) over the NULL calibration records of the same benchmark type (type I = items with item-level controls; type M = no item-level controls). RMS about zero (not SD) so that systematic centre offsets under the null (for example C3 0.009-0.013) are absorbed. A control with fewer than 30 null calibration observations is not tested (listed in the output).
3. Max statistic: T = max over testable controls of |z_k| / kappa_k. Critical value q (per type) = the 0.95 empirical quantile of T over the null calibration records of that type (family-wise error target 0.05).
4. BIASED if T > q. Per-control flags are reported as |z_k|/kappa_k > q (not used for the verdict beyond T).
5. Equivalence: with delta(F) = 0.5 x 2.8 x sigma_fam / sqrt(F), F = the smallest n_k among the three primary controls, sigma_fam = 0.2014, a primary control is equivalent if |p_k - 0.5| + 1.645 x kappa_k x SE_k <= delta(F).
6. Verdict precedence (unchanged from A11): BIASED, else UNVERIFIABLE (a primary control not evaluable), else NOT_EQUIVALENT (any primary control not equivalent), else VALID.
Margin derivation (sigma_fam, delta): the decision the gate protects is the zero-shot arm comparison. The pre-registered power analysis (`results/power.json`, analysis I, 26 families, five arm-minus-baseline contrasts) gives a median family-level SD of the paired difference of 0.2014 (range 0.1509-0.2488), i.e. MDE80 = 2.8 x 0.2014 / sqrt(F). A compound-only shortcut that by itself moves per-family AUROC by half of that MDE would explain a gain that the comparison could otherwise detect, so delta(F) = MDE80(F)/2: F = 14: 0.0754; 20: 0.0630; 26: 0.0553; 47: 0.0411; 85: 0.0306. (The registered 0.05 was chosen post hoc; this replaces it with a derivation from the design's own power. It is a pre-declared choice, not an optimum.)
Calibration data (null, existing, already seen by the positive-control fork): `gpc_results_run1.jsonl` (sha256 6011d9a1...) and `gpc_results_run2.jsonl` (sha256 6a5bba2e...), kinds VI (200 permutations of analysis I, 26 families; type I), VM2 (200 permutations of M2, 14 families; type M) and CURVE (synthetic-from-real, tpf = 2, clip = 600, F = 14, 20, 26, 47, 50, 85, 100, 150; type M). Seeds <= 17,040 and 900,001-900,030. Pooled over F within type (the standardisation is expected to remove most F dependence; the validation judges this).

## 3. Procedure (b): within-target permutation test (SECONDARY; cross-check, not judged by the criteria)
For a real benchmark, the permutation null is the distribution of the raw statistic T_raw = max_k |z_k| over fresh within-target label permutations of that same benchmark (the VI / VM2 construction). p = (1 + #{T_raw,null >= T_raw,obs}) / (1 + N). This is the exact-test counterpart of procedure (a) for the benchmark's own family structure; it is reported alongside (a) for analysis I and M2 using the FRESH null sets below (400 and 200 permutations). Label permutation within target preserves target size and class balance and therefore the family-cluster structure.

## 4. Validation data (fresh; seeds >= 2,000,000; never used for calibration; constructions differ from calibration)
| set | construction | n |
|---|---|---|
| V-I-fresh | within-target permutation of analysis I, 26 families | 400 |
| V-M2-fresh | within-target permutation of M2, 14 families (application only) | 200 |
| V3-F20 / V3-F26 / V3-F47 | synthetic-from-real with tpf = 3 targets per family and clip = 400 (calibration used tpf = 2, clip = 600), random labels | 400 each |
| S-real | planted shortcut on analysis I (26 families): S-tpsa, S-typ, S-diffuse at AUROC 0.65 and 0.70; S-cens at 0.65 (0.70 infeasible by earlier calibration), using the existing planted-signal calibration | 60 each |
| S-syn-F20 / S-syn-F47 | planted shortcut on synthetic tpf = 3 benchmarks: S-tpsa, S-typ, S-diffuse at 0.65 and 0.70 (planted-signal strength calibrated on a representative synthetic benchmark with separate seeds 2,900,001-2,900,030) | 60 each |
All sets are run through the registered gate code on EC2; the registered verdict and the calibrated verdict are computed from the same records, so both gates' operating characteristics are reported on identical data.

## 5. Acceptance criteria (fixed now)
- **PASS-A (false alarms), judged on V-I-fresh (F = 26), V3-F20, V3-F26, V3-F47:** P(BIASED | planted-valid) <= 0.10 as a point estimate AND the exact (Clopper-Pearson) 95 % upper bound <= 0.15, in every one of the four cells.
- **PASS-B (detection):** P(BIASED | shortcut) >= 0.80 at AUROC 0.65 and >= 0.90 at AUROC 0.70 (point estimates; exact lower 95 % bounds reported) for every feasible shortcut family in every shortcut cell (S-real at F = 26; S-syn at F = 20 and 47; S-cens only in S-real at 0.65).
- **PASS-C (safety):** P(VALID | shortcut at AUROC 0.65) <= 0.05 (point) in every shortcut cell.
- **Reported without a threshold:** P(VALID | planted-valid) with exact CIs per cell; delta(F); the registered gate's rates on the same records.
- **Outcome rule:** SUCCESS if PASS-A, PASS-B and PASS-C all hold in every cell; PARTIAL if PASS-A holds and PASS-B or PASS-C fails in some cells (list them); FAILURE if PASS-A fails in any cell. The constants (kappa_k, q) are frozen in a committed file before the validation jobs start; no refitting on validation data. A second calibration round would need a new amendment and a new fresh validation set with new seeds.
- A P(VALID | planted-valid) below 0.5 at a given F is stated as "the calibrated gate cannot certify at that F".

## 6. Application to real benchmarks (after the acceptance verdict)
Analysis I (26 families) and M2 (14 families): compact record from the registered code on EC2; calibrated verdict, T versus q, per-control standardised values, the permutation p-values of procedure (b), and which verdict changes relative to the registered gate. The censoring result (C4, inverted AUROC) is reported on its own from the stored interval and does not depend on calibration. The exact-potency benchmark of pilot 4 is a ranking task without decoy classes; the gate (AUC of control scores for positives vs decoys) is not applicable and is not run.

## 7. Limits stated in advance
Calibration nulls are label permutations of real benchmark structure; real benchmarks can be biased in ways no permutation reproduces. Planted shortcuts are single known properties (S-diffuse is a mixture). kappa_k and q are pooled over F within type; if the pooling fails at some F the criteria show it. Percentile-bootstrap SEs are approximated from stored interval widths. The synthetic constructions share the real compound pool.

## 8. Compute and cost
EC2 spot only (ecsInstanceRole, SG sg-0de9af2d4437a8c90, tags project=cyclic-selector, Name=gate-calib, terminate on shutdown, wall-clock cap, one writer per S3 prefix `s3://biomate-nextflow-work/cyclic_peptide/gate_calib/<run-id>/`, boot log to S3, resumable). About 2,940 gate runs of ~25 CPU-seconds each on one 36-vCPU instance (about 35 minutes); estimated cost under USD 1 (cap USD 2); cost reconstructed from instance ids and times.

## Results (2026-10-29; numbers from `gate_calibration/results/gcal_eval.json`, produced on EC2 by `gcal_eval.py` over `gcal_validation.jsonl` (2,940 fresh records, sha256 in the file), frozen constants `calibration_frozen.json` sha256 `7c218ddd06710fdeecba6d9ff9c15c4ea4595a8658db474a9e7758f42fd25c75`)
**Outcome under the pre-registered criteria: SUCCESS (PASS-A, PASS-B, PASS-C hold in every cell).** The first (as-run) evaluator printout read FAILURE; see deviation 1.

**Protocol record (all disclosed; none changes data, constants or thresholds).**
1. *Evaluator lookup defect (my error).* The as-run evaluator looked up the V-I-fresh cell under 26 families; the records carry 25 evaluable families (n_families of C1), so the cell was `None` and the roll-up read FAILURE (`gcal_eval_as_run.json` kept). The lookup was patched to find the V-I cell by kind and the evaluation recomputed from the same records and the same frozen constants.
2. *Ordering gap of about 23 s.* The validation instance was launched at about 12:28:40, the frozen constants were committed at 12:29:03 (`39ce9502b`; the first commit attempt failed on a gitignored log). The instance was installing packages and no validation record existed; the constants file was produced by stage 1 from the pre-existing null records only.
3. *Stage-1 test error (my error).* The first stage-1 run stopped on a wrong expected Clopper-Pearson bound in my own test (0.031 where scipy gives 0.0308); fixed before any fit.
4. *Cell label.* The pre-registered "V-I-fresh (F = 26)" is the analysis-I permutation set with 25 evaluable families; V3 cells are exactly 20, 26, 47.
5. Fit on null records only: 200 VI (type I), 580 VM2/CURVE (type M). Critical values q = 3.145 (type I) and 3.052 (type M); dispersion kappa 1.0-1.35 (C2/C3 on type M: 1.31/1.35).

**PASS-A (false alarms; calibrated gate, exact 95 % CI; registered gate on the same records in brackets).**
| cell | n | P(BIASED) | CI | P(VALID) | registered P(BIASED) | registered P(VALID) |
|---|---|---|---|---|---|---|
| V-I-fresh (25 families) | 400 | 0.033 | [0.017, 0.055] | 0.835 | 0.223 | 0.603 |
| V3, F = 20 | 400 | 0.083 | [0.057, 0.114] | 0.917 | 0.338 | 0.662 |
| V3, F = 26 | 400 | 0.043 | [0.025, 0.067] | 0.958 | 0.223 | 0.777 |
| V3, F = 47 | 400 | 0.030 | [0.016, 0.052] | 0.970 | 0.172 | 0.828 |
Criterion (point <= 0.10 and CI upper <= 0.15): met in all four; F = 20 is the tightest (0.083, upper 0.114). Application-only set V-M2 (14 families, 200 permutations, not judged): P(BIASED) 0.090 [0.054, 0.139], **P(VALID) 0.170 [0.121, 0.229]: the calibrated gate cannot certify at 14 families** (registered 0.015).

**PASS-B (detection of planted shortcuts) and PASS-C (no VALID on a shortcut).** Detection (P(BIASED)) was 1.00 in every shortcut cell at AUROC 0.65 and 0.70 (S-tpsa, S-typ, S-diffuse at 25, 20 and 47 families; S-cens at 25 families, 0.65 only; 60 records per cell, exact lower 95 % bound about 0.94); P(VALID | shortcut at 0.65) = 0.00 in every cell. Detection at weaker shortcuts (AUROC 0.55-0.60) was not pre-registered and was not tested for the calibrated gate (the registered gate's curve is in the positive-control results).

**Application to the real benchmarks (calibrated gate; verdicts compared with the registered gate).**
| benchmark | calibrated T vs q | controls beyond q | within-target permutation p (fresh null, N) | registered verdict | calibrated verdict |
|---|---|---|---|---|---|
| analysis I (26 families) | 10.82 vs 3.14 | C4 censored label (std z -10.8), C5 Ki-or-Kd (3.2), o_frac | 0.0025 (400; the smallest attainable) | NOT_VALID_BIASED | BIASED (unchanged) |
| M2 (14 families) | 5.06 vs 3.05 | fsp3, has_halogen (secondary) | 0.0050 (200; the smallest attainable) | NOT_VALID_BIASED | BIASED (unchanged) |
Reading. The verdict does not change for either benchmark, but its basis does. On analysis I the three primary compound-only controls are inside the calibrated null (standardised values 0.12, 1.93, 2.84 against q = 3.14); the BIASED verdict is carried by the censoring and assay-type controls (C4 point estimate 0.206 family-mean AUROC, 95 % interval [0.134, 0.280]: an inverted AUROC of 0.794), which do not depend on the calibration. The primary-control evidence the registered gate used for analysis I (for example C3 = 0.584) is therefore not by itself outside what exchangeable benchmarks produce at this size. On M2 no primary control is beyond q individually (2.82, 2.62, 1.98 against 3.05), and the verdict rests on the secondary controls fsp3 and halogen content plus the permutation test (p = 0.005). Equivalence is not reached for the primary controls on either benchmark (analysis I: C2, C3 outside delta = 0.056; M2: all three outside delta = 0.075).
The exact-potency benchmark of pilot 4 is a ranking task without decoy classes; the gate (AUC of control scores for positives against decoys) is not applicable and was not run.

**Limits.** Calibration nulls are label permutations of real benchmark structure and synthetic family structures that share the real compound pool; real benchmarks can be biased in ways no permutation reproduces. kappa and q are pooled over F within type (the validation cells at F = 20, 26, 47 and the 25-family real structure support that pooling; the 14-family M2 set is only an application). Planted shortcuts are single known properties (S-diffuse is a mixture) at AUROC >= 0.65. Detection of 1.00 at 0.65-0.70 does not establish sensitivity below 0.65. Percentile-bootstrap SEs are approximated from stored interval widths; the max statistic is dominated by secondary controls when they are many. Spend: stage 1 (three short c5.9xlarge spot instances) and the validation run (c5.9xlarge, about 35 min) estimated under USD 0.6 from instance times at the spot price (no cost log; instances terminated).

**Erratum (2026-10-29, after the paper-1 writer flagged it):** the number of fresh validation records is 2,940 (1,800 permutation/synthetic-null: 400 V-I + 200 V-M2 + 3 x 400 V3; 420 planted shortcuts on analysis I: 7 cells x 60; 720 on synthetic benchmarks: 12 cells x 60), matching `n_records` in `gcal_eval.json`; earlier text in this document that says 2,900 was my estimate and is wrong. No analysis depended on it.
