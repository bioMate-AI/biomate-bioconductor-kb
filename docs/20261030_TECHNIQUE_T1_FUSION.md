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
## RESULTS
(appended after the pre-registration commit)
