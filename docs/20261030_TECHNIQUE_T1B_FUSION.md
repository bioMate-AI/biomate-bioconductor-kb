# Technique T1b — learned prior (PT) fused with the analog component by a reliability-weighted rule (pre-registration, 2026-10-30)

Status: **PRE-REGISTRATION, committed before any T1b score was computed.** Results go below the line "RESULTS" after that commit. Code: `research/guangzhou_all_atom/cyclic_llm/technique_sprint/fusion_b/` (reuses `fusion/fusion.py`, `fusion/perm_testbed.py` read-only by import). CPU only, no paid APIs.

## 0. Disclosure: this follows an observed result
T1 (`20261030_TECHNIQUE_T1_FUSION.md`) was run and read first. What I had seen when writing this: in permeability, a HistGB prior PT (trained on the other labs) scored mean Spearman 0.419 / 0.368 / 0.381 at k = 5 / 10 / 25 and PT + analog residual correction (PT+k) 0.454 / 0.429 / 0.419, above the K_phys fusion (0.30 / 0.35 / 0.36); in binding, nearest-neighbour (NN) 0.753 / 0.822 / 0.869, frozen PT 0.539 (k = 0), F(PT, NN) not better than NN. So the choice of PT as prior, the comparator set, and the expectation that a learned prior helps in permeability were informed by test-set outcomes of T1. This is a **second look at the same labs/targets**, not a fresh confirmation; no new data. Any positive result is exploratory with respect to those labs/targets.

## 1. Hypothesis
With k revealed labels, the reliability-weighted fusion
  s(x) = w_k · z(PT(x)) + (1 − w_k) · r · z(A(x; revealed)),  w_k = n0 / (n0 + k),
with PT a learned prior trained on training labs/families only (no revealed labels), A the analog estimate and r ∈ [0, 1] the leave-one-out reliability of A from the revealed set (`fusion.fuse2`, `reliability_perm` / `reliability_nn`, constants unchanged: R0 = 0.5, M0 = 3), is
 (a) **non-inferior** (point estimate ≥ −0.03 vs the best comparator at every k), and
 (b) **better than the best of {PT+k, PT, A (NN for binding)} at some k ∈ {5, 10, 25}**, where "best" is the comparator with the highest mean on the evaluation units at that k (chosen on the evaluation data = conservative).
Primary n0 = 5 (fixed). Secondary: F1b (same without r) and n0 ∈ {1, 2, 10, 25}, reported descriptively, no best-of-grid claim. At k = 0 the score is PT by construction.
Prior art: shrinkage/residual-correction combinations are standard; **no novelty is claimed for the formula**; the claim is about measured behaviour on these two few-label settings.

## 2. PT definitions fixed here
- **Permeability PT:** `HistGradientBoostingRegressor(max_iter=100, max_bins=31, learning_rate=0.1, max_leaf_nodes=31, min_samples_leaf=20, l2_regularization=0.0, early_stopping=False, random_state=0)`; features = 1024-dim log1p chirality-aware Morgan radius-2 count bits + 9 physchem descriptors (`stratification/common.FAMILIES['physchem']`: mw, tpsa, logp, hbd, hba, rotb, arom_rings, heavy, fsp3); target = within-source-z label; training set = all labelled CycPeptMPDB peptides outside the held-out lab (including labs with < 20 peptides) minus peptides flat-identical (stereo-free SMILES) to any peptide of the held-out lab. One model per held-out lab (21), predictions cached. This is the same specification as the PT of T1 (reduced from the earlier loop's 150 iterations / 255 bins for speed; unchanged here so that T1b is comparable to T1).
- **PT+k (permeability):** score = z(PT) + (W r)/(ΣW + 0.05), W = Tanimoto^4 to the revealed items, r_j = standardised revealed label − standardised PT at the revealed item (T1 definition; PT standardisation over the evaluated candidate set).
- **A (permeability):** `fusion.analog_perm` (T1 definition). Analog similarity: chirality-aware Morgan 2048-bit Tanimoto.
- **Binding PT, NN, PT+k, FP-k, R:** the frozen H4b baseline definitions of `retro_recovery/11_h4b_run.py` (logistic regression on 1024-dim log1p chirality-aware count fingerprints, C = 0.05, other folds' labelled pairs, flat-siblings removed; NN = max-sim to revealed positives − max-sim to revealed inactives; PT+k = warm-started refit with revealed items weighted 20). I re-implement PT+k and must reproduce the frozen per-target values (audit, §6).

## 3. Testbed 1 — permeability leave-labs-out few-label
Same cells as T1: labs with ≥ 20 peptides (21), k ∈ {5, 10, 25}, seeds 0–4, reveal by `crc32("lab|k|seed")`, flat-siblings of revealed items excluded from evaluation, cells with < 20 items or constant labels dropped. Metric Spearman(score, raw lab-scale label). Aggregate: mean over seeds per lab; mean over labs; **lab-cluster bootstrap** (B = 5000). Comparators and fusion on the same cells and labs (labs present for all arms).

## 4. Testbed 2 — binding few-label H4b (analysis I)
Frozen reveal sets / eligibility (`h4b_reveals.csv.gz`, `h4b_eligible.csv`; k ∈ {5, 10, 25}; seeds 0–4), per-target AUROC / EF5 / P10 → mean over seeds → family mean → **family-cluster bootstrap** (harness `boot_mean`, `boot_diff`, B = 2000; B = 5000 for the multiplicity-adjusted interval). Arms: R, NN, FP-k, PT, PT+k (frozen), F1b(PT, NN), F2b(PT, NN) (primary), also F2b(PB, NN) with the T1 typicality-free prior as a secondary prior. Official plug-in `run_s3.py --k` for the contamination-controlled subset. 
- **Analog-distance strata (new):** within every (target, k, seed) cell, remaining items are split at the cell median of their maximum Tanimoto to the revealed set into near / far halves; AUROC computed per half (cell dropped for a half with < 3 items of a class); target → family aggregation as above. Reported for NN, PT, PT+k, F1b, F2b. Purpose: show whether any fusion gain lives where analogs exist (near) or where they do not (far). Descriptive, not part of the kill criteria.
- **Control-adjusted rule (A7/A8):** an arm is SUPPORTED only if the family-bootstrap lower bound of its paired difference vs the strongest of {frozen baselines R, NN, FP-k, PT, PT+k; gate controls C1–C3 at that k} exceeds 0, and its gain over its own k = 0 value has lower bound > 0. The A7 gate for I is INVALID at every k (C3 above chance), so no arm is described as validated.

## 5. Kill criteria and multiplicity (registered)
- **Per testbed, (b) is supported only if, at some k, point difference ≥ +0.02 (Spearman for permeability, AUROC for binding) against the best comparator AND the lower bound of the Bonferroni-adjusted interval (3 values of k per testbed → 98.33 % bootstrap interval) is > 0.** The nominal 95 % interval is also reported, labelled "nominal, unadjusted". Cluster type is stated with every interval: permeability = lab-cluster, binding = family-cluster. No correction across the two testbeds (they are reported separately and are never pooled into one claim).
- (a) fails if at any k the point difference vs the best comparator is < −0.03; formal non-inferiority (95 % lower bound > −0.05) reported as secondary.
- Outcomes per testbed: SUPPORTED = (a) and (b); PARTIAL = (a) only; NULL = (b) fails; FAILED = (a) fails. Binding additionally needs the control-adjusted rule for "SUPPORTED".
- Power note: permeability 9–17 labs, binding 21–26 families; "not detected" ≠ "no effect".

## 6. Controls (must pass before real-data results are read)
1. **Planted-signal tests** (`fusion_b/test_fusion_b.py`, synthetic, 20 seeds, n = 400, k ∈ {5, 10, 25}): prior = noisy copy of the latent signal, analog = cluster structure. (i) prior-informative world, analog uninformative: F2b ≥ 0.85 × PT at every k; (ii) analog-informative world, prior = noise: F2b at k = 25 ≥ A − 0.03; (iii) both informative: F2b ≥ max(PT, A) − 0.03 at every k (non-inferiority to components; superiority over PT+k is NOT required in the synthetic world); (iv) k = 0 returns PT ordering; PT+k construction recovers a planted residual cluster (PT+k > PT when the residual is cluster-structured). Failures are disclosed and trigger an amendment before real data, as in T1.
2. **Shuffled-label control:** permeability: labels permuted within each lab (PT retrained on shuffled training labels for each held-out lab, 3 shuffles, all 21 labs); each arm's mean Spearman must be within ±0.03 of 0 with the lab-cluster CI containing 0. Binding: labels permuted within target (items, reveals, and the training labels of PT; 2 shuffles); family-mean AUROC for every arm within ±0.03 of 0.5 with CI containing 0.5. A failure invalidates that testbed's run.
3. **Audit before reading results:** independent brute-force recomputation of PT+k and fusion for 3 permeability cells (deterministic PT predictions shared); binding PT+k must reproduce `h4b_per_target.csv` PT+k AUROC/EF5 within 1e-6; NN, PT parity as in T1.
4. Binding gate controls C1–C3 per k from the frozen `validity_gate_h4b.json`.

## 7. Claim limits
Scope: PAMPA permeability (CycPeptMPDB) and analysis-I binding only; no generation, no wet lab. Positive results are exploratory (second look, §0) and would need fresh labs/targets for confirmation. The "analog" component is nearest-neighbour similarity, not target-aware.

## AMENDMENT A1 (2026-10-30; committed BEFORE any real-data T1b score)
**Planted control 6.1(i) failed marginally:** prior-informative world, F2b = 0.665 / 0.608 / 0.662 at k = 5 / 10 / 25 vs 0.85 × PT = 0.609 at every k: the k = 10 value misses by 0.001 (0.8484 × PT). (ii) analog-informative (F2b at k = 25 = 0.659 vs A 0.684), (iii) both-informative (F2b 0.501 / 0.575 / 0.659 vs max(PT, A) 0.441 / 0.440 / 0.487) and (iv) pass; PT+k recovers the planted cluster residual (0.687 / 0.670 / 0.653 vs PT 0.717 in the prior-only world — PT+k loses 0.03–0.06 there; 0.495 / 0.545 / 0.646 vs 0.441 in the both-informative world).
**Decision (no threshold or formula change):** F2b with n0 = 5 stays primary exactly as registered and is **labelled "failed planted control (i), marginal (k = 10)"** wherever reported; this label limits what a positive (b) result can mean (it cannot be attributed to a formula proven to be safe when the prior is the only informative component). n0 = 10 (already in the registered secondary grid) is reported descriptively; moving n0 after seeing the control would be tuning the primary arm on a synthetic world I had already seen in T1 (identical F2 numbers: 0.665 / 0.608 / 0.662). All other registrations unchanged.

---
## RESULTS
(appended after the pre-registration commit)
