# Technique T1 — evidence-weighted fusion of a knowledge prior and analog lookup (pre-registration, 2026-10-30)

Status: **PRE-REGISTRATION, written and committed before any fusion score was computed.** Results are appended below the line "RESULTS" only after this commit.
Owner of this file: technique-sprint fork T1. Code: `research/guangzhou_all_atom/cyclic_llm/technique_sprint/fusion/`. CPU only, no paid APIs.

## 0. What I had already seen (disclosure)
Published numbers only: H4b baselines on analysis I (nearest-neighbour AUROC 0.753 / 0.822 / 0.869 at k = 5 / 10 / 25; no-target PT ≈ 0.52–0.54; `retro_recovery/results/h4b_baselines.json`), the A7 gate results on the H4b remaining-item sets (C3 above chance at every k), and the K_phys leave-one-lab-out summary (median per-lab ρ 0.25 [0.13, 0.49], 19/21 labs positive; pooled 0.39; `kb_audit/lolo_summary.json`). No fusion score of any kind has been computed.

## 1. Hypothesis
With k revealed labels for a new lab (permeability) or new target (binding), the score
  s(x) = w_k · z(P(x)) + (1 − w_k) · z(A(x; revealed)),  w_k = n0 / (n0 + k),
where P is a knowledge/learned **prior** (label-free at inference) and A an **analog estimate** from the revealed items, is
 (a) **non-inferior:** at every k ∈ {5, 10, 25}, not worse than the better single component by more than 0.03 (point estimate of the paired difference), and
 (b) **complementary:** better than BOTH components at some k ∈ {5, 10, 25}, because P is informative where A has nothing (k = 0, and items dissimilar to every revealed item) while A dominates where analog series exist.
At k = 0, w = 1 and s = z(P) by construction (no claim is made at k = 0 other than it equals the prior).
z(·) = centre and scale over the evaluated candidate set of that (lab or target, k, seed); a constant component contributes 0.
Generic prior art: shrinkage/Bayesian fusion and retrieval-augmented scoring are standard; **no novelty is claimed for the formula**. The contribution, if any, is the measured behaviour on cyclic-peptide permeability/binding few-label settings.

## 2. Definitions fixed here
- **Analog estimate.** Similarity s_ij = Tanimoto on chirality-aware Morgan radius-2, 2048-bit fingerprints. Permeability: A_i = Σ_j s_ij⁴ (y_j − ȳ_rev) / (Σ_j s_ij⁴ + 0.05) with y = raw lab-scale label (ranking is invariant to the lab offset). Binding: A_i = NN score of H4b = max_s(i, revealed positives) − max_s(i, revealed inactives) (identical to the frozen baseline arm NN). Kernel exponent and λ fixed a priori, not tuned.
- **Sibling exclusion.** Evaluated items exclude revealed items and items flat-identical (stereo-free SMILES) to a revealed item (as in H4b); sensitivity analysis includes them (permeability only).
- **n0.** Primary n0 = 5 (equal weight when k = 5), fixed in advance. Grid {1, 2, 5, 10, 25} reported as sensitivity only; **no best-of-grid claim**. Secondary (permeability only): n0 chosen from the grid by nested inner leave-one-training-lab-out CV (mean Spearman over inner labs at k ∈ {5, 10, 25}, 2 seeds, rules re-mined excluding both the outer and inner lab); reported separately and not used for the kill criteria.
- **Descriptive only:** the curve over fixed w ∈ {0, 0.1, …, 1} at each k (shows headroom; not a claim).

## 3. Testbed 1 — permeability, leave-labs-out few-label
- Data: CycPeptMPDB labelled set (6,960 peptides; `stratification/common.load_labelled`), labs with ≥ 20 peptides (21). A (lab, k, seed) cell is evaluated if ≥ 20 items remain after exclusions and the remaining raw labels are not constant. Seeds 0–4; reveal = k peptides drawn without replacement with a seed from `crc32("lab|k|seed")`.
- Prior P = K_phys of `kb_audit/peptide_sar_kb.py`, rules **mined from the other eligible labs only** (`fit(pairs, d, train=eligible \ {L})`), channel standardised within the held-out lab (label-free feature normalisation).
- Arms: K (prior alone), A (analog alone = NN-to-revealed), **F** (fusion, primary n0 = 5), GBM-revealed-only (random forest, 200 trees, chirality-aware bits, trained on the revealed items), PT (HistGradientBoosting on training labs: chirality-aware count bits + physchem descriptors, within-source-z labels, trained excluding the held-out lab), PT+k (PT plus analog residual correction: z-scored PT + Σ w_ij r_j /(Σ w_ij + 0.05) with r_j = revealed standardised label − standardised PT at the revealed item). Chirality-aware features throughout.
- Metric: Spearman(score, y_raw) over the evaluated items; mean over seeds per lab; aggregate across labs by mean and median; 95 % lab-cluster bootstrap (B = 2000). Paired differences F − max(K, A) use the better component **chosen on the evaluation labs** (conservative).
- Number of labs per k is determined by eligibility and reported; no lab is dropped otherwise.

## 4. Testbed 2 — binding few-label (H4b on analysis I)
- Frozen reveal sets and eligibility (`data/h4b_reveals.csv.gz`, `h4b_eligible.csv`; k ∈ {5, 10, 25}; seeds 0–4) and the frozen baseline machinery of `11_h4b_run.py` (PT, NN, FP-k, PT+k).
- Primary prior P_B: logistic regression on the **typicality-free proxies** {heavy, charge, n_frac, o_frac, has_s, has_halogen, ncaa_frac, n_arom, tpsa, logp, hbd, hba, rotb, fsp3, ring, n_rings, n_alpha} (standardised), trained on labelled pairs (pos vs inactive) of the **other folds** (flat-siblings of held-out compounds removed, as for PT; C = 0.5). This is a compound-only learned prior, **the same information class as validity control C2**, and is flagged as such. Secondary prior: PT (frozen). Primary fusion arm F_B = F(P_B, NN); secondary F_PT = F(PT, NN).
- Metrics and aggregation exactly as H4b (`harness.boot_mean`, `boot_diff`): per-target AUROC / EF5 / P10 → mean over seeds → family mean → family-cluster bootstrap. Score files (target_key, compound_id, score, seed) are also run through the official plug-in `run_s3.py --k K` for the contamination-controlled subset and the vs-baselines table.
- **Control-adjusted rule (A7/A8):** an arm is SUPPORTED only if its family-bootstrap lower bound of the paired difference exceeds 0 against the strongest of {frozen baselines (NN, FP-k, PT, PT+k, R), C1, C2, C3 at that k} and its gain over its own k = 0 value has lower bound > 0. The gate itself is INVALID for I at every k (C3 above chance), so no arm is described as validated; "SUPPORTED" means control-adjusted only.

## 5. Kill criteria (registered)
- **Permeability:** hypothesis (b) is **not supported (null)** if at no k ∈ {5, 10, 25} the paired difference F − max(K, A) has point ≥ +0.02 Spearman AND lower 95 % bound > 0. (a) fails if at any k the point difference < −0.03.
- **Binding:** (b) is **not supported (null)** if at no k ∈ {5, 10, 25} F_B − NN has point ≥ +0.02 AUROC AND family-bootstrap lower bound > 0 AND the control-adjusted rule holds. (a) fails if at any k F_B − NN < −0.03.
- Outcomes: SUPPORTED = (a) and (b) in a testbed; PARTIAL = (a) only; NULL = (b) fails; FAILED = (a) fails. Both testbeds are reported whatever happens.
- Power note: permeability aggregates over ≤ 21 labs (fewer at larger k) and binding over 39–45 targets in 21–26 families; small effects may be undetectable. A non-supported result is reported as "not detected", not as evidence of no effect.

## 6. Controls (must pass before any real-data result is read)
1. **Planted-signal unit tests** (`test_fusion.py`, synthetic worlds, n = 400, 20 seeds): (i) prior-only world: fusion at k = 5 reaches ≥ 0.8 × the prior-only Spearman and is not worse than A by > 0.03; (ii) analog-only world (prior = noise): at k = 25 fusion is within 0.03 of A; (iii) both-signals world: fusion exceeds max(K, A) by ≥ 0.02 at some k. (iv) constant component handled (z → 0, no NaN); (v) k = 0 returns the prior ordering.
2. **Shuffled-label control on real data (permeability):** labels permuted within each lab before mining and before reveal/evaluation (5 shuffles); each arm's mean Spearman must be within ±0.03 of 0 with the CI containing 0; a failure invalidates the permeability run (audit first).
3. **Binding validity:** the per-k gate (C1–C3) is recomputed on the remaining-item sets (frozen `validity_gate_h4b.json`); any arm using only compound-level information (P_B) is compared with C2.
4. **Code audit before running:** independent recomputation of the permeability analog estimate and fusion for 3 (lab, k, seed) cells with a separate brute-force implementation; the binding NN arm must reproduce the frozen `h4b_per_target.csv` NN values to 1e-6.

## 7. Claim limits
Scope: PAMPA permeability (CycPeptMPDB) and the analysis-I binding set only; no claim about generation, wet lab, or other properties. A fusion that beats its components on permeability is a statement about the K_phys prior and the analog kernel used; binding results are control-adjusted. Contamination-controlled subset reported side by side.

## AMENDMENT A1 (2026-10-30; committed BEFORE any real-data fusion score was computed)
**Why.** The registered planted-signal control 6.1(i) (prior-only world, analog component uninformative) FAILED for the pre-registered fusion F1: at k = 5 Spearman 0.571 vs the criterion 0.8 × prior = 0.573 (marginal miss), and clearly degrading at larger k (k = 10: 0.428; k = 25: 0.181; prior alone 0.717 at all k; analog alone ≈ 0). Controls (ii) and (iii) passed. This is a property of the formula, not a code error (checked: z(·), k = 0, constant component all behave as specified): weight depends on k only, so weight shifts to the analog component even when it carries no information. By my own rule (§6) F1 therefore cannot be the primary test.
**F2 (reliability-weighted).** s2 = w_k · z(P) + (1 − w_k) · r · z(A), with r ∈ [0, 1] the leave-one-out reliability of the analog component estimated from the revealed set only: for revealed items with analog mass Σ s^p > 0.01, r̂ = clip(Spearman(A^{−j}, y_j), 0, 1); r = (m r̂ + 3 · 0.5)/(m + 3), m = number of usable revealed items (r = 0.5 if fewer than 3 revealed). Constants (prior mean 0.5, pseudo-count 3) fixed once and tested on synthetic worlds only. Binding analogue: r̂ = clip(2·AUC_LOO − 1, 0, 1) on the revealed items with both classes available in the leave-one-out reference.
**Controls for F2 (synthetic, 20 seeds; `test_fusion.py`) — all passed:** prior-only world F2 = 0.665 / 0.608 / 0.662 at k = 5 / 10 / 25 (prior alone 0.717, i.e. ≥ 0.85 × prior everywhere; within 0.03 of the best component NOT achieved — the price of not knowing the reliability); analog-only world F2 at k = 25 = 0.659 vs analog 0.684 (within 0.03); both-signals world F2 = 0.501 / 0.575 / 0.659 vs best component 0.441 / 0.440 / 0.487 (exceeds by ≥ 0.02 from k = 5). F1 in the same worlds: 0.495 / 0.551 / 0.604 (both-signals).
**Consequence for the registered claims.** F2 is the PRIMARY fusion for the kill criteria of §5; F1 is reported as the pre-registered original and labelled "failed planted control (i)"; no result is selected by looking at real data. Hypothesis (a) is evaluated empirically on real data for F2 (and F1); it cannot hold in all worlds (see control (i)). All other registrations (data, n0 = 5, eligibility, arms, metrics, kill thresholds, shuffled-label control, audit steps) are unchanged.

---
## RESULTS (appended after pre-registration commit 855209794 and amendment A1 commit eab45dfa5; code and artefacts in `research/guangzhou_all_atom/cyclic_llm/technique_sprint/fusion/`)

### R1 Controls and audit
- **Planted-signal controls (synthetic, 20 seeds):** F1 FAILED registered control 6.1(i) (prior-only world, k=5: 0.571 vs threshold 0.573; k=10 0.428; k=25 0.181; prior alone 0.717) → amendment A1; F2 passes all three worlds; controls (ii), (iii) and the reliability functions (`reliability_perm`: informative 0.79 vs random 0.20; `reliability_nn`: 0.90 vs 0.21) pass.
- **Independent brute-force audit (3 cells; pure-python loops + RDKit BulkTanimoto):** worst |difference| 5.6e-17 for K, A, F1, F2 and the reliability r (first attempts showed 1–4e-6; causes: float32 Tanimoto, and 1-ulp float noise breaking exact mathematical ties differently; fixed by float64 and rounding scores to 10 decimals before ranking in both implementations). Binding: my NN and PT arms reproduce the frozen `h4b_per_target.csv` AUROC and EF5 with max |diff| = 0.0 (640 and 686 cells).
- **Shuffled-label control (permeability, 5 shuffles):** A, F1_5, F2_5 pass (all |mean| ≤ 0.03, CI contains 0 at every k; e.g. k=25: A +0.018, F1 +0.019, F2 +0.021). The prior K is non-constant in only 2–4 labs after shuffling (spurious rules rarely activate), so a dedicated control with 40 shuffles was run (`k_null_control.py`): K non-constant in 55/840 (shuffle, lab) rows (11 shuffles); pooled mean ρ = +0.015; mean of shuffle means −0.033, 95 % shuffle-bootstrap CI [−0.089, +0.019] (contains 0; the −0.033 narrowly exceeds the ±0.03 magnitude rule on this aggregation, the pooled mean does not). No evidence of leakage; low information.

### R2 Testbed 1 — permeability leave-labs-out few-label (CycPeptMPDB; labs with ≥ 20 peptides; 5 seeds; sibling-excluded; n0 = 5)
Mean within-lab Spearman across labs [95 % lab-bootstrap CI]; labs per k = 17 / 15 / 9.
| k | K (prior) | A (analog) | F1 (as registered) | F2 (A1, primary) | F1 − best component | F2 − best component |
|---|---|---|---|---|---|---|
| 5 | 0.261 [0.129, 0.391] | 0.227 [0.139, 0.323] | 0.301 [0.208, 0.400] | 0.302 [0.187, 0.415] | +0.041 [−0.044, 0.142] (best = K) | +0.041 [−0.001, 0.091] |
| 10 | 0.212 [0.080, 0.354] | 0.309 [0.204, 0.419] | 0.350 [0.242, 0.462] | 0.336 [0.226, 0.458] | +0.041 [−0.002, 0.084] (best = A) | +0.027 [−0.066, 0.115] |
| 25 | 0.180 [0.028, 0.329] | 0.333 [0.267, 0.404] | 0.364 [0.288, 0.450] | 0.329 [0.217, 0.447] | **+0.031 [0.007, 0.055]** (best = A) | −0.004 [−0.105, 0.074] |
- Sensitivity: sibling-inclusive (stereo/flat siblings of revealed items left in): F1 0.319 / 0.358 / 0.402 vs K 0.270 / 0.218 / 0.200 and A 0.243 / 0.319 / 0.372 (same ordering). n0 grid for F1 (k = 5/10/25): n0=1 0.265/0.329/0.338, 2 0.282/0.340/0.345, 5 0.301/0.350/0.364, 10 0.300/0.351/0.372, 25 0.287/0.305/0.355 (flat, no best-of-grid claim). Descriptive weight curve (F1 form): maximum at w ≈ 0.6 (k=5; 0.307), 0.4 (k=10; 0.353), 0.3–0.4 (k=25; 0.373) — i.e. an interior optimum above both components at every k in the point estimates.
- Secondary nested-CV n0 (chosen 10 for 14 labs, 25 for 3): F1 − best = +0.036 [−0.022, 0.104] / +0.029 [−0.049, 0.106] / +0.008 [−0.060, 0.069]; F2 = +0.026 [−0.004, 0.060] / −0.008 / −0.052.
- Multiplicity (3 k tested): F1 at k=25, Bonferroni 98.3 % CI [0.003, 0.061]; positive in 6/9 labs (Townsend +0.052, Kelly +0.078, Ohta +0.053, Taechalertpaisarn +0.093, Bhardwaj +0.022, CHUGAI +0.008; negative: Furukawa −0.007, Naylor −0.010, Faris −0.014). Lab-level heterogeneity is large at k=5 (−0.19 to +0.67).

### R3 Testbed 2 — binding few-label H4b on analysis I (45 / 44 / 39 targets, 26 / 25 / 21 families at k = 5 / 10 / 25; 5 seeds)
AUROC family-mean [95 % family bootstrap]; prior P_B = logistic regression on typicality-free proxies (zero-shot AUROC 0.595 [0.551, 0.635]; frozen PT 0.539 [0.478, 0.605]); gate controls C1/C2/C3 at k = 5: 0.512/0.564/0.587; k=10: 0.518/0.564/0.567; k=25: 0.499/0.527/0.595.
| k | NN (strongest baseline) | F1(P_B, NN) | F2(P_B, NN) | F1 − NN | F2 − NN | F1(PT, NN) − NN |
|---|---|---|---|---|---|---|
| 5 | 0.753 [0.715, 0.789] | 0.744 [0.706, 0.780] | 0.697 [0.653, 0.739] | −0.009 [−0.029, 0.013] | −0.056 [−0.086, −0.025] | −0.049 [−0.076, −0.020] |
| 10 | 0.822 [0.784, 0.856] | 0.818 [0.779, 0.853] | 0.779 [0.735, 0.819] | −0.003 [−0.017, 0.012] | −0.042 [−0.064, −0.021] | −0.024 [−0.036, −0.012] |
| 25 | 0.869 [0.835, 0.899] | 0.875 [0.839, 0.906] | 0.866 [0.825, 0.900] | +0.005 [−0.000, 0.011] | −0.004 [−0.016, 0.007] | −0.002 [−0.008, 0.004] |
- Gain over the arm's own k = 0 value is large (F1(P_B): +0.149 / +0.225 / +0.295) but equals the analog-lookup gain (NN itself). Contamination-controlled subset (official `run_s3.py --k`): F1(P_B) − NN = −0.035 [−0.095, 0.027] / −0.029 [−0.082, 0.020] / −0.038 [−0.110, 0.025]; F2(P_B) − NN = −0.076 [−0.149, 0.002] / −0.075 [−0.147, −0.007] / −0.045 [−0.112, 0.017]. The plug-in reproduces the all-items numbers exactly.
- Validity: the gate is INVALID for analysis I at every k (C3 above chance); P_B is a compound-only learned prior, the same information class as control C2, so no arm here is described as validated.

### R4 Registered outcomes
| testbed / variant | (a) non-inferior at every k (point ≥ −0.03) | (b) better than best single component at some k (≥ +0.02 and CI lower bound > 0) | outcome |
|---|---|---|---|
| Permeability, **F2 (primary, A1)** | yes (+0.041, +0.027, −0.004) | **no** (k=5: lower bound −0.001; k=10: −0.066; k=25: −0.105) | **NULL (not detected)** |
| Permeability, F1 (as registered; failed planted control (i)) | yes | yes at k=25 only (+0.031 [0.007, 0.055]) | SUPPORTED by the letter of the rule, but F1 is not primary; fragile (nested-n0 version +0.008 [−0.06, 0.07]; 9 labs; best component chosen on the evaluation labs) |
| Binding, **F2(P_B, NN) (primary)** | **no** (k=5 −0.056, k=10 −0.042) | no | **FAILED** |
| Binding, F1(P_B, NN) | yes (−0.009, −0.003, +0.005) | no (k=25 +0.005 < 0.02) | PARTIAL ((a) only) |

### R5 What this supports and does not
- In permeability the prior and the analog component are complementary in the point estimates at every k (fusion above both components by about 0.03–0.04 Spearman over a broad range of w), but with 9–17 labs the registered primary test (F2) does not detect it; F1 clears the rule at one of three k with a lower bound of 0.007. Treat as suggestive, not demonstrated.
- In binding the analog lookup (NN) already carries the signal; a compound-only prior (zero-shot AUROC 0.595) adds nothing at any k, and the reliability weighting hurts because leave-one-out reliability from k ≤ 25 revealed items underestimates the analog component's reliability (r shrinks toward 0.5).
- The planted-signal result is a property of the idea, not just the code: a k-only weight cannot know that the analog component is uninformative; any reliability estimate from a handful of revealed items is noisy.

### R6 Errors found in my own work (all fixed or disclosed)
(1) The registered formula F1 failed its own planted control (disclosed, A1). (2) Float32 Tanimoto and 1-ulp tie breaking caused 1–4e-6 audit differences (fixed). (3) Eligibility guard missing for labs smaller than k (crash; fixed before any result). (4) macOS `sed -i` misuse (no effect). (5) The first K shuffled-label summary rested on 2–4 labs; replaced by the dedicated 40-shuffle control. (6) First F2 controls were defined after the test runner and did not run until the runner was moved (no result affected).

### R7 Gaps
Pretrained-GBM baselines (RF on revealed, PT, PT+k) for the permeability testbed are computed in the full run (`perm_cells.csv`) and appended below if finished; independent audit covered 3 cells; the binding prior is not mined "knowledge"; no multiplicity rule was registered (Bonferroni view given as descriptive); F1/F2 choice and n0 = 5 were fixed before real data but F2's constants were tuned on synthetic worlds; permeability power is limited (9–17 labs, heavy lab heterogeneity).
