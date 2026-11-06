# IH-LM ladder (R0-R4) — results (T-LADDER). Status: COMPLETE (all 115 task files, development seeds 0-9 and confirmatory seeds 10-19); modules remain NOT CLAIMED under the pre-registered rule.
Pre-registration: `20261030_IHLM_LADDER_PREREG.md` (+ A1, A2). Code: `research/guangzhou_all_atom/cyclic_llm/ihlm_ladder/`. Retrospective replay on CycPeptMPDB permeability; no generation, wet-lab or foundation-model claim.

## 1. Pre-launch review note (written before the spot launch)
**What changed since the pre-registration (all before any scored run):** A2 (file split; E-score logging; zt control for all rungs; control definitions; Holm p) and one **code defect fixed at its root**: `IHLM.clone()` hard-coded the base class, so after the first `update` a ladder model silently became a plain `IHLM`, re-enabling the neural analog attention (M3) and neural edit residual (M4) that the pre-registration disables (they are expected-fail upstream). Found by the rung-wiring test (`m._pack(...)` returned a pack for R3). R3/R4 results produced before the fix would not have been the pre-registered rungs. The planted-signal tests were rerun after the fix.
**Gating conditions / silent skips traced:** (i) regime L anchors exist only for held-out labs with >= 20 peptides, taken from non-evaluation peptides (asserted in `world()`); (ii) a rung adds nothing if its layer receives no data — R4 equals R3 exactly when no N-Me/D-flip pair exists among revealed rows (tested: `test_rung_wiring`), so R4-R3 can be exactly 0 on a task, which is a real outcome, not a bug; (iii) R2's offsets are ~0 under `zc` unless replicate anchors exist (labels are already source-standardised), so R2-R1 is expected to be small; (iv) the shuffled control `R4_shuf` draws labels from the pool's label vector by design (L7d), so only labels OUTSIDE the pool are tested for isolation.
**Tests (all green before launch; bundle = repo HEAD):** core suite (9 tests: causal labels, world disjointness/anchors/determinism, hash-seed determinism of world and K-shuffle, label isolation through the runner for the learner, frozen/rule/random arms, neutral edit priors and the leak-guarded rule loader, aggregator on synthetic results) and full suite (planted K / offset / retrieval / edit; rung wiring; label isolation through all eight IH-LM arms; runner smoke output identical under PYTHONHASHSEED 1 and 2 and readable by the aggregator). IH-LM core tests: 12 passed, 3 expected-fail (unchanged).
**Cost projection (cap USD 6, spot only).** Measured on the loaded laptop for one regime-L task with the real parameters: R0 126 s, R1 105 s, R2 104 s, R3 92 s, R4 346 s (R4_shuf about the same, R1_kshuf like R1, R4_frozen about 40 s); GBM/kNN/GP/random_fb assumed about 20 min together (conservative). Plan = 85 units: 30 primary (A, B, L x seeds 0-9, zc, k = 5, all 13 arms, ~45 min each), 15 zt (A, B, L x seeds 0-4, R0-R4 + gbm_aware, ~21 min), 10 gc (A, L x seeds 0-4, R0-R4, ~13 min), 30 anchor-sensitivity (k = 0 and 10, seeds 0-4, R1/R2, ~3.5 min). ≈ 32 core-hours; one m6i.8xlarge spot (32 vCPU, 128 GB; 704 mUSD/h in us-west-2c), 30 parallel processes: ≈ 1.2-1.5 h wall + boot ≈ **USD 1.3**; hard `shutdown -h +200` caps it at ≈ USD 2.4. Optional arms not run: R1c (label-mined K), PT/PT+analog correction, L9 (regime M), confirmatory seeds 10-19 (only if a primary contrast has a lower bound > 0 on seeds 0-9, prereg section 5).
**Predictions written before any result (so they can fail):** first task files on S3 within ~20 min of launch (boot + installs ~10 min, then ~2 min to the first arm). M3 (symbolic retrieval) is the module most likely to show a gain, mainly in A (near-duplicate/stereoisomer analogs by design) and less in L; M1 (K prior) a modest gain in L; M2 ≈ 0 under zc; M4 ≈ 0 (R4 = R3 on many tasks). Under L, the pre-registered strong baselines (kNN, GBM) will probably match or beat the ladder; no claim of beating the larger comparators can be made from this run (they are not in it).
**External comparators.** GBM / kNN / GP / random feedback / rule_kphys are run inside this ladder under the same causal worlds. ChemBERTa and atom-LM exist only from the L7 runs (transductive standardisation, no anchors): they are cited as descriptive context from `loop_retro/results/l7_aggregate.json` (arm `loop_sub`, same candidate subsets), never as a paired contrast.

## 2. Results

### 2.0 Completeness and the shared-prefix overwrite incident
Files on `s3://biomate-nextflow-work/cyclic_peptide/ihlm_ladder/res/` (synced 2026-10-29 06:41 CDT), checked against the design: primary seeds 0-9 (zc, k = 5): 30/30 tasks, all 13 arms; confirmatory seeds 10-19: 30/30, all 13 arms; zt control (A, B, L x seeds 0-4; R0-R4 + gbm_aware): 15/15 complete; gc (A, L x seeds 0-4; R0-R4): 10/10; anchor sensitivity k = 0: 15/15 (R1, R2); k = 10: 15/15 (R1, R2). **Nothing is missing.** The first real instance was reclaimed by AWS after about 1.6 h; the job was resumed (second launch) and the pre-registered confirmatory seeds were started in parallel (third launch). **Incident:** both jobs synced one shared S3 prefix, and the confirmatory instance (which had downloaded the earlier partial files at its start) overwrote the resume instance's completed secondary files with its stale copies (gc R4, parts of zt, k = 10 were lost). The 30 primary tasks were complete before either launch and are unaffected. The lost arms were recomputed on the still-running confirmatory instance (55 units re-queued, finished arms skipped); all families are complete as listed. Rule from now on: **one writer per S3 prefix (per-run sub-prefix); never sync a whole directory to a prefix another job also writes.** Three earlier launches failed at boot (an IAM profile with no S3 access; torch installed from a CPU-only index; the first one silent because its own output was discarded): minutes of spot time. Spend: about 3.7 instance-hours of m6i.8xlarge at USD 0.706/h plus the failed launches = **about USD 2.7** (computed from launch and termination times, not from the AWS bill) against the USD 6 cap.

### 2.1 Verdict (read this first)
1. **No module is claimed.** Under the pre-registered rule (section 7 + A2) every module is "not claimed": the shuffled-label gate control fails in regimes A and L, and Holm-significance in both B and L is not reproduced on the confirmatory seeds for any module.
2. **What the data support, descriptively, at the pre-registered intervals.** M3 (symbolic analog retrieval, R3 − R2) is the only consistent effect: regime L development +12.1 [+6.5, +17.7] hits (Holm p 0.006), confirmatory +9.5 [+6.2, +12.8] (Holm p 0.002); regime B development +3.7 [+1.6, +5.8] (Holm p 0.021) but confirmatory +3.4 [+0.0, +6.8] (Holm p 0.195, not confirmed). M1 (K prior, R1 − R0) is positive in all four cells but significant in different regimes in development (B) and confirmation (L). M2 (lab offsets, R2 − R1) is null to negative (confirmatory B −2.7 [−5.1, −0.3]; E-AUROC lower in B and L in development). M4 (edit layer, R4 − R3) is null (|mean| <= 1.8 hits, intervals include 0) although R4's picks differ from R3's in 60/60 tasks.
3. **The ladder does not support "the in-house model beats baselines".** In the lab-shift regime L the full model R4 picks fewer hits than GBM and GP on both seed sets (confirmatory −8.0 [−13.0, −3.0] and −10.2 [−15.3, −5.1]) and is not better than kNN; it beats kNN in regime B (about +9 hits). A nuance: in L the held-out-lab *ranking* of R4 (E-AUROC) is above GBM (dev +0.056 [+0.014, +0.098]; conf +0.062 [−0.002, +0.126]), GP and kNN (kNN +0.133 and +0.154), while its selection *yield* is below GBM and GP; ranking and yield disagree, and only yield is the pre-registered primary metric. The larger pretrained models (ChemBERTa, atom LM, PeptideCLM) are not in this run. **This is not a claim of paper 1.**

### 2.2 Primary family — development seeds 0-9 (Holm, size 8)
### Primary family (Holm, size 8; metric Y = hits of 500; causal source-standardised labels `zc`, k = 5 anchors)

| contrast | module | regime | n seeds | mean paired diff [wider of (b) bootstrap, (c) t] | (a) percentile spread | MDD | Holm p | positive after Holm |
|---|---|---|---|---|---|---|---|---|
| R1-R0 | M1 knowledge prior | B | 10 | +1.70 [+0.94, +2.46] | [+0.2, +3.6] | 0.9 | 0.005 | yes |
| R1-R0 | M1 knowledge prior | L | 10 | +2.80 [-1.91, +7.51] | [-4.5, +14.9] | 5.8 | 0.846 | no |
| R2-R1 | M2 lab offset | B | 10 | -1.30 [-3.27, +0.67] | [-4.8, +3.9] | 2.4 | 0.846 | no |
| R2-R1 | M2 lab offset | L | 10 | -0.10 [-4.22, +4.02] | [-5.8, +10.2] | 5.1 | 1.000 | no |
| R3-R2 | M3 symbolic analog retrieval | B | 10 | +3.70 [+1.57, +5.83] | [+0.0, +7.8] | 2.6 | 0.021 | yes |
| R3-R2 | M3 symbolic analog retrieval | L | 10 | +12.10 [+6.47, +17.73] | [+1.2, +23.8] | 7.0 | 0.006 | yes |
| R4-R3 | M4 edit-space layer | B | 10 | +0.30 [-0.29, +0.89] | [-0.8, +1.8] | 0.7 | 0.936 | no |
| R4-R3 | M4 edit-space layer | L | 10 | +0.00 [-2.26, +2.26] | [-4.8, +4.6] | 2.8 | 1.000 | no |

### 2.3 Primary family — confirmatory seeds 10-19
Prereg section 5 trigger met: R1−R0 in B and R3−R2 in B and L had a bootstrap-mean lower bound > 0 on seeds 0-9. Analysed separately from the development seeds, not pooled.

### Primary family (Holm, size 8; metric Y = hits of 500; causal source-standardised labels `zc`, k = 5 anchors)

| contrast | module | regime | n seeds | mean paired diff [wider of (b) bootstrap, (c) t] | (a) percentile spread | MDD | Holm p | positive after Holm |
|---|---|---|---|---|---|---|---|---|
| R1-R0 | M1 knowledge prior | B | 10 | +2.50 [+0.71, +4.29] | [-1.0, +6.6] | 2.2 | 0.070 | no |
| R1-R0 | M1 knowledge prior | L | 10 | +7.30 [+4.00, +10.60] | [+0.2, +12.8] | 4.1 | 0.005 | yes |
| R2-R1 | M2 lab offset | B | 10 | -2.70 [-5.13, -0.27] | [-7.8, +1.8] | 3.0 | 0.166 | no |
| R2-R1 | M2 lab offset | L | 10 | -1.60 [-4.56, +1.36] | [-8.0, +3.8] | 3.7 | 0.506 | no |
| R3-R2 | M3 symbolic analog retrieval | B | 10 | +3.40 [+0.02, +6.78] | [-5.1, +9.6] | 4.2 | 0.195 | no |
| R3-R2 | M3 symbolic analog retrieval | L | 10 | +9.50 [+6.24, +12.76] | [+3.2, +17.4] | 4.0 | 0.002 | yes |
| R4-R3 | M4 edit-space layer | B | 10 | +0.70 [-1.05, +2.45] | [-3.3, +4.6] | 2.2 | 0.506 | no |
| R4-R3 | M4 edit-space layer | L | 10 | -1.80 [-3.85, +0.25] | [-5.8, +2.8] | 2.5 | 0.233 | no |

Pooled seeds 0-19 (exploratory and descriptive only; the pre-registered decision uses the two sets separately):

| contrast | regime | n seeds | mean [wider CI] | Holm p (family of 8 within the pooled set) |
|---|---|---|---|---|
| R1-R0 | B | 20 | +2.1 [+1.2, +3.0] | 0.002 |
| R1-R0 | L | 20 | +5.0 [+2.2, +7.9] | 0.007 |
| R2-R1 | B | 20 | -2.0 [-3.4, -0.6] | 0.038 |
| R2-R1 | L | 20 | -0.8 [-3.2, +1.5] | 0.619 |
| R3-R2 | B | 20 | +3.5 [+1.8, +5.3] | 0.003 |
| R3-R2 | L | 20 | +10.8 [+7.8, +13.8] | 0.002 |
| R4-R3 | B | 20 | +0.5 [-0.3, +1.3] | 0.619 |
| R4-R3 | L | 20 | -0.9 [-2.3, +0.5] | 0.619 |

### 2.4 Module claim table (pre-registered rule; both seed sets)
Development seeds:

### Module claims (all criteria must be met)

| module | status | criteria |
|---|---|---|
| M1 knowledge prior (R1-R0) | **not claimed** | holm_positive_B_and_L=False; planted_test_passed=True; controls_inside_margin_B_and_L=False; same_sign_under_zt=True |
| M2 lab offset (R2-R1) | **not claimed** | holm_positive_B_and_L=False; planted_test_passed=True; controls_inside_margin_B_and_L=False; same_sign_under_zt=False |
| M3 symbolic analog retrieval (R3-R2) | **not claimed** | holm_positive_B_and_L=True; planted_test_passed=True; controls_inside_margin_B_and_L=False; same_sign_under_zt=True |
| M4 edit-space layer (R4-R3) | **not claimed** | holm_positive_B_and_L=False; planted_test_passed=True; controls_inside_margin_B_and_L=False; same_sign_under_zt=True |

Confirmatory seeds (the zt control exists only for seeds 0-4, so that criterion is `None` = not assessable here, and is never counted as met):

### Module claims (all criteria must be met)

| module | status | criteria |
|---|---|---|
| M1 knowledge prior (R1-R0) | **not claimed** | holm_positive_B_and_L=False; planted_test_passed=True; controls_inside_margin_B_and_L=False; same_sign_under_zt=None |
| M2 lab offset (R2-R1) | **not claimed** | holm_positive_B_and_L=False; planted_test_passed=True; controls_inside_margin_B_and_L=False; same_sign_under_zt=None |
| M3 symbolic analog retrieval (R3-R2) | **not claimed** | holm_positive_B_and_L=False; planted_test_passed=True; controls_inside_margin_B_and_L=False; same_sign_under_zt=None |
| M4 edit-space layer (R4-R3) | **not claimed** | holm_positive_B_and_L=False; planted_test_passed=True; controls_inside_margin_B_and_L=False; same_sign_under_zt=None |

### 2.5 Controls, and why the pre-registered shuffled-label gate is not a valid null
Development seeds:

### Controls (equivalence margins: shuffled-label gain within ±10 hits / ±0.05 AUROC; wider interval inside the margin = inside)

| control | regime | metric | mean [wider CI] | margin | inside | MDD | gate |
|---|---|---|---|---|---|---|---|
| R4_shuf-random_fb | B | Y | +7.200 [+5.422, +8.978] | ±10.0 | yes | 2.20 | gate |
| R4_shuf-random_fb | B | AUROC | -0.061 [-0.115, -0.006] | ±0.05 | NO | 0.07 | gate |
| R1_kshuf-R0 | B | Y | -0.600 [-2.259, +1.059] | ±10.0 | yes | 2.05 | gate |
| R1_kshuf-R0 | B | AUROC | -0.006 [-0.041, +0.028] | ±0.05 | yes | 0.04 | gate |
| R1-R1_kshuf (K content contrast; 'no attributable content effect' if inside the margin) | B | Y | +2.300 [+0.546, +4.054] | ±10.0 | yes | 2.17 | report |
| R1-R1_kshuf (K content contrast; 'no attributable content effect' if inside the margin) | B | AUROC | +0.051 [+0.018, +0.084] | ±0.05 | NO | 0.04 | report |
| R4_shuf-random_fb | L | Y | +28.500 [+19.809, +37.191] | ±10.0 | NO | 10.76 | gate |
| R4_shuf-random_fb | L | AUROC | +0.029 [-0.002, +0.060] | ±0.05 | NO | 0.04 | gate |
| R1_kshuf-R0 | L | Y | -1.400 [-5.421, +2.621] | ±10.0 | yes | 4.98 | gate |
| R1_kshuf-R0 | L | AUROC | +0.018 [-0.009, +0.044] | ±0.05 | yes | 0.03 | gate |
| R1-R1_kshuf (K content contrast; 'no attributable content effect' if inside the margin) | L | Y | +4.200 [+0.213, +8.187] | ±10.0 | yes | 4.94 | report |
| R1-R1_kshuf (K content contrast; 'no attributable content effect' if inside the margin) | L | AUROC | +0.015 [-0.028, +0.057] | ±0.05 | NO | 0.05 | report |
| R4_shuf-random_fb | A | Y | +19.000 [+14.352, +23.648] | ±10.0 | NO | 5.75 | gate |
| R4_shuf-random_fb | A | AUROC | -0.198 [-0.220, -0.175] | ±0.05 | NO | 0.03 | gate |
| R1_kshuf-R0 | A | Y | +2.600 [-1.851, +7.051] | ±10.0 | yes | 5.51 | gate |
| R1_kshuf-R0 | A | AUROC | -0.005 [-0.029, +0.018] | ±0.05 | yes | 0.03 | gate |
| R1-R1_kshuf (K content contrast; 'no attributable content effect' if inside the margin) | A | Y | +2.200 [-2.661, +7.061] | ±10.0 | yes | 6.02 | report |
| R1-R1_kshuf (K content contrast; 'no attributable content effect' if inside the margin) | A | AUROC | +0.014 [-0.004, +0.032] | ±0.05 | yes | 0.02 | report |
| R4_shuf-rule_kphys (POST-HOC diagnostic: shuffled-label arm vs the label-free K rule) | B | Y | -1.800 [-4.515, +0.915] | ±10.0 | yes | 3.36 | report |
| R4_shuf-R1_kshuf (POST-HOC diagnostic) | B | Y | +3.100 [-0.313, +6.513] | ±10.0 | yes | 4.22 | report |
| R4_shuf-rule_kphys (POST-HOC diagnostic: shuffled-label arm vs the label-free K rule) | L | Y | -8.300 [-15.095, -1.505] | ±10.0 | NO | 8.41 | report |
| R4_shuf-R1_kshuf (POST-HOC diagnostic) | L | Y | -6.900 [-12.946, -0.854] | ±10.0 | NO | 7.48 | report |
| R4_shuf-rule_kphys (POST-HOC diagnostic: shuffled-label arm vs the label-free K rule) | A | Y | -9.200 [-13.990, -4.410] | ±10.0 | NO | 5.93 | report |
| R4_shuf-R1_kshuf (POST-HOC diagnostic) | A | Y | -7.300 [-13.564, -1.036] | ±10.0 | NO | 7.75 | report |

**Flaw in the pre-registered control (stated plainly).** The gate `R4_shuf − random_fb` compares an IH-LM arm that still carries the label-free K prior and analog retrieval (with labels shuffled) against a *different learner* (a GBM fed real labels from random picks). The shuffled arm therefore keeps whatever the label-free parts can do, and its E-AUROC is not comparable with the GBM's. It fails the ±10-hit margin in regimes L (+28.5 development, +32.6 confirmatory) and A, so it blocks every module claim. It is **not** evidence of label leakage: label isolation was tested directly (corrupting every unrevealed or held-out-lab label leaves every arm's picks and metrics unchanged, for all eight IH-LM arms), and the planted-signal tests pass. The **post hoc** comparison against the label-free K ranking (`R4_shuf − rule_kphys`, not pre-registered) is negative in L and A in development (−8.3 [−15.1, −1.5] and −9.2 [−14.0, −4.4]) and not positive in confirmation, i.e. shuffled labels add nothing beyond the label-free rule. The rule was **not** changed to rescue a claim; a corrected control (shuffled-label arm against its own label-free ablation) would need a dated amendment and a new run.

### 2.6 Baselines in every regime
Hits of 500, paired over seeds, wider of the bootstrap and t intervals; `dev` = seeds 0-9, `conf` = seeds 10-19.

| contrast (hits of 500, paired, wider interval) | A dev | B dev | L dev | A conf | B conf | L conf |
|---|---|---|---|---|---|---|
| R4 − GBM (chirality-aware) | -2.8 [-7.7, +2.1] | +2.2 [-1.0, +5.4] | -4.9 [-7.9, -1.9] | -3.6 [-6.3, -0.9] | +1.3 [-1.5, +4.1] | -8.0 [-13.0, -3.0] |
| R4 − kNN to revealed | +4.7 [-0.4, +9.8] | +9.3 [+7.5, +11.1] | -5.1 [-8.9, -1.3] | +4.5 [+0.9, +8.1] | +8.9 [+5.7, +12.1] | -1.7 [-7.5, +4.1] |
| R4 − GP (Tanimoto) | -5.3 [-9.6, -1.0] | +2.9 [+0.1, +5.7] | -9.3 [-13.0, -5.6] | -7.2 [-11.8, -2.6] | +3.2 [+0.5, +5.9] | -10.2 [-15.3, -5.1] |
| R4 − rule_kphys (label-free K ranking) | +9.1 [+5.1, +13.1] | +0.1 [-1.6, +1.8] | +14.8 [+7.1, +22.5] | +8.1 [+3.5, +12.7] | -3.7 [-5.9, -1.5] | +11.5 [+4.8, +18.2] |
| R4 − random picks (learner still fed) | +37.3 [+33.4, +41.2] | +9.1 [+7.1, +11.1] | +51.6 [+42.1, +61.1] | +38.2 [+32.4, +44.0] | +4.6 [+0.9, +8.3] | +50.6 [+45.7, +55.5] |
| R4 − R0 (net only) | +13.6 [+8.9, +18.3] | +4.4 [+2.6, +6.2] | +14.8 [+7.0, +22.6] | +15.4 [+10.9, +19.9] | +3.9 [+1.3, +6.5] | +13.4 [+10.1, +16.7] |

E-AUROC on the held-out slice after the last round:

| contrast (E-AUROC after the final round) | A dev | B dev | L dev | A conf | B conf | L conf |
|---|---|---|---|---|---|---|
| R4 − GBM | -0.033 [-0.059, -0.006] | -0.019 [-0.052, +0.013] | +0.056 [+0.014, +0.098] | -0.009 [-0.024, +0.006] | +0.011 [-0.019, +0.040] | +0.062 [-0.002, +0.126] |
| R4 − kNN | +0.026 [-0.008, +0.060] | +0.080 [+0.036, +0.125] | +0.133 [+0.073, +0.193] | +0.036 [+0.013, +0.060] | +0.141 [+0.113, +0.168] | +0.154 [+0.116, +0.191] |
| R4 − GP | -0.030 [-0.060, -0.001] | -0.004 [-0.046, +0.039] | +0.062 [+0.012, +0.113] | -0.025 [-0.043, -0.008] | +0.021 [-0.006, +0.047] | +0.079 [+0.030, +0.127] |
| R4 − R0 | +0.078 [+0.055, +0.101] | +0.079 [+0.021, +0.137] | +0.030 [-0.008, +0.067] | +0.071 [+0.049, +0.093] | +0.109 [+0.072, +0.145] | -0.026 [-0.065, +0.013] |

Regime L, held-out-lab cluster bootstrap (resampling labs within each seed), development seeds:

### (d) regime L, E-AUROC, held-out-lab cluster bootstrap (per seed resample of held-out labs; 1,000 resamples)

| contrast | seeds | labs per seed | mean | 95% percentile CI |
|---|---|---|---|---|
| R4-R3 | 10 | 6-18 | -0.005 | [-0.018, +0.013] |
| R4-R0 | 10 | 6-18 | +0.030 | [+0.002, +0.079] |
| R4-gbm_aware | 10 | 6-18 | +0.056 | [+0.034, +0.099] |
| R4-knn | 10 | 6-18 | +0.133 | [+0.081, +0.156] |

### 2.7 R4 versus R3 on the real data
Development: A: picks identical 0/10, hit counts identical 0/10; B: picks identical 0/10, hit counts identical 3/10; L: picks identical 0/10, hit counts identical 0/10. Confirmatory: A: picks identical 0/10, hit counts identical 0/10; B: picks identical 0/10, hit counts identical 0/10; L: picks identical 0/10, hit counts identical 0/10. The edit layer changes the picks in every task (edit effects are non-zero as soon as one edit pair is revealed) but does not change the hit count systematically.

### 2.8 Secondary schemes and anchor sensitivity (development seeds, 5 seeds each; exploratory)
| contrast | regime | scheme / k | n seeds | mean [wider CI] (hits) |
|---|---|---|---|---|
| R1-R0 | A | gc/k5 | 5 | +7.8 [+1.1, +14.5] |
| R2-R1 | A | gc/k5 | 5 | -5.0 [-14.2, +4.2] |
| R3-R2 | A | gc/k5 | 5 | +13.2 [+10.8, +15.6] |
| R4-R3 | A | gc/k5 | 5 | +0.0 [-5.9, +5.9] |
| R4-R0 | A | gc/k5 | 5 | +16.0 [+4.4, +27.6] |
| R1-R0 | L | gc/k5 | 5 | +6.4 [+3.0, +9.8] |
| R2-R1 | L | gc/k5 | 5 | +2.0 [-7.5, +11.5] |
| R3-R2 | L | gc/k5 | 5 | +8.2 [-3.8, +20.2] |
| R4-R3 | L | gc/k5 | 5 | +1.0 [-4.2, +6.2] |
| R4-R0 | L | gc/k5 | 5 | +17.6 [+0.7, +34.5] |
| R1-R0 | A | zt/k5 | 5 | +5.2 [-4.1, +14.5] |
| R2-R1 | A | zt/k5 | 5 | -2.2 [-9.7, +5.3] |
| R3-R2 | A | zt/k5 | 5 | +9.6 [+2.5, +16.7] |
| R4-R3 | A | zt/k5 | 5 | +2.0 [-2.9, +6.9] |
| R4-R0 | A | zt/k5 | 5 | +14.6 [+5.9, +23.3] |
| R1-R0 | B | zt/k5 | 5 | +3.0 [-1.0, +7.0] |
| R2-R1 | B | zt/k5 | 5 | -1.4 [-2.8, +0.0] |
| R3-R2 | B | zt/k5 | 5 | +5.2 [+3.0, +7.4] |
| R4-R3 | B | zt/k5 | 5 | +0.8 [-1.0, +2.6] |
| R4-R0 | B | zt/k5 | 5 | +7.6 [+3.2, +12.0] |
| R1-R0 | L | zt/k5 | 5 | +3.4 [-7.4, +14.2] |
| R2-R1 | L | zt/k5 | 5 | +0.4 [-6.2, +7.0] |
| R3-R2 | L | zt/k5 | 5 | +11.6 [+1.9, +21.3] |
| R4-R3 | L | zt/k5 | 5 | -0.6 [-2.7, +1.5] |
| R4-R0 | L | zt/k5 | 5 | +14.8 [-0.7, +30.3] |
| R2-R1 | A | zc/k0 | 5 | -2.4 [-7.9, +3.1] |
| R2-R1 | B | zc/k0 | 5 | -3.2 [-7.3, +0.9] |
| R2-R1 | L | zc/k0 | 5 | +0.6 [-7.6, +8.8] |
| R2-R1 | A | zc/k10 | 5 | -2.8 [-6.6, +1.0] |
| R2-R1 | B | zc/k10 | 5 | -1.4 [-6.6, +3.8] |
| R2-R1 | L | zc/k10 | 5 | +3.0 [-6.0, +12.0] |

Reading: under the transductive control `zt` the signs of R1−R0, R3−R2 and R4−R0 match `zc` in all regimes; M3's gain stays positive under `gc` (global-centred labels with source offsets present): A +13.2 [+10.8, +15.6], L +8.2 [−3.8, +20.2] (5 seeds); M2 still does not help even when source offsets are present (A −5.0 [−14.2, +4.2], L +2.0 [−7.5, +11.5]). The anchor counts k = 0 and k = 10 do not change the null for M2.

### 2.9 Audit problems found during this work
1. `IHLM.clone()` hard-coded the base class: after the first update a ladder model silently became a plain `IHLM`, switching the neural analog attention (M3) and neural edit residual (M4) back on. Fixed in `ihlm/model.py` before any scored run; the planted tests were rerun after the fix. 2. The pre-registered shuffled-label gate is not a valid null (section 2.5). 3. The pre-registered `zc` variance shrinkage compresses sources whose SD is far below the global SD (documented in A2; formula unchanged). 4. Shared S3 prefix overwrite (section 2.0). 5. Three boot failures of the spot launch script; the generator `make_ud_ladder.py` now logs to S3 from the first second and is committed. 6. Not run: R1c (label-mined K), the information-privileged PT / PT+analog-correction block, the L9 regime, and the ChemBERTa / atom-LM / PeptideCLM comparators under the ladder protocol.
