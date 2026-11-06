<!-- model=anthropic/claude-sonnet-4.6 finish=stop tokens_in=39081 out=7238 reasoning=28 cost=0.225813 -->
# External reviewer SONNET (anthropic/claude-sonnet-4.6)

## ROLE 1. MANUSCRIPT REFEREE

**What the paper can claim.** A rigorously audited evaluation instrument showing that no standard cyclic-peptide binder benchmark passes a no-target validity gate; that GBM loop selection beats random in-distribution but the gain is transductively inflated and concentrated in one laboratory; that in regime L a feedback effect on held-out ranking is learner-dependent and inconsistent across contrasts; that few-label gain reduces to analog lookup; and that anchor calibration, fusion techniques T1/T1b, and a physicochemical rule are all null or failed as registered.

**What it cannot claim.** Any statement about language models in the loop. Any statement about "closed-loop learning" that generalises beyond one fixed 6,960-peptide library. Any claim that the loop improves a model's ability to predict new laboratories — the cluster intervals in regime L either include zero or are inconsistent across learners.

**Overclaims and internal inconsistencies.**

1. *Abstract*, "Aim B: build and audit a retrospective evaluation instrument… and measure baseline loop behaviour with it." The loop is on permeability; the evaluation instrument is for binding. These are presented as one coherent Aim B but address entirely different tasks with different datasets. A referee will ask whether they belong in one paper.

2. *Abstract results (i)*: "+186.3 hits" is flagged as "likely overstated" in the same paragraph. Reporting a transductively inflated headline number and then immediately disclaiming it is not acceptable practice. The causal-normalisation arm is running; until it finishes, no headline hit number for regime A should appear in an abstract. Delete or replace with the single-seed indicative range.

3. *Section 5.0a, P3*: "loop − frozen excludes 0 for the chirality-aware (+0.075, 0.037 to 0.115)" is a cluster-boot interval over 11 sources. "loop − shuffled-label excludes 0 only for the physicochemical learner" — yet the abstract's conclusion reads "a small, learner-dependent feedback effect on held-out ranking in regime L." This phrasing overstates: the effect is present for one learner on one contrast and absent or sign-reversed on others. A referee will require "inconclusive" rather than "small."

4. *Section 5.0a, P1*: The boot-mean CI (181.1–191.5) is labelled "post hoc" in Section 4.9 but appears without a post-hoc label in P1. Inconsistency.

5. *Section 5.2*: "sequential selection adds no held-out ranking gain beyond the same labels given at once that these data can detect" — but the minimal detectable difference is ~0.04. The paper does not establish that the true difference is zero; it establishes only that it cannot detect it. Correct to "differences below ~0.04 are not excluded."

6. *Physicochemical learner anomaly*: "random feedback beats the loop on held-out ranking in the physicochemical learner (unexplained; diagnostics so far exclude artefact)" — this unexplained result sits in the primary claims table (P3, P4) with no resolution. A referee will demand either an explanation or that the physicochemical arm be moved entirely to appendix exploratory material.

7. *Section 8*: Literature statements marked [LIT-UNVERIFIED] and [LIT-SNIPPET] appear in the prior-art section. Submission is not possible with unverified citations.

8. *K_phys discussion*: 54 dependent contrasts, no multiplicity correction, 15 excluded at 99% — the paper calls these "exploratory leads" but allows them to inform the discussion framing. The discussion (Section 6) mentions "held-out AUROC advantage over a shuffled channel in the scaffold-shifted regime for 2 of 3 GBM backends" as though directional. With no multiplicity correction and 54 correlated tests, this is not reportable as directional evidence.

9. *Regime C*: described as "identical-structure sensitivity, not a near-duplicate-free regime (26.9% of the pool still has a nearest initial peptide at Tanimoto ≥ 0.9)" — if regime C is not near-duplicate-free, all results under it are series interpolation and should not be reported alongside regime B as if they address generalisation.

10. *C2 rerun*: "original logged numbers withdrawn" is appropriate. But the rerun also failed its reproducibility tolerance. The family-disjoint extension is the only C2 claim; the text should make clear that the rerun numbers are themselves provisional (3 seeds, unknown whether within the new tolerance).

**Missing analyses a referee would demand.**
- Paired test for zero-shot model vs fingerprint control on analysis I (not just overlapping intervals; the paper explicitly says "no paired family-cluster test was computed" — this must be computed before submission).
- Power calculation for the regime-L cluster bootstrap with 6–11 sources; the paper approximates MDE at ~0.13–0.19 but never states a power for the observed contrasts. An underpowered null finding is not a finding.
- Multiplicity correction for the 54 K_phys contrasts (Holm or Benjamini-Hochberg); or these must be relegated entirely to appendix with no directional claim.
- A formal test of whether regime-L yield distributions are stationary across seeds, given that the number of held-out laboratories varies from 6 to 18 across seeds (this is explicitly flagged as irregular).

**Interval/multiplicity issues.**
- Spread intervals are used for the registered judgements (C1, C2) but boot-mean intervals are then reported post hoc and partially used in the abstract. The paper must choose one and apply it consistently.
- The 99% vs 95% CI level switch for K_phys contrasts versus other contrasts (Section 5.2 first paragraph) is disclosed but creates asymmetric evidence standards within the same table.
- Cluster-boot CIs with 6 sources (regime A) have wide bootstrap variability themselves; the reported precision (e.g. 0.203 to 0.369) likely overstates precision given n=6.

**Publishability framing.** As a methods/audit paper documenting null results and instrument construction, this is publishable in principle at venues such as *JCIM*, *Journal of Cheminformatics*, or *PLoS Computational Biology*. The central hypothesis comparison (IH-LM vs pretrained models) is absent, which means the paper cannot reach a high-impact venue for its primary claim. The appropriate framing is an audit and baseline paper, clearly labelled as such, pending Aim A.

**Ranked required revisions.**
1. Remove headline regime-A hit number from abstract until causal arm completes; replace with the indicative range.
2. Compute the paired family-cluster test for zero-shot model vs fingerprint control.
3. Apply multiplicity correction to K_phys contrasts or move all 54 to appendix with no directional claim in the main text or discussion.
4. Resolve or remove the physicochemical learner anomaly from the primary claims table.
5. Verify all [LIT-UNVERIFIED] and [LIT-SNIPPET] citations before submission.
6. Relabel post-hoc boot-mean intervals consistently throughout.
7. Report formal power for regime-L cluster contrasts with n=6–11 sources.
8. Separate the binding benchmark instrument and the permeability loop into distinct contribution statements.

---

## ROLE 2. CODE / STATISTICS REVIEWER

### `aggregate_l7.py : learner_key` (line 80)

The fix for the key-collision bug (chirality-blind overwriting chirality-aware) is implemented by directory-name heuristics. **Concrete defect:** the function uses `"blind" in name` as a string test on `os.path.basename(os.path.normpath(dirpath)).lower()`. If a future run directory contains "blind" in its path for any reason unrelated to learner type (e.g., a tag like "non_blind_test"), the function silently misclassifies the learner. The fix is fragile relative to a structured metadata field. This does not change any currently reported number (the fix was applied before the frozen aggregate) but creates a silent failure mode for future runs. **Risk: interpretation, not current numbers.** Recommendation: require the `learner` field in all new runs and raise an error if absent.

### `aggregate_l7.py : cluster_contrast` (line 56)

1. **Seed resampling in `ci_seed_only` (lines ~75–82):** the bootstrap resamples seeds (`seeds_all`) with replacement but then weights contributions by `w[k]` (the count of how many times seed `k` was drawn). For sources present in only some seeds, the denominator `den = sum(w[k] for k in d[s])` can be small or zero if the sampled seeds don't include any seed where source `s` was held out. The `if den > 0` guard drops the source entirely from that bootstrap replicate. **This is a resampling unit error:** the correct procedure when sources have unequal coverage across seeds is to resample sources as the primary unit (which `ci_cluster` does correctly) or to use a stratified bootstrap. The `ci_seed_only` interval is therefore anticonservative for sources held out in few seeds, because dropping a source from some replicates inflates the effective degrees of freedom. **This changes the `ci_seed_only` interval interpretation** but the paper correctly states to cite `ci_cluster`; if `ci_seed_only` is not cited anywhere in the main text, the practical impact is limited. **[UNVERIFIED whether ci_seed_only appears in any reported interval].**

2. **`_seed` function called with `(per_src, lo, hi)`:** this derives a fixed RNG seed from the data values `per_src`. If two different contrasts happen to produce the same `per_src` array (unlikely but possible for degenerate cases), they share a seed. Minor; no reported number affected.

3. **`sorted(set(tab_a) & set(tab_b))`:** the use of `sorted()` on string source names is noted as necessary to avoid hash-randomisation ordering. Correct.

4. **NaN guard:** dropping non-finite per-seed values before computing per-source means is correct practice. No defect.

5. **Point estimate = mean of per-source means (equal-weight over sources, not over seeds).** This is an unusual estimand when sources have very different numbers of seeds; a source held out in only 3 seeds (the minimum) has equal weight to one held out in 10. The paper discloses this but a referee will object that the estimand is dominated by sources with sparse coverage.

### `validity_gate.py : _family_ci` (line 26)

**Fixed seed = 5.** Every call to `_family_ci` uses `seed=5`. This means all bootstrap CIs for all controls and all benchmarks share the same RNG sequence. This is not statistically incorrect (the bootstrap is valid for any fixed seed) but it means results are not reproducible under a different seed. For 26 families and 10,000 bootstrap samples the Monte Carlo error is small (~±0.001 on a percentile). No reported number is changed. Recommend using a content-derived seed or documented fixed seed, not an arbitrary constant.

**No defect in the AUROC computation path** (delegates to `H.tie_aware_auc`); tie handling is correct if `H.tie_aware_auc` uses the standard midrank convention. [UNVERIFIED: `H.tie_aware_auc` source not in packet.]

### `validity_gate.py : control_auc` (line 36)

Straightforward: maps scores onto items, drops NaN scores, computes per-target AUROC, calls `_family_ci`. No defect found.

### `validity_gate.py : assign_status` (line 88)

**Defect (interpretation, not number):** the equivalence test uses `lo90`/`hi90` (the 90% interval) for the TOST check (`0.5 - DELTA_PRIMARY` to `0.5 + DELTA_PRIMARY`). The note says "alpha = 0.05 per side." A 90% central interval is appropriate for TOST at α=0.05 per side. This is correct. No defect.

**`v["lo"] > 0.5 or v["hi"] < 0.5`** correctly identifies bias (CI excludes chance from above or below). Correct.

**`v["lo"] == v["hi"]`** for degenerate secondary controls: correct guard.

### `validity_gate.py : run_gate` (line 108)

**Concrete defect in secondary-level Bonferroni:** `adj = 1 - 0.05 / n_sec` is used as the `level` argument to `control_auc`, which passes it to `_family_ci` as the bootstrap CI level. If `n_sec` = 1 this gives level = 0.95 (correct); if n_sec is larger (e.g., 5) this gives level = 0.99. The `_family_ci` function then constructs `a = (1 - level) / 2 * 100`, so for level = 0.99 we get the 0.5th and 99.5th percentiles. This is the Bonferroni-corrected interval and is intentional. **However:** the `assign_status` function checks secondaries using only `v["lo"] > 0.5 or v["hi"] < 0.5` — it uses the Bonferroni-adjusted `lo`/`hi` to flag bias. This is conservative (correct direction: harder to flag a secondary as biased). Reported secondary flags are therefore conservative. No number is changed; the interpretation is acceptable.

### `run_l7a.py` lines 160–176

1. **`s` variable at line `if has_std and base not in (...):`** — `s` is initialised as `None` at the top of the loop (inferred from `if s is not None`) and is assigned only in the `else` branch of the frozen/non-frozen split. In the `frozen` branch, `s` is never assigned, so the `pick_scores` append on the non-frozen path correctly skips. Verify that `s` from the previous round is not inadvertently reused in the frozen branch — if the variable is not reset to `None` at the top of each round, the frozen arm would log the *previous round's* scores. **This is a potential silent defect.** [UNVERIFIED: the full round loop is not shown.]

2. **`K.zs(ch[U])`:** the knowledge channel is z-scored over the unlabelled pool `U` at each selection step. This means the z-score statistics are computed on the changing pool, introducing a mild non-stationarity across rounds. This is a minor methodological choice, not a defect.

3. **`kind="stable"`** used throughout `argsort` calls: correct for reproducibility.

### `acq.py : setup_L` (line 61)

**Concrete design risk:** `random.Random(500000 + seed).shuffle(cand)` uses Python's `random.Random` (not numpy), and the shuffle is of a `sorted(...)` list. The result is a fixed permutation per seed. However, `giant` laboratories (the two largest) are always excluded from `held`. This means the held-out set never contains Townsend or Kelly, which hold ~65% of peptides and most hits. The paper discloses this, but the consequence is that regime L is evaluating generalisation to small, heterogeneous laboratories only. Any claim about "generalisation" from regime L is conditional on this selection and cannot be generalised to the dominant laboratories.

### `acq.py : causal_z` (line 78)

No defect. The shrinkage formula is correct: global mean/variance used as prior, per-source update with weight `k=5`. Unrevealed labels are not accessed.

### `acq.py : run_arm` (line 135)

1. **`assert ymode in ("trans", "causal") and (ymode == "trans" or not override)`**: this assertion prevents causal mode with label overrides. Correct design constraint.

2. **`nn_greedy` arm:** computes similarity `S = inter / np.maximum(union, 1.0)` — this is the Tanimoto coefficient from binary fingerprints. The weighted sum `(w * lab).sum(1) / np.maximum(w.sum(1), 1e-9)` is a distance-weighted kNN prediction. Correct.

3. **`prov` arm:** `score = (1 - w) * zs(mu + C_UCB * sd) + w * zs(D["Kphys"][U])` — this combines UCB-adjusted model scores with physicochemical knowledge. With `lam=0` (frozen config), diversity is disabled. With `cap_src=50`, the source cap is effectively the library size (50 per source is loose). The frozen config gives `prov@l0.0_s50_finf`, which is greedy model + K_phys, no diversity. The paper correctly states "prov − div is NOT a diversity ablation."

### `make_ud.py` diff

**Risk flag (design/launch, not results):** the change from `$(nproc)` to `$(nproc --all)` correctly fixes the OMP_NUM_THREADS=1 issue. However, `nproc --all` returns the total hardware threads regardless of container or cgroup limits. On AWS, if the instance is a subset of a physical host (unlikely for m6i but possible for smaller types), `nproc --all` may overcount. For a spot instance running a CPU-bound grid, this is unlikely to cause incorrect results but could cause memory pressure. **Low risk; note only.**

**Multi-stage body assembly:** `parts = st.split(",")` with assertion that all stages write to the same S3 prefix. If the assertion fails at launch time, the script exits before generating the user-data file. This is a safe fail. No risk to results.

---

## ROLE 3. DATA / EVALUATION REVIEWER

### Leakage routes

**1. Corpus leakage into pretrained comparators.** The paper acknowledges that external pretrained models may have seen CycPeptMPDB compounds in pretraining. Per-model overlap checks and contamination-controlled subsets are promised but not yet run for the central comparison (which has not been run). For the GBM baselines reported here, this is not relevant. For ChemBERTa exploratory results (not folded into aggregate), leakage is unquantified. [UNVERIFIED: whether the contamination-controlled subset is defined and frozen.]

**2. Fold-level compound leakage in analysis I.** 11.6% of rows (1,093 of 9,432) have the same compound in another fold under folds_v1. The paper correctly flags this and provides the compound-disjoint I_CD list. The key finding: I_CD still fails the gate (C3 = 0.621, 0.555–0.685), meaning compound overlap is not the cause of the bias. However, 29.6% of positives have a Tanimoto ≥ 0.70 neighbor in another fold — analog leakage remains even after exact-duplicate removal. This is not adequately addressed; the paper should report whether the few-label results change materially on I_CD.

**3. Stereoisomer leakage.** The registered sibling removal removed 0 items from analysis I (stated: "the stereoisomer-sibling stratum is empty by construction"). This is suspicious — with 16,195 compounds in a cyclic peptide binding benchmark, zero stereo-sibling pairs across folds is implausible unless the deduplication was done on flat structure, which then creates a different problem (multiple stereoforms collapsed). [UNVERIFIED: the protocol for collapsing stereoforms in analysis I.]

**4. Laboratory leakage in regime L.** The source-assignment defect (178 peptides with wrong laboratory) was fixed, and the leave-laboratories-out Spearman fell from ~0.30 to ~0.22. The fix is appropriate and the drop is the right direction. However, the pre-fix numbers appeared in earlier reported results (e.g., the original logged C2 numbers, now withdrawn). Any analysis that used the pre-fix annotation for training set construction (not just evaluation) may be subtly contaminated. The paper should explicitly state whether any currently-reported number (not just C2) was derived using the pre-fix annotation.

**5. Series and analogue leakage in regime A.** The paper correctly characterises regime A as series interpolation: 346 of 500 picks come from one laboratory, and 26.9% of regime C's pool has Tanimoto ≥ 0.90 to an initial peptide. This means regime A results describe exploitation of a known-laboratory's series and cannot be generalised.

**6. Transductive convention for hit thresholding.** The hit threshold uses "every label of the source" (transductive) rather than labels known at selection time. The indicative single-seed check shows this inflates hits from 151 (causal) to 251 (transductive). The causal-normalisation arm is running but not complete. **This means the primary regime-A claim (P1) in the abstract is currently based on a leaky threshold.** This is the most consequential leakage in the reported results.

### Validity gates and the control-adjusted rule

The no-target gate is correctly implemented and the retrospective application is disclosed. The key issue: the censoring indicator (AUROC 0.794 when inverted, 0.206 direct) is stronger than any compound-based control but is not applied as a primary gate control. It is listed as a secondary flag (C4). **This means the gate as implemented does not protect against the dominant confound in analysis I.** Any arm on analysis I that achieves AUROC > 0.794 inverted might be exploiting censoring, not binding prediction. The paper should state that C4 should have been a primary gate control and that no arm on analysis I can be interpreted without the censoring distribution.

**The control-adjusted rule** ("an arm is SUPPORTED only if the lower 95% bound of its difference from the strongest baseline exceeds zero") is sound. No arm was supported on analysis I. Correct conclusion.

### Family-disjoint fold quality

Folds are Pfam-Jaccard family folds, not sequence-identity families. 29 of 775 accessions occur in more than one family; 6 of 46 targets in analysis I have a same-protein target in another fold; αvβ6 and β6 are counted separately with 70 shared compounds. The paper discloses all of this. However, the phrase "Pfam-family-disjoint" in the abstract and title-level descriptions is misleading: the folds are family-disjoint by Pfam annotation but not by protein sequence or by compound. A submission should say "Pfam-Jaccard-family-disjoint" or, more accurately, "approximately family-disjoint with known violations."

### Regime definitions and leave-laboratories-out set sizes

Regime L draws 6 to 18 laboratories across seeds (6, 9 and 11 sources in regimes A, B and L — the paper appears to mean A has 6 eligible sources, B has 9, L has 11, but the L figure is the mean and the actual range is 6–18). The cluster-boot CI for L uses `n_sources` = 11 (sources with ≥15 E peptides in ≥3 seeds). **An irregular held-out set is a serious problem:** different seeds contribute different laboratories to the aggregate, making the cluster estimand a mixture. The registered L9 sensitivity (cap of 9) has not run. All regime-L cluster CIs are conditional on the irregular design and should not be reported as primary results until L9 confirms them.

### Power

With 11 sources in regime L, the cluster bootstrap has very low power. The paper estimates MDE ~0.13–0.19. For the observed contrast of +0.034 (aware loop − shuffled-label in regime L), power is far below 0.80. The null result here is not informative: the study is underpowered to detect plausible true effects. The paper should give explicit power calculations for each cluster contrast, not just the MDE approximation.

### Multiple comparisons

54 K_phys contrasts with no multiplicity correction. 15 of 54 exclude zero at 99% percentile bootstrap. With 54 correlated tests at a nominal 99% level, the expected number of false positives under the null depends on correlation structure, but even with perfect correlation (one effective test) we would expect 0 false positives — so 15 exclusions is genuinely more than chance. However, the contrasts are not independent (they share seeds, regimes, and learners), and the paper provides no familywise error rate analysis. The 15 exclusions cannot support directional claims.

### Selection of arms

The physicochemical rule (K_z) was "added after the first loop result" (Section 7, limitation 8; also P2 claims table). This is a post-hoc arm. The paper correctly labels this but the Discussion framing ("most of the margin was reproduced by simple analog or physicochemical lookup") includes this post-hoc arm as evidence. This is circular: a rule defined to match the loop will match the loop.

### CycPeptMPDB-style public data

The public data can support the reported claims about GBM learning behaviour, leave-laboratory-out skill, matched molecular pair effects, and the audit instrument. It cannot support claims about language models (not run), about prospective generation, or about binding (analysis I fails the gate). The concentration of the database in two laboratories (Townsend + Kelly = ~65%) means the regime-A results are a within-series learning demonstration, not a general closed-loop result.

---

## CLAIMS I WOULD DELETE

From the claims table (Packet 2, Section 8) and the primary claims (Section 5.0a):

| Claim | Reason |
|---|---|
| P1 headline: "+186.3 hits per 500 selections" | Transductively inflated; causal arm incomplete; should not appear in abstract or claims table as a result |
| "loop − shuffled-label excludes 0 only for the physicochemical learner (+0.155)" as a positive finding | Physicochemical learner shows *inverted* random-feedback ranking (unexplained); the contrast is uninterpretable without resolving the anomaly |
| "K_phys holds a heterogeneous but real zero-fit association" as a main-text claim supporting the loop | This is an offline correlation only; the 54-contrast loop analysis has no multiplicity correction and the cluster-level analysis is uniformly null |
| "Cheap-tier API language models are far behind a GBM" | 4 seeds, exploratory, no interval reported; this should be a footnote, not a ranked finding |
| "Few-label gain is analog lookup" as a finding of analysis I | Analysis I fails the censoring control (C4 inverted AUROC 0.794); the absolute AUROCs are not interpretable; the claim is valid only as a relative comparison between methods on a gate-failing benchmark, which is weaker than stated |
| K_phys "exploratory leads (held-out AUROC advantage over a shuffled channel in the scaffold-shifted regime for 2 of 3 GBM backends)" | 54 dependent contrasts, no correction, not a directional claim |
| Regime C results as supporting regime-B generalisation | Regime C is not near-duplicate-free; it is another interpolation regime |

**Missing control:** the regime-A yield claim (P1) has no control for the two-laboratory concentration effect. Specifically, there is no "random within one laboratory vs random across all laboratories" control that would quantify how much of the +186.3 yield gain is simply from concentrating picks in the high-hit-rate Townsend laboratory versus learning a useful model.

---

## THE SINGLE MOST DAMAGING FLAW

**The transductive hit threshold in the primary regime-A claim (P1).**

The hit threshold is computed from the full within-source label distribution (all 6,960 labels), not from the labels revealed at selection time. This means the model's picks are evaluated against a threshold it could not have known. The single-seed indicative check shows this inflates hits by 40%: 251 (transductive) vs 151 (causal-from-labelled). The causal-normalisation arm is running but has not produced a result. If the final causal result is ~151 (≈+104 over random's 47), the regime-A claim shrinks substantially; if it is close to random (as the raw-pooled check of 64 vs 47 suggests), the primary regime-A result disappears. The paper presents the 186.3 figure as its headline result with a disclaimer, but the abstract and claims table still carry it prominently.

**Why it is the most damaging:** this is the lead headline result of the paper. If the causal arm shows the advantage is ~0 or small, the entire "GBM loop beats random" narrative collapses for the primary regime, leaving only regime B (which failed the registered test) and regime L (which shows an irregular, learner-dependent, underpowered cluster effect). The paper would then have no positive result for the loop, only auditing methodology.

**Cheapest test to confirm or refute within a day:** the L7q run (mentioned in Packet 0b as running) is the 10-seed causal arm. The team should freeze whichever seeds have completed (≥8 required by the paper's own rule) and compute the mean causal hit count with a 95% boot-mean CI. If the CI for causal hits overlaps the random baseline, the P1 claim must be deleted. This requires one Python aggregation call on whatever files have been synced to S3, which the paper's own infrastructure (45-second S3 sync) would make available within minutes of the spot instance completing.
