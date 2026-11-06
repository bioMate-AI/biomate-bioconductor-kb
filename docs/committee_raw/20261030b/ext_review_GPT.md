<!-- model=openai/gpt-5.5 finish=stop tokens_in=30230 out=4919 reasoning=0 cost=0.29872 -->
# External reviewer GPT (openai/gpt-5.5)

## ROLE 1. MANUSCRIPT REFEREE

**Overall recommendation:** this is not publishable as a paper about an in-house cyclic-peptide language model versus larger pretrained peptide/chemistry models. That central comparison has not been run. It may be publishable, after substantial reframing and pruning, as an evaluation/audit paper: “retrospective closed-loop benchmarks for cyclic-peptide permeability/binding are highly confounded; simple learners beat random mainly by lookup/physicochemical shortcuts; no clean binding benchmark was obtained from this public collection.” That framing is honest and potentially valuable. The current draft still tries to carry too many uncompleted aims, technique sprints, and speculative model plans.

**What the paper can claim from the evidence.**

1. A simple GBM-style loop can select more high-permeability compounds than random from the fixed CycPeptMPDB-like library in in-distribution/interpolation regimes.
2. The preregistered L5 claim “loop beats random in both primary regimes” was not met because the scaffold-shifted spread includes 0.
3. Under scaffold shift, a label-free physicochemical rule ties the loop on the primary hit definition.
4. In leave-laboratories-out settings, yield gains can be large, but held-out ranking improvement on new laboratories is not demonstrated for the plain GBM when laboratories/sources are the resampling unit.
5. Few-label binding gains on analysis I are dominated by nearest-neighbour/analog lookup; transferable gain to remote chemotypes is not demonstrated.
6. The validity-gate audit is a real result: the tested binding benchmark constructions fail no-target/typicality/fingerprint controls.
7. K_phys has an offline within-source association with permeability in held-out laboratories, but loop-level gains are exploratory and multiplicity-exposed.
8. Fusion and anchor-offset techniques did not work as registered, or were unsupported by available public anchor coverage.

**What the paper cannot claim.**

1. It cannot claim IH-LM matches or exceeds larger pretrained models. No IH-LM loop result exists.
2. It cannot claim closed-loop learning improves model generalisation to new laboratories. The best-supported statement is selection yield, not demonstrated transferable prediction.
3. It cannot claim benchmark validity for binding. The benchmark is explicitly invalid under the authors’ own gate; only control-adjusted/audit conclusions are defensible.
4. It cannot claim discovery of transferable cyclic-peptide rules beyond analog/physicochemical lookup.
5. It cannot claim prospective design ability, molecule generation improvement, or wet-lab relevance beyond retrospective replay on already measured public compounds.
6. It should not claim that matched-decoy cyclic-peptide benchmarks generally cannot work; only the authors’ constructions on this collection failed.

**Overclaims and internal inconsistencies.**

- “Two aims, one paper” is rhetorically dangerous. Aim A is not merely incomplete; it is the central model-comparison story and has no data. Split the paper or make Aim A a preregistered future study, not an aim of this paper.
- The abstract is unusually candid, but overloaded. It reports many nulls and technique tests whose connection to the main evaluation-instrument claim is weak.
- Numbering and organization are messy: Results items are ordered (i), (ii), (iii), (iv), (v), (vi), (viii), (vii); Limitations have 8a/8b/8c/8e/8d/8. This signals uncontrolled accretion.
- “No threshold, feature set, model or contrast is chosen after seeing a result” conflicts with several disclosed amendments, retrospective gates, post hoc boot-mean additions, replacement of M2/M3, and T1/T1b modifications. The transparent record helps, but the sentence is too broad. Say instead that deviations are dated and labelled exploratory/post hoc.
- Regime L is described as leave-laboratories-out, but some major laboratories are “never held out,” and held-out set sizes vary from 6 to 18 laboratories with 3 seeds holding out all eligible labs. That is not a clean leave-one-lab or fixed leave-lab-out design; it is a stochastic held-out-source regime with exclusions.
- The draft alternates between “new laboratories” language and careful disclaimers that seed intervals do not support new-laboratory inference. The source-cluster intervals must be the only basis for such language.
- The binding section says no analysis passes validity gates but still discusses zero-shot/few-label arms at length. This is acceptable only if every result is explicitly labelled “on an invalid/audited benchmark; control-adjusted/diagnostic only.”

**Missing analyses a referee would demand.**

1. A compact evidence ledger separating preregistered primary, amended primary, post hoc exploratory, and not-run items. The current ledger is too diffuse.
2. A single primary estimand for each question. The paper mixes hit yield, E-AUROC, within-source Spearman, top-5% enrichment, AUROC, recall, and pair concordance.
3. Multiplicity control or a strict “exploratory only” quarantine for K_phys and all 54 dependent contrasts.
4. Sensitivity of L5/L7 to family/flat-structure disjointness, not just scaffold/near-duplicate filters.
5. Results of the registered L9 sensitivity, or removal of any interpretation that depends on current irregular L held-out sets.
6. Explicit denominator tables: number of compounds, flat structures, sources, families, targets, positives/inactives per regime and fold.
7. For binding validity gates, control-adjusted scores for all model arms in one table. If no arm beats strongest no-target control, say so directly.
8. Prospective/power planning for Aim A before it is run, including non-inferiority margins, multiplicity, and contamination handling.

**Interval-type and multiplicity issues.**

The draft does better than most papers by distinguishing spread, boot-mean, cluster-boot, and meta intervals. Still, it must not present boot-mean CIs over 10 or 30 seeds as population inference. The L5 decision rule used seed spread, not bootstrap CI of mean; the scaffold-shift result therefore fails by the stated rule. K_phys is not confirmatory: 54 dependent contrasts, 10 development seeds, no correction. “15 of 54 exclude 0 at 99%” suggests signal, but it is still not a controlled familywise or FDR result.

**Is the framing honest and publishable? Where?**

Yes, if reframed as an evaluation-instrument/audit/null-results paper. Suitable venues would be cheminformatics, ML-for-drug-discovery, benchmark/evaluation tracks, or a methods journal. It is not ready for a high-claim “new cyclic-peptide LM” paper. The most publishable contribution is the harsh audit: family-disjoint folds, no-target gates, analog-distance strata, source/lab clustering, and demonstration that common retrospective gains collapse to lookup/physicochemical shortcuts.

**Ranked required revisions.**

1. Remove Aim A from the title/abstract as a delivered aim; state it only as future preregistered work.
2. Rewrite the paper around three claims: permeability loop baselines, binding benchmark validity audit, and lookup/physicochemical nulls.
3. Put all primary claims in one table with estimand, unit, interval type, preregistration status, and verdict.
4. Quarantine exploratory K_phys, cheap-tier API, T1/T1b, and anchor tests into appendices unless central.
5. Replace seed-based generalisation language with cluster-based language.
6. Run or drop L9 sensitivity before interpreting regime L.
7. Provide denominator/fold/source/family tables.
8. Clean up numbering, withdrawn results, correction notes, and “VERIFIED/REPORTED” labels into stable supplement language.
9. Re-check all literature claims; keep unverified claims explicitly marked [UNVERIFIED].
10. Add a “what would falsify the future IH-LM claim” preregistered analysis plan.

## ROLE 2. CODE / STATISTICS REVIEWER

**`loop_retro/aggregate_l7.py : cluster_contrast`**

- The source-cluster bootstrap resamples per-source means with equal source weight. This matches the stated estimand, but it ignores source size. That changes interpretation, not necessarily a reported number, provided the paper says “mean over sources,” not “mean over peptides.”
- `srcs_sorted = sorted(d)` is computed, but `per_src = ... for v in d.values()` uses insertion order from prior sorted loop over sources, so it is deterministic. No defect found there.
- The seed-only bootstrap has a real failure mode: `vals` can be empty if the resampled seed multiset contains none of the seeds available for any source. With 10 seeds and sources requiring ≥3, probability is probably tiny but nonzero. Then `np.mean([])` is NaN and percentiles can become NaN. This likely does not change current reported numbers if no NaNs appeared, but the code should guard it.
- The cluster bootstrap treats sources as independent although sources may share series/literature chemistry. This changes interpretation.
- No studentization/BCa; percentile bootstrap with 6–11 clusters can be unstable. This affects interval reliability, not point estimates.
- Ties in Spearman are not handled here; upstream metric must handle them.

**`validity_gate.py : _family_ci`**

- Concrete defect: family bootstrap uses unweighted family means and reports `point=fm.mean()`. If families contain different numbers of targets/items, this is a family-level estimand, not target/item-level AUROC. This is acceptable only if stated. It changes interpretation and possibly the reported number relative to target-weighted AUROC.
- With 14–26 families, percentile bootstrap intervals are low-resolution and may undercover. Interpretation issue.
- Fixed seed is fine for reproducibility.
- If `per_target` has targets missing from `tfam`, they are silently dropped by merge. This can change reported numbers if score coverage varies by family; must report target/family coverage.

**`validity_gate.py : control_auc`**

- Potential denominator/coverage bias: `items_used_frac` is global. If `values` are missing non-randomly by target/family/class, AUROC can be biased. It can change reported validity-control numbers for atom-LM/proxy controls with incomplete coverage.
- It computes per-target AUC even if a target has only one class. If `H.tie_aware_auc` returns NaN, `_family_ci` drops it. That changes effective target/family set and should be reported.
- Tie-aware AUC is appropriate if `H.tie_aware_auc` is correct [UNVERIFIED].

**`validity_gate.py : multi_proxy_scores`**

- Serious leakage/duplication risk: `X = prox[MULTI]` is indexed by compound, but training rows `tr` are item rows. If the same `compound_id` appears for multiple targets/families, `X.loc[tr.compound_id]` duplicates identical compound features with different labels. This is not target leakage because target labels are excluded by fold, but it can overweight promiscuous compounds and create compound-series leakage across families. It changes reported no-target logistic-control numbers and their interpretation.
- Fold assignment is by target family, good for target-family holdout.
- Potential bug: `it = it[it.compound_id.isin(ok[ok].index)]` assumes `prox` index is compound_id. If not, coverage is wrong. [UNVERIFIED]
- No grouping by flat structure or stereoisomer siblings in fitting. For a no-target control this is partly the point, but it can exploit compound typicality replicated across families. Changes interpretation.
- Logistic regression has no `random_state`, but solver is deterministic enough for default lbfgs. Minor.
- If `it.fold` has NaNs for unmapped families, `sorted(it.fold.unique())` can error or skip unpredictably. Not likely if frozen tables are complete.

**`05_folds.py`**

- Family-grouped deterministic fold construction is simple and auditable.
- Concrete issue: fold weights are number of distinct compounds per family, not positives/inactives, target count, or class balance. Folds may be size-balanced but not label-balanced. This can change performance variance and power, not leakage.
- Families with zero pair labels are absent from `w` and therefore from folds. If any target family lacks labels, it is excluded. Probably intended; report it.
- No randomness/seeds; fine.

**`v4_eval/stereo_eval.py : load_groups`**

- Major transductive/statistical issue: source standardisation `mu`/`sd` is computed using all rows, including evaluation rows. For retrospective evaluation this leaks test-label distribution into labels. It changes the labels used for reported stereo metrics, not just interpretation.
- Grouping sources with <20 rows into `__other__` pools unrelated laboratories and uses pooled mean/sd. This can distort labels and may create artificial within-group variance. Changes reported stereo metrics if used.
- Uses population `np.std` default `ddof=0`; acceptable but should be stated.
- `iso` groups exact isomeric SMILES and averages multiple measurements after source-standardisation. Fine if intended.
- Since language-model stereo results are not run, this currently affects planned metrics rather than reported main numbers.

**`v4_eval/stereo_eval.py : group_metrics`**

- Pair concordance denominator excludes score ties and label ties, rather than assigning 0.5 to score ties. That inflates concordance for scorers with many ties and changes reported pair-concordance numbers. The audit headline says pair ordering uses ties 0.5, but this code does not. Statistic mismatch.
- Spearman for constant scores is set to 0.0, which is defensible, but groups with constant labels are excluded. Interpretation issue.
- Groups with any missing score are skipped entirely. Coverage bias can change reported numbers.

**`kb_audit/perm_null.py : perm_p`**

- Serious defect: the permutation null uses `rk[idx] * ry` with `den` fixed from original ranks. For Spearman permutation this is acceptable if there are no problematic ties because rank vector norm is unchanged under permutation. With ties, rankdata average ranks still preserves norm under permutation, so denominator remains valid.
- However, `idx = np.argsort(rng.random((B, len(rk))), axis=1)` is an inefficient way to generate random permutations and can in principle have random ties, though floating ties are negligible. It changes neither number nor interpretation materially.
- Missing guard: if `den == 0` for constant k or y, obs/null become NaN. Could change numbers for low-variance labs; must handle.
- P-value is two-sided with +1 correction; fine.

**`fusion/fusion.py : fuse`**

- No defect in the formula if `z()` handles zero variance. If `z()` does not, constant prior/analog scores produce NaNs [UNVERIFIED].
- `k` is described as number of revealed labels but `w_k(k,n0)` is not shown; cannot verify weighting.

**`fusion/fusion.py : analog_perm`**

- The estimate centers revealed labels by `y.mean()` but does not add the mean back. That is fine for ranking, but not for calibrated prediction. Interpretation issue.
- Uses raw revealed labels, not source-standardised labels. In leave-lab-out permeability this may be affected by lab offsets; changes numbers if source scales differ.
- Self-similarity is not relevant because sim is rest × revealed.
- No tie/zero-mass problem because denominator has `lam`.

**`fusion/fusion.py : reliability_perm`**

- Concrete statistical defect: LOO prediction centers each row by `(y.sum()-y[j])/(k-1)` but multiplies all weights `W[j]` by the vector `y - loo_mean`, including the held-out element. Since diagonal was zeroed, the held-out term contributes zero, so it is not direct leakage. Acceptable.
- Reliability is estimated on the same revealed set used to fit analog component; high variance and selection-biased in active learning. Changes interpretation and possibly fusion weights.
- Spearman function imported is unclear. If it returns a tuple like SciPy’s `spearmanr`, `np.isfinite(rh)` would fail. Since results exist, likely a wrapper. [UNVERIFIED]
- Clipping negative reliability to 0 discards evidence that analog lookup is anti-correlated. This can improve results relative to an unconstrained reliability estimator; changes method definition and interpretation.

**`fusion/fusion.py : fuse2`**

- Multiplying only the analog z-score by `r` while leaving the prior term weighted by `w_k` means total score scale shrinks when `r` is small. For rank metrics, shrinkage relative to prior matters. This is the registered F2 if stated; no code defect.
- Again depends on robust `z()` [UNVERIFIED].

## ROLE 3. DATA / EVALUATION REVIEWER

**Leakage routes.**

- Pretrained comparator corpora are the largest unresolved leakage route. The paper acknowledges possible overlap with CycPeptMPDB, source literature, benchmark positives, and in-house pretraining corpora. Since comparators have not been run, this is a future risk, not a current result.
- The permeability data are heavily series- and laboratory-concentrated: Townsend and Kelly dominate rows/hits. In-distribution performance is largely series interpolation.
- Regime A has large near-duplicate exposure: identical fingerprints/flat structures/stereo-free scaffolds in the pool relative to initial set. It is not a generalisation regime.
- Stereoisomer siblings are pervasive: 6,960 peptides but only 2,460 flat structures. Any chirality-blind fingerprint model can leak flat-structure analog information while failing stereochemical distinctions. Family/flat-structure grouping is essential.
- Binding benchmarks are vulnerable to decoy shortcuts: cross-target decoys can be solved by similarity; matched decoys can be solved by typicality/no-target controls; analysis I still fails fingerprint no-target control.
- Source/laboratory leakage occurs whenever source standardisation or label thresholds are estimated using the full source, including test rows. The L5 label audit partly quantifies transductive sensitivity, but it remains a caveat.
- Literature/pretraining contamination flags are necessary but not sufficient. Absence of exact compound overlap does not exclude analog/series overlap.

**Validity gates and control-adjusted rule.**

The validity-gate design is appropriate and unusually honest: no-target controls must be at chance before model arms are trusted. Since no benchmark passes, the correct conclusion is not “our model failed” but “this public benchmark construction is not clean enough for unadjusted zero-shot claims.” The control-adjusted rule—beat strongest baseline and controls on AUROC and enrichment—is strict and defensible. The draft should show actual control-adjusted model scores, not only gate failures.

**Family-disjoint folds.**

The fold construction is family-grouped by Pfam-Jaccard components and deterministic. That is better than random target splits. But Pfam-Jaccard families are not necessarily biological/assay independence units; they are a chosen clustering scheme. Class balance and target count are not controlled in the fold packer. Any fold-level claim must report family count, target count, compound count, positives/inactives, and coverage.

**Regime definitions and leave-laboratories-out set sizes.**

Regime definitions are too complicated for a reader. A, B, C, L, L9, E-slice, H4b, M/M2/M3/I all appear. The leave-laboratories-out regime is especially problematic:

- Eligible pool: 18 laboratories.
- Townsend and Kelly are never held out.
- Seeds hold out 6–18 laboratories.
- In 3/10 seeds all 18 eligible labs are held out.
- Held-out fraction is 25.2–34.3%, not fixed.
- Cluster intervals for E-metrics use only sources with ≥15 E peptides in ≥3 seeds, yielding 11 sources.

This is not a clean “new laboratory” evaluation of the dominant laboratories. The L9 sensitivity should be run before publication, and the language should say “held-out subset of eligible smaller laboratories, with two dominant laboratories always retained,” unless that is inaccurate [UNVERIFIED].

**Power.**

Power is limited and correctly acknowledged. Analysis I with 26 families has MDE about 0.11 AUROC; M2 about 0.185. Thus nulls do not exclude small model effects. Few-label gains over zero-shot are large enough to be well powered, but they are analog-neighbour gains. K_phys loop contrasts with 10 seeds are underpowered for small reliable effects and overexposed to multiplicity.

**Multiple comparisons.**

The knowledge-arm analysis is the worst offender: 54 dependent contrasts, no correction, development seeds, post hoc interpretation. It should not appear in abstract except as “exploratory; confirmatory rerun pending.” The manuscript is mostly honest about this, but still gives it too much space and narrative weight.

**Selection of arms.**

There are too many arms: plain GBM, chirality-aware GBM, physicochemical-channel GBM, K_phys, K_shuffled, K_none, random feedback, shuffled-label feedback, frozen model, data-matched one-shot, fusion variants F1/F2/F1b/F2b, prompted API models, nearest-neighbour, zero-shot, pretrained+revealed, etc. A reader cannot distinguish primary controls from exploratory engineering. Reduce to preregistered primary arms in main text; move the rest to supplement.

**Can public CycPeptMPDB-style data support the claims at all?**

It can support a narrow retrospective claim: on this fixed public finite library, under explicit source/family/analog controls, simple active selection beats random mainly by exploiting series, analog, and physicochemical structure. It cannot support strong claims about prospective design, novel chemotype transfer, cross-laboratory generalisation, or superiority of language models. The source concentration, stereoisomer redundancy, lab offsets, missing anchors, and public/pretraining contamination make it unsuitable as the sole evidence base for a high-stakes model-comparison claim.

## THE SINGLE MOST DAMAGING FLAW

**Flaw:** the central comparison advertised by the project—IH-LM versus larger pretrained peptide/chemistry models inside the closed loop—has not been run.

**Why it is most damaging:** without this, the manuscript is not evidence for the main model hypothesis. All current results are baselines, audits, nulls, and retrospective controls. Those are valuable, but they support a different paper. Keeping the unrun IH-LM aim in the frame invites readers to treat evaluation scaffolding as indirect support for a model claim that has no empirical result.

**Cheapest one-day test:** run a minimal smoke-test loop on a small frozen subset with one IH-LM checkpoint or random-initialized/proof-of-pipeline checkpoint and one available pretrained comparator, using identical revealed labels, one regime, two seeds, and the existing controls. This will not settle the scientific question, but it will confirm whether the claimed loop interface, fine-tuning path, scoring, contamination filters, and aggregation actually execute end-to-end. If even that cannot run within a day, the model-comparison paper is not merely incomplete; it is operationally unready.
