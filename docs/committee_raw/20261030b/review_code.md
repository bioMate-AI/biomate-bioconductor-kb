# Independent code and statistics review (read-only), 2026-10-30

Scope: research/guangzhou_all_atom/ (loop_retro, retro_recovery, technique_sprint/fusion*, kb_audit, ihlm, stratification, c2_audit). Paths below are relative to research/guangzhou_all_atom/ unless stated. Project summaries and ledgers were not trusted. Everything marked "recomputed" was computed from the raw per-task JSONs or the CSVs. Scratch scripts are in the session scratchpad; no repository file was edited.

Test status: retro_recovery test_gate, test_harness, test_chem: 23 passed. kb_audit test_perm_null: 7 passed. loop_retro test_l7a, test_aggregate_l7, test_l5, test_loop_par, test_loop_prior were still running when this was written: UNVERIFIED (passing tests would not change any finding below, because the defects are in what the tests do not cover).

---------------------------------------------------------------------------------------------------

## A. Ranked defect list

### CRITICAL

**C1. The L7 aggregate silently discards the chirality-aware GBM and reports the chirality-blind GBM under the name "gbm".**
- File: cyclic_llm/loop_retro/aggregate_l7.py:78-87 (`load_small`, keyed by `(backend, regime)` then `.setdefault(seed, {}).update(r)`); cyclic_llm/loop_retro/collect_l7.sh (passes every `res7*` directory).
- Evidence. results/l7_collect/small/ contains res7f_gbm_aware and res7f_gbm_blind. Both hold `backend="gbm"`, regimes A/B/L, seeds 0-9, with the same arm set. The loader merges them, so the later directory (blind) overwrites the earlier one key by key.
  - Recomputed mean `loop_sub` yield in regime A: aware 86.0, blind 87.4. The committed `gbm|A` is 87.4 (blind). `loop_kphys_sub`: aware 90.7, blind 89.8; committed 89.8.
  - Committed `gbm|A` `stereo.loop_sub.zero_sibling` is exactly 0.0 (n=10). Recomputed from the raw files, aware is 0.181 and blind is 0.0.
  - `inputs.n_files=110` and its sha256 include the 30 discarded aware files, so the fingerprint certifies inputs that were never used.
  - The cluster contrasts differ materially. For regime A, `loop_sub - frozen_sub` E source-rho is 0.134 [0.063, 0.207] (committed, blind) versus 0.236 [0.176, 0.296] (aware, recomputed). `loop_kphys_sub - loop_kshuf_sub` is -0.024 (blind) versus +0.030 [-0.018, 0.089] (aware).
- Endangers: every "GBM" number in the manuscript that comes from l7_aggregate.json. L7k registers "GBM chirality-aware" as the subject of the knowledge contrasts, so the registered configuration is not what the aggregate reports. It also endangers all stereo-resolved claims and the K_phys sign (aware +, blind -).
- Fix: key by `backend_spec` or a required `--alias` that is unique per configuration. Make `load_small` raise on any duplicate `(alias, regime, seed)` that comes from a different directory. Compute `inputs` only over files actually consumed. Regenerate l7_aggregate.json and the manuscript tables with aware and blind as separate rows.

### MAJOR

**M1. Percentile bootstrap over very few clusters is anti-conservative, and the K_phys "harm" and "frozen" conclusions flip under a t interval.**
- Files: cyclic_llm/loop_retro/aggregate_l7.py:55-75 (`cluster_contrast`), cyclic_llm/technique_sprint/fusion/summarize_perm.py (`boot_mean_median`), cyclic_llm/technique_sprint/fusion_b/summarize_b.py (`boot_ci`).
- Evidence (recomputed). Using the committed per-source values, my own bootstrap reproduces the committed percentile intervals to ±0.003 (see section B). Re-fitted as 95% t intervals over the same sources:

| contrast (physchem GBM) | n sources | committed percentile CI | t95 (recomputed) |
|---|---|---|---|
| A, `loop_sub - frozen_sub` | 6 | [0.041, 0.249] | [-0.012, 0.297] |
| B, `loop_kphys_sub - loop_kshuf_sub` (mean -0.0387) | 9 | [-0.090, -0.0012] | [-0.096, +0.019] |
| L, `loop_kphys_sub - loop_kshuf_sub` (mean -0.0351) | 11 | [-0.0686, -0.0071] | [-0.072, +0.002] |

  - The same issue affects T1: `F1_5 - best` at k=25 has 9 labs. The percentile CI is [0.0067, 0.0551]. The t interval is [-0.0002, 0.0615] (t p=0.051), and the sign-flip result is the same. The "(b) supported at k=25" verdict rests on that percentile lower bound.
  - Sources per contrast are 6 (regime A), 9 (B) and 11 (L). They are selected by the E-count rule `min_n=15` per seed, and each source is present in only some seeds.
- Endangers: the statements "K_phys hurts the physchem learner", "loop beats frozen in regime A (physchem)" and the T1 complementarity claim.
- Fix: for any cluster count below about 15, use a t or Hartung-Knapp interval or a sign-flip permutation across clusters. Report cluster counts next to every interval. Do not call a contrast "excluded 0" on percentile bootstrap with fewer than 15 clusters.

**M2. The pre-registered multiplicity and seed-nesting rules are not implemented, and the confirmatory seeds do not exist in the aggregate.**
- File: cyclic_llm/loop_retro/aggregate_l7.py:123-132 and :143-149; cyclic_llm/loop_retro/PREREG_LOOP.md L7j(3) and L7k(3).
- Evidence.
  - No Holm or BH correction anywhere in the code. Line 126 widens to 99% only when the string "kphys" or "kn" occurs in the contrast name. `loop_kshuf_sub - loop_sub` therefore gets 95% while its siblings get 99% (visible in the committed JSON, `ci_level_pct`). The six cluster contrasts × six backend/regime groups are all reported at an unadjusted 95%.
  - L7j(3) says "rung/arm selection on development seeds 0-4, reporting on seeds 5-9". The aggregate pools seeds 0-9.
  - L7k(3) says seeds 0-9 are DEVELOPMENT only, and the confirmatory decision uses seeds 10-29. results/l7_collect/small holds only seeds 0-9 (n_seeds=10 everywhere), so every K_phys inference in the aggregate is development-seed.
- Endangers: any sentence that treats the K_phys contrasts as confirmatory. Also the "H3 supported/not supported" language.
- Fix: implement the Holm/BH families as registered, label all current numbers "development, unadjusted", and do not cite them as confirmatory until seeds 10-29 are run and analysed separately.

**M3. Control "passes" are vacuous or too weak to fail.**
- File: cyclic_llm/loop_retro/aggregate_l7.py:133-136.
- Evidence.
  - `frozen` and `frozen_sub` E-AUROC gain is exactly 0.0 with CI [0, 0] in all 6 groups, because the frozen arm's `_record` uses `state0` and the gain is last-round minus round-0 of the same model (run_l7a.py:185). The control "passes" by construction. It tests nothing.
  - The pass rule is `ci[0] <= 0`, i.e. "not significantly positive". With n=10 seeds, `shuffled_sub` in gbm|L (+ -0.004, CI [-0.085, 0.057]) and in B (CI [-0.085, 0.017]) pass on width alone. There is no equivalence margin.
- Endangers: "pre-registered controls passed".
- Fix: apply the pass rule as an equivalence test (CI inside ±δ, δ stated), and drop `frozen*` from the control list or replace it with a control that can fail, for example the frozen model's E-metric versus the loop's round-0 model on re-split data.

**M4. Validity gate: leave-fold-out controls are label-inverted by compound reuse across folds, and "interval contains 0.5" is used as proof of validity.**
- File: multitarget/integrin_chembl/retro_recovery/validity_gate.py:34-70 (`multi_proxy_scores`, `fp_scores`) and :95-107 (decision).
- Evidence (recomputed from data/items_*.csv.gz and data/folds_v1.csv).
  - Folds are split by family, but compounds are not: 1,057 of 14,492 labelled compounds have pair labels in more than one fold.
  - In items M, 47.2% of decoys are positives on a target in another fold, and 99.6% of positives appear as decoys in another fold. A fingerprint classifier trained on the other folds therefore memorises the inverse label. C3 on M is 0.315 [0.279, 0.352] in the committed gate. With training items whose flat structure occurs in the test fold removed, I get 0.461 [0.423, 0.498]. The interval still excludes 0.5, but narrowly. About 0.15 of the reported deviation is the compound-reuse artefact.
  - For items I (14% of decoys are positives elsewhere), the same flat-disjoint rerun gives 0.579 [0.530, 0.630] (committed 0.584 [0.533, 0.636]). I's failure is robust.
  - The secondary controls use a Bonferroni interval, which reduces power to detect a shortcut. That is the wrong direction for a validity gate. At line ~101 a secondary control with NaN bounds is skipped silently (`v["lo"] == v["lo"]`), while primary controls with too few families are flagged "unverifiable".
  - The gate passes when the interval contains 0.5, which is absence of evidence. `MIN_FAMILIES=8` is the only guard.
- Endangers: the magnitude of "benchmark M is invalid (C3 0.315)". The verdict "I invalid" stands.
- Fix: build gate folds so that no flat key appears in both train and test (group by flat key or compound, not only family). Do not Bonferroni-widen secondary validity checks (or use a one-sided equivalence margin). Treat NaN secondary controls as "unverifiable".

**M5. anchor_test.py leaks held-out-source labels into the calibrated arm.**
- File: cyclic_llm/c2_audit/anchor_test.py:36-45 (`estimate_offsets`), :90-100; cyclic_llm/c2_audit/prep_anchor_data.py:25-33.
- Evidence. Each anchor's `y_others` is the mean PAMPA of the same peptide in all other sources, including the held-out source `h`. The offsets `b_s` of the TRAINING sources are fitted from `y_self - y_others`, and the training labels are shifted by `b_s`. Only anchor lists with source != h are passed in, but their `y_others` values still contain `h` labels. Recomputed from the CSV (57 anchor rows overall): for held-out 2018_Naylor, 21 of the 49 training anchors use `h` labels; 2015_Wang 19/49; 2023_Ghosh 11/52; 2015_Ahlbach 10/51. Cumulatively 61 of 828 (anchor, held-out) pairs. In addition, the same peptide appears raw in both the training source and `h`, so the `raw` variant also sees duplicates.
- Endangers: the "anchor calibration gain" in Part B. The leak helps the `cal` arm only, so any positive gain is inflated.
- Fix: for each held-out source, recompute `y_others` excluding `h`, and drop training rows whose peptide occurs in `h` (or report both).

**M6. Source z-scoring and the hit threshold use all labels, including E and held-out labs.**
- File: cyclic_llm/loop_retro/run_l7a.py:228-229 (`y = K.source_normalize(...)` over all peptides; `thr = quantile(y, 0.9)` over all; `thr_g` per source over all).
- Evidence. In regime L the held-out lab's mean and sd enter the label scale the models are trained and scored on, and the threshold. Within-source Spearman is invariant to this. Pooled E-AUROC/EF5, `hits`, `hits_g` and the yield contrasts are not.
- Endangers: regime-L pooled E-metrics and yield as "deployable" numbers.
- Fix: normalise using training-lab labels only for regime L, and set `thr` from training labs. Alternatively state explicitly that regime L assumes known held-out lab scale (an oracle on lab offset) and say so beside the numbers.

**M7. The "zero-sibling" stereo metric is not zero-sibling for a measurable fraction of groups.**
- File: cyclic_llm/loop_retro/run_l7a.py:34-43 (`make_flat_slice`).
- Evidence (recomputed over 96 task files, 5,292 groups). 355 groups (6.7%) have a same-flat-structure peptide in the initial training set `init`. In regime L, stereoisomers in the training labs are available for any group by construction. `make_flat_slice` selects groups on the variance of the whole group including the revealed sibling. 9 groups have constant target labels and are then dropped inside `stereo_rho` (variable denominator).
- Endangers: interpretation of `stereo_rho` as zero-sibling ranking, specifically the aware-GBM +0.18 and the "blind = 0 exactly" comparison (the latter is by construction).
- Fix: exclude from the group pool every flat key that appears in `init`, E, or (regime L) the training labs, or report the stratified result (groups with and without a training sibling).

**M8. H4b/T1 comparisons mix unmatched item sets, and the T1 decision rules are weak by design.**
- Files: multitarget/integrin_chembl/retro_recovery/11_h4b_run.py (`gain_vs_PT_zero_shot_auc`, the `zs` block); technique_sprint/fusion/summarize_perm.py (`rule_a`, `rule_b`); fusion_b/summarize_b.py (`decide`).
- Evidence.
  - `gain_vs_PT_zero_shot` compares a k>0 family mean over eligible (target, k, seed) cells, computed on the remaining items after removing revealed items and flat siblings, with the k=0 PT family mean over ALL targets and all items. The family sets and item sets differ.
  - T1 criterion (a) is "point estimate ≥ -0.03", not a CI bound. Criterion (b) is "any of 3 k" with the best single component chosen on the same evaluation labs. The 3 k values × 2 fusions are not corrected in T1 (T1b adds a 3-way Bonferroni).
- Endangers: "fusion gain over zero-shot PT" and "non-inferior at every k".
- Fix: restrict the k=0 reference to the same targets and the same remaining items; use a CI lower bound for non-inferiority.

### MINOR

- **m1. K_shuf is not reproducible.** run_l7a.py:331-332 draws one `rr` generator while looping over `set(d["srcs"])`. Set iteration order of strings depends on PYTHONHASHSEED. Recomputed: with PYTHONHASHSEED=1 vs 2 the within-source permuted vector has different hashes (ac9d5c... vs 02eb91...). The "no-information" control is a different random vector on each process start. Fix: iterate `sorted(set(...))`.
- **m2. Non-inferiority block** (aggregate_l7.py:166-174): the ratio is a mean of per-seed ratios and drops pairs with q=0 (post hoc selection of pairs); the absolute-loss margin required by L7j(4) is not computed. Currently moot, since n=4 pairs and it is labelled inconclusive.
- **m3. Peptides measured in several sources are collapsed** (run_loop.py:30-41): the label is averaged over labs and the source is the first row's source. 52 IDs repeat; 21 span sources. Small, but it contradicts "within-source z" for those peptides.
- **m4. Legacy L1/L2 code reports spreads as CIs** (run_loop.py:57, `ci()` takes `v[int(.025*n)]` of per-seed values; `CLAIM_loop_beats_random_both_regimes` takes `any` over two policies). PREREG L7k already acknowledges the mislabel; confirm the manuscript text uses `ci_mean`.
- **m5. Vacuous or loose assertions.** ihlm/test_ihlm.py:218 `assert s_hi == s_lo or True` cannot fail. stratification/test_stats.py:24 `assert sig.sum() <= 5` tolerates up to 5 false positives. `bh_fdr` defaults to q=0.10, not 0.05.
- **m6. c2_audit/aggregate_A.py** uses one module-level `rng = default_rng(0)` for all bootstraps (results depend on call order and arms are not resampled identically), and parses per-target values from rounded stdout text with a regex.
- **m7. Name collision.** "K_phys" in the L7 runner is a fixed textbook linear combination (-tpsa -hbd +logp, run_l7a.py:239). "K_phys" in kb_audit is a rule-mined weighted sum of the same descriptors from other labs. Results for one are being discussed as the other; state which one each claim refers to.
- **m8. Pair-rule variance (peptide_sar_kb.py `mine_pair_rule`)**: `var/len(g)` treats matched pairs as independent, but pairs share peptides. DL pooling with z=2.576 may over-call "rule" status. UNVERIFIED how often this changes status.
- **m9. IH-LM priors** `EDIT_PRIORS` (symbolic.py:15, nme_add +0.25) are cited to the stratification analysis of B4, which was computed on the full CycPeptMPDB. If those effect sizes come from data that include the evaluation labs, the prior leaks. UNVERIFIED; check the provenance in docs/20261029_CYCLIC_PEPTIDE_STRATIFICATION_ANALYSIS.md.
- **m10. Working tree** has uncommitted edits to kb_audit/lolo_permutation_null.py, perm_null.py and test_perm_null.py (NaN guards). The committed lolo_permutation_null.json may predate them. Recorded results are unchanged (my reimplementation below matches), but commit before citing.
- **m11. Within-lab permutation null** (lolo_permutation_null.py, N1) assumes peptides within a lab are exchangeable. Series and scaffold dependence is only partially handled by the flat-structure group permutation (lolo_group_permutation_null.json: 10 of 21 labs p<0.05 versus 11 for N1; 2016_Furukawa p 0.009 -> 0.155). Scaffold-level dependence remains.

---------------------------------------------------------------------------------------------------

## B. Independent reimplementations (compared with committed outputs)

1. **Source-cluster bootstrap on the L7 aggregate inputs.** I rebuilt `y` and sources from the CSV (own source z-score, 6,960 peptides, 41 sources), recomputed per-(source, seed) Spearman of `E_scores_final` with scipy, applied the min_n=15 / min_seeds=3 rules, and bootstrapped sources with a different RNG (20,000 draws). Sample of results (mine versus committed):
   - gbm blind A `loop_sub - shuffled_sub`: 0.278 [0.189, 0.368] vs 0.278 [0.1886, 0.3669]
   - gbm blind A `kphys - kshuf`: -0.0244 [-0.0531, 0.0006] vs [-0.0531, 0.0003]
   - physchem B `loop_sub - frozen_sub`: 0.2916 [0.132, 0.466] vs [0.1289, 0.4653]
   - physchem L `kphys - kshuf`: -0.0351 [-0.0687, -0.0071] vs [-0.0686, -0.0071]
   - 15 of 15 contrasts matched in point estimate and n_sources, and in interval to ±0.004. The calculation is correct. The problems are the interval type (M1) and which configuration feeds it (C1). The same script run on the aware directory gives different numbers (C1).
2. **Family fold assignment.** I reimplemented the LPT bin-packing (weight = distinct compounds with a labelled pair per family; ties to lowest fold). The assignment equals data/folds_v1.csv exactly (317 families; loads 4524/2941/2941/2941/2940). Every target maps to one family and every family to one fold, so families are disjoint across folds. Compounds are not (M4).
3. **Permutation null for K_phys (kb_audit).** I re-mined the rules per held-out lab with the repository's `fit`, then recomputed the per-lab Spearman and a within-lab permutation p (20,000 permutations, my own loop with np.corrcoef). All 21 labs: observed rho identical to 4 decimals; p within sampling noise of the committed values (for example Furukawa 2016 0.0093 vs 0.0089, Naylor 0.793 vs 0.791, Kelly/Townsend/Wang ≈ 5e-5). The committed 11/21 labs with p<0.05 is correct for that null.
4. **Within-flat-group ranking structure.** From the stored `Ef_groups`, `Ef_sib`, `init`, `E` and the CSV flat keys: every group has exactly one sibling and ≥2 targets; all members share the flat key; no flat key repeats across groups within a task; 0 groups have constant whole-group labels. Scores were not stored, so rho itself could not be recomputed (UNVERIFIED); the structure checks yielded M7.
5. **T1 headline numbers.** Recomputed from technique_sprint/fusion/results/perm_cells.csv: F1_5 − best = +0.0407 (k=5, 17 labs), +0.0412 (k=10, 15), +0.0306 (k=25, 9), matching perm_summary.json; the intervals differ by type, see M1.
6. **Gate re-run with flat-disjoint training** (M4) is my own LogisticRegression pipeline using the repository's `fp_table` and `_family_ci`.

---------------------------------------------------------------------------------------------------

## C. Verified correct (no defect found)

- `cluster_contrast` arithmetic, source sorting (hash-order fix), constant-score = rho 0 rule, seed-only statistic recomputation, and the NaN guards behave as documented; the bootstrap seed derivation is deterministic (reproduced twice).
- Paired design: every arm gets `default_rng(seed)`; GBM fits use `seed*1000+r`; the `_sub` candidate subsets come from one shared `subset()`; E, Ef, Es and init are shared across arms and asserted pairwise disjoint (run_l7a.py:330). Regime L training pool and held-out set are asserted disjoint (:326).
- Frozen-arm SAR update uses only the labels the model owns (`revealed`/`ylab` lengths asserted). The `picked_final` fix handles older files correctly in the aggregate.
- Shuffled arm draws a global label vector from the pool (no item-level association); the tests for the planted world and for K_phys fusion identities are meaningful (they check an exact identity and a planted correlation, not just "runs").
- `ef5_auroc`, `tie_aware_auc`, `tie_aware_ef` (ties straddling the cut): spot-checked against rank formulas; the validity-gate unit tests (planted proxy fails, balanced passes, too few families = unverifiable) can fail and exercise the gate.
- H4b: PT per fold removes training compounds whose flat structure equals any held-out-fold compound (11_h4b_run.py PT block); reveal sets are frozen with a deterministic crc32-based RNG; remaining items exclude revealed compounds and their flat siblings; reveal sets are drawn before any scoring.
- PT standardisation in T1 uses only the candidate set; analog estimates use only revealed items; nested-n0 re-mines rules excluding both the outer and inner lab.
- K_phys textbook (L7) uses no label-mined parameter and source standardisation uses descriptors only.

---------------------------------------------------------------------------------------------------

## D. Not assessed or UNVERIFIED

- Rho for the within-flat-group metric (scores not stored), the large-LLM runner (run_l7a_llm.py: only paired-subset identity inspected), the v4 and atom-LM backends, ihlm/model.py training leakage, stratification annotation and MMP code (only stats.py read), c2_audit Part A numbers beyond code reading.
- Whether `EDIT_PRIORS` provenance leaks (m9) and whether m8 changes any rule status.
- Pending test runs in loop_retro (see top).

## E. Minimum actions before any number is cited

1. Fix C1 and regenerate l7_aggregate.json with aware and blind as separate rows.
2. Replace percentile cluster intervals with t or sign-flip intervals when clusters are fewer than about 15 (M1); re-state the K_phys-harm and T1-k=25 claims accordingly.
3. Label all seed 0-9 K_phys results "development, unadjusted"; run seeds 10-29 as registered (M2).
4. Rebuild validity-gate folds so no flat key crosses train and test; re-run the gate for I and M (M4).
5. Fix the anchor_test leak (M5) and the oracle normalisation in regime L (M6) or label them.
