<!-- model=openai/gpt-5.5 finish=stop tokens_in=33459 out=6842 reasoning=20 cost=0.372555 -->
# External reviewer GPT (openai/gpt-5.5)

## ROLE 1. MANUSCRIPT REFEREE

The draft is unusually candid, but it is not yet a paper about an in-house cyclic-peptide language model or about larger pretrained models in a closed loop. It is, at most, a retrospective evaluation-instrument/audit paper plus baseline GBM loop behavior on public permeability data and failed/null technique studies. The current framing “Two aims, one paper” is risky: Aim A is central in motivation but not run, and the manuscript’s strongest publishable contribution is actually Aim B. I would require the title, abstract, and introduction to make the paper sound like “audited retrospective loop benchmarks and null controls for cyclic-peptide permeability/binding,” not “closed-loop learning with IH-LM.”

What it can claim:

1. A simple GBM loop can select more high-permeability compounds than random from a fixed retrospective CycPeptMPDB-style library, especially in-distribution.
2. The in-distribution gain is heavily entangled with laboratory/series concentration and likely inflated by transductive source standardization and thresholding.
3. Under scaffold shift, the pre-registered “loop beats random” rule was not met, and a post hoc/label-free physicochemical rule was not distinguishable from the loop.
4. In leave-laboratories-out analyses, yield improvements exist, but held-out ranking improvement from sequential feedback over data-matched controls is not demonstrated consistently.
5. Public binding benchmark constructions attempted here fail no-target/typicality/censoring controls; therefore absolute zero-shot/few-label binding claims are not validated.
6. Few-label binding gains on analysis I look like analog lookup, not transfer to remote chemotypes.
7. Fusion and anchor-offset techniques are not supported as registered.
8. The paper can honestly present an evaluation instrument with validity gates, audited nulls, and planned Aim A, if the unrun central comparison is clearly excluded from the evidence base.

What it cannot claim:

1. That IH-LM works, is competitive, or adds value. No real-data IH-LM run exists.
2. That larger pretrained peptide/chemistry LMs have been beaten, matched, or fairly compared in the loop.
3. That retrospective loop success implies prospective discovery or molecule generation benefit.
4. That the binding benchmark supports true family-held-out zero-shot generalization; no benchmark passes the gate.
5. That K_phys helps in a confirmatory way; the current loop evidence is development-set, multiplicity-heavy, and not cluster-supported.
6. That anchor panels are a recommended design for ranking; D1 argues the opposite.
7. That “closed-loop learning improves the model” in a general sense; the evidence mainly supports selection/exploitation yield.

Internal inconsistencies / tension points:

- The abstract still gives many numerical “Results” before making clear that the central hypothesis is untested. This may mislead readers into thinking the paper validates the closed-loop LM program.
- “Loop beats random in-distribution by a wide margin that survives removing near-duplicates” appears in Discussion, but regime C is described as removing identical flat structures only, not near duplicates; 26.9% still have Tanimoto ≥ 0.9 to an initial peptide. This should be softened unless a real Tanimoto purge is complete.
- Regime L is called leave-laboratories-out but is irregular: the two dominant laboratories are never held out, held-out sets vary by seed, and all-18-held-out occurs in 3/10 seeds. The draft now discloses this, but headline language should say “small-laboratory-held-out” or “eligible-laboratory-held-out,” not clean leave-laboratories-out.
- “No benchmark passes the validity gate” is well supported, but the gate was retrospective. That is fine as an audit finding, not as a pre-registered benchmark rejection unless the chronology is stated every time.
- Binding analysis I has a censoring shortcut stronger than compound-only controls. The manuscript should not let no-target fingerprint AUROC 0.584 appear to be the only problem; censoring may be the dominant flaw.
- Literature statements in Section 8 include multiple [LIT-SNIPPET], [LIT-UNVERIFIED], and blocked/unverified readings. These must not be cited as established prior art without primary verification.

Missing analyses a referee would demand:

1. Complete the causal-normalization arm for P1 before making any quantitative in-distribution yield claim beyond “upper bound.” The single-seed check showing 251 leaky vs 151 causal vs 64 raw is too important to leave as indicative.
2. Provide source-cluster/laboratory-cluster intervals for any claim about generalization to laboratories. Seed bootstraps are inadequate for new-lab statements.
3. Run or remove the Tanimoto ≥ 0.8/0.9 near-duplicate-free regime if claiming near-duplicate robustness.
4. Multiplicity control for K_phys and any knowledge variants; otherwise keep them appendix/exploratory.
5. A clear estimand table: yield vs held-out ranking, seed-based vs source-cluster, fixed-library vs population inference.
6. Binding gate: include a paired comparison between zero-shot pretrained model and no-target controls if any language-model score is discussed. Overlapping intervals are not a test.
7. For analysis I, report censoring-controlled or exact-only feasibility results prominently; current audit says exact-only is infeasible, so this likely downgrades all binding conclusions to diagnostic only.
8. Add a one-page “claims not made” box: no IH-LM result, no pretrained comparator result, no prospective validation, no clean binding benchmark.
9. Confirm all hashes/artifacts and remove “to be re-verified” before submission.

Interval and multiplicity issues:

- The draft has improved by labeling spread, boot-mean, cluster-boot, and meta intervals, but it still risks mixing them rhetorically. The pre-registered L5 decision used spread; post hoc boot-mean should not rescue conclusions.
- Seed bootstraps over 10 paired seeds are weak and conditional on one library. They are acceptable for algorithmic variability, not for laboratory-population inference.
- Cluster bootstraps over 6, 9, 11, 14, 16, or 26 clusters have wide/unstable coverage. The paper should avoid binary “supported” language unless decision rules were truly pre-registered and power is stated.
- K_phys: 54 dependent contrasts, development seeds, no multiplicity correction. It must remain exploratory.
- The validity gate uses multiple primary and secondary controls; the equivalence framing is good, but because it was retrospective its role is audit/instrument design, not confirmatory inference.

Publishability:

A rigorous methods/audit paper could be publishable in a cheminformatics, ML-for-drug-discovery, or benchmark/evaluation venue if reframed around failures, controls, and baseline behavior. It is not ready as a claims-forward AI model paper. The honesty is a strength, but the manuscript must stop centering an unrun model comparison.

Ranked required revisions:

1. Retitle/reframe as an evaluation/audit and baseline-loop paper; move Aim A to future work unless run.
2. Complete causal-normalization and near-duplicate-purge sensitivity or downgrade all P1/P2 claims accordingly.
3. Replace “leave-laboratories-out” headline language with a precise description of the irregular eligible-source design.
4. Remove or quarantine all unverified literature claims and all running-now material.
5. Make binding results diagnostic only; no absolute benchmark-performance claims from failed gates.
6. Add a single canonical claims table with allowed/downgraded/deleted claims and interval type.
7. Apply multiplicity correction or keep K_phys wholly exploratory.
8. Verify all artifact hashes and remove “to be re-verified” language before submission.
9. Shorten numerical overload in the abstract; use it to state evidential boundaries, not every result.
10. Add a “no IH-LM result” statement to title/abstract/conclusion if the model remains unrun.

## ROLE 2. CODE / STATISTICS REVIEWER

### `loop_retro/aggregate_l7.py : learner_key`

Concrete status: the prior key-collision defect appears addressed for current files that either contain `learner` or have informative directory names.

Defects / risks:

- Directory-name inference is brittle. If a run directory lacks “blind” but contains blind GBM results with `backend="gbm"` and no `learner`, it will be classified as `gbm_aware`. This changes reported numbers if legacy files are misnamed. The fix depends on filesystem naming, not run metadata.
- `"confirm"` substring matching can misclassify unrelated names containing that substring. Probably low risk, but it affects aggregation interpretation and potentially reported confirmatory/development separation.
- `gbm_physchem` is treated specially only when not confirm/res7m/res7q. This seems intentional. I see no line-level arithmetic defect in the excerpt.

Effect: could change reported numbers if any legacy/current result file lacks `learner` and lives under a misleading directory name; otherwise only interpretation/provenance risk.

### `loop_retro/aggregate_l7.py : cluster_contrast`

Good features: uses sorted sources, drops nonfinite values, reports source-level mean, distinguishes cluster vs seed-only intervals.

Defects / risks:

- The point estimate weights each source equally after averaging seeds within source. That is a legitimate source-level estimand, but it is not peptide-weighted or held-out-set-weighted. It changes interpretation, not necessarily a number if this is the intended estimand.
- Source inclusion requires `len(dd) >= min_seeds`. Sources held out fewer than 3 seeds are dropped. This can bias the source estimand toward more frequently sampled held-out laboratories, especially because regime L held-out sets are irregular. This changes reported cluster means and CIs.
- `ci_seed_only` resamples global seed labels across sources even though not every source appears in every seed. When a resampled seed has no value for a source, the source may be dropped from that bootstrap replicate’s mean. This is described, but it is an awkward bootstrap for the irregular design and can under/overstate seed variability. Interpretation issue; could alter seed-only intervals.
- Cluster bootstrap resamples source means only, not source-by-seed blocks. Since seeds are averaged before clustering, within-source seed uncertainty is ignored in the cluster CI. With 3–10 appearances/source this likely narrows CIs. Changes reported CI width.
- Deterministic seed `_seed(per_src, lo, hi)` is not shown. If it hashes rounded/floating values, tiny numerical changes can alter bootstrap draws. [UNVERIFIED]

Effect: source-cluster reported numbers and intervals are conditional on a source-equal, min-3-seed estimand; CIs may be too narrow because within-source seed uncertainty is not propagated.

### `validity_gate.py : _family_ci`

No obvious line-level bug for the stated family-equal estimand.

Defects / risks:

- Family means are unweighted by number of targets/items. Valid if intended, but not a target/item-level AUROC estimand.
- Targets with undefined AUROC are silently dropped before family means. This can bias controls if undefined targets are systematically single-class after filtering. The draft discloses dropping undefined targets; still, report counts per control.
- Percentile bootstrap over as few as 14–26 families is coarse and may have poor coverage. Interpretation/power issue, not a code bug.
- Fixed seed `seed=5` makes intervals reproducible but does not explore Monte Carlo error. With B=10000 likely acceptable.

Effect: affects interpretation and possibly CI coverage; no concrete arithmetic defect found in excerpt.

### `validity_gate.py : control_auc`

Concrete defect/risk:

- `items.compound_id.map(values)` assumes `values` is indexed uniquely by compound_id. If `values` has duplicate compound IDs or mismatched key type, pandas mapping may fail or silently produce unexpected results depending on construction. [UNVERIFIED] Needs assertion of unique index.
- Items with missing scores are dropped, then AUROC is computed per target. If missingness is label-correlated, `items_used_frac` alone is insufficient; target-level used fractions should be reported. This can change reported AUROC if coverage differs by label.
- Tie handling depends on `H.tie_aware_auc`; not shown. If constant scores return 0.5, fine. [UNVERIFIED]

Effect: potential reported-number change if score coverage is nonrandom or value index is nonunique; otherwise interpretation.

### `validity_gate.py : assign_status`

Good: NaN/too few families become unverifiable; equivalence is not confused with “CI contains 0.5.”

Defects / risks:

- Primary bias check uses `v["lo"] > 0.5 or v["hi"] < 0.5`, where `lo/hi` correspond to `PRIM_LEVEL`. Packet 4 says primary bias flags now use Bonferroni 98.3%. If `PRIM_LEVEL` is indeed 0.983, this is fine; if manuscript tables quote 95%, status and displayed intervals differ. Needs explicit display of status interval level. Potential interpretation mismatch.
- Secondary controls use `adj = 1 - 0.05/n_sec`; that is Bonferroni two-sided-ish by CI level, but many secondary controls are diagnostic. Fine if pre-registered.
- Degenerate secondary controls with `lo == hi` are not biased. If a constant secondary score yields 0.5 exactly, okay; if a degenerate but non-0.5 AUROC occurs due to implementation quirks, this would bypass biased. Rare; should assert degenerate point equals 0.5.

Effect: mainly status/interpretation; possible status number change if interval levels mismatched.

### `validity_gate.py : run_gate`

Defects / risks:

- `folds_evaluated` maps target family to folds using `items.target_key.map(tfam.set_index("target_key").family).map(folds)`. If `folds` is keyed by family this is fine; if keyed by target or fold ID, this is wrong. [UNVERIFIED] Given previous pandas/fold-family error in audit, I would require a unit test.
- Multi-proxy and fingerprint controls merge scores with labels per `(target_key, compound_id)`. If `items` has duplicate rows for same target-compound, merge can duplicate rows and affect AUROC. Need uniqueness assertion.
- `FP = fp_table(items.compound_id)` may compute fingerprints for repeated compound IDs repeatedly unless the helper deduplicates. Efficiency, not statistical.
- Training exclusion logic for `multi_proxy_scores`/`fp_scores` is not shown; leakage cannot be ruled out from excerpt. [UNVERIFIED]

Effect: could change reported validity-gate numbers if duplicate target-compound rows or fold mapping errors exist; otherwise no defect in visible lines.

### `loop_retro/run_l7a.py lines 160-176`

Defects / risks:

- Knowledge fusion weight `w = 100/(100+len(revealed))`: because `len(revealed)` likely includes the initial 100, the initial knowledge weight is 0.5, not 1.0. If the intended formula was `n0/(n0+n_new)` with `n_new` excluding initial labels, this is wrong. The comment says “n0=100” but not whether `revealed` includes initial. This can materially change K_phys/K_shuf results. [UNVERIFIED but high priority]
- `K.zs(ch[U])` z-scores the knowledge channel within the current candidate pool. This is transductive with respect to candidate distribution but label-free. Acceptable if intended; it means scores depend on what else remains in the pool.
- Stable argsort has no random tie-break for nonknowledge arms here. If many equal predictions occur, input order controls picks. Could bias deterministic policies if `U` has source/order structure. Changes numbers if ties are common.
- `s` may be referenced later even for branches where not defined? In shown code, random branch presumably defines `s` earlier; frozen branch shown does not set `s` unless defined outside. The excerpt has `if s is not None:` after frozen branch. If `s` is stale from a previous round/branch, pick_scores could be wrong. Need inspect initialization before excerpt. [UNVERIFIED] This may affect logged scores, likely not picks.
- `pick_std` is not recorded for knowledge-fused arms even if uncertainty exists. Interpretation/logging only.

Effect: possible material changes for knowledge-arm numbers; possible logging defect for frozen scores; tie bias may affect picks.

### `technique_sprint/acquisition/acq.py : setup_L`

Concrete design defect:

- The two largest laboratories are always excluded from being held out. This is not a clean leave-laboratories-out design; it tests transfer to smaller eligible labs only. Changes interpretation materially.
- Held-out laboratories are accumulated until peptide fraction ≥25%, so the number of held-out labs and peptide fraction vary by seed. This complicates paired comparisons and cluster inference.
- `ids = list(train); random.Random(seed).shuffle(ids); return ids[:n_init], ids[n_init:], test...` gives initial and pool only from nonheldout labs. Good for no label leakage into test, but the initial source composition is random over dominant labs and may vary strongly.

Effect: design/interpretation, not a code bug if registered.

### `technique_sprint/acquisition/acq.py : causal_z`

Potential concrete defect:

- Function returns z-scored labels only for `idx`. For model training this is fine. But source-specific shrinkage uses the same revealed peptide’s label in estimating its own source mean/variance. That is causal in time but not leave-one-out within training. Acceptable for training target normalization.
- For sources with one revealed label, `yr[m].var()` with NumPy default ddof=0 gives 0; shrinkage to global variance avoids zero. Fine.
- If `idx` empty, `yr.mean()` is NaN; probably never called with empty labeled set. No issue.

Effect: no defect found in excerpt; it supports causal training labels but not causal hit thresholds unless thresholds are separately causal.

### `technique_sprint/acquisition/acq.py : select_diverse`

Defects / risks:

- With frozen config `lam=0`, `cap_src=50`, `cap_flat=inf`, this function reduces essentially to greedy top-score selection for 50-pick batches. Thus T2 selected “prov” is not a diversity ablation. This is correctly disclosed.
- If `cap_src` equals batch size 50, the cap prevents more than 50 from a source in a 50 batch, i.e. no effective source cap within a batch. Interpretation only.
- Tanimoto similarity uses sparse/dense matrix multiplication [UNVERIFIED type]. If `D["B"]` is boolean, `BU @ BU[j]` may return bool rather than counts depending on type. Need confirm numeric fingerprint matrix. Potential number change if boolean matmul semantics are wrong. [UNVERIFIED]

Effect: no visible defect if matrices numeric; selected config has no diversity effect.

### `technique_sprint/acquisition/acq.py : run_arm`

Defects / risks:

- In causal mode, model training uses `causal_z(D,L)`, but hit counting still uses `y[i] >= thr` where `y = D["y"]` and `thr = D["thr"]` unless changed. If `D["y"]`/`D["thr"]` are transductive within-source standardized labels/thresholds, then the causal arm still evaluates hits with transductive thresholds. This is acceptable for a fixed retrospective endpoint but does not solve transductive hit-definition inflation. It changes interpretation, possibly numbers if causal thresholds were intended.
- `nn_greedy`: `top = np.argsort(-S, axis=1)[:, :NN_K]`; then `lab = yL[top]`. Here `top` indexes columns of `S`, corresponding to positions in `L`, so `yL[top]` is correct.
- For random arm, `score = rng.random(len(U))`, then selection by argsort. Fine.
- For `rule_phys`, tiny random jitter breaks ties reproducibly. Good.
- For `div` and `prov`, `select_diverse` returns positions into `U`; for other arms argsort positions are used. Good.
- `flat_count` is initialized empty and only updated after selected picks, not with initial labeled flat structures. If diversity is intended to avoid selecting flat structures already present in the initial labeled set, this is a defect. It changes picks for diversity/cap arms when `cap_flat` is finite. In the frozen config cap_flat is infinite, so current selected config unaffected.
- Ensemble fitting uses the same RNG object that may have been consumed differently across arms. Comparability across arms may be affected if intended common random numbers were desired. Interpretation/noise, not leakage.

Effect: current frozen `prov@lam0 cap_flat inf` mostly unaffected by diversity-count issue; causal endpoint may remain transductive.

### `frozen_config.json`

No code defect. Design issue: selected `prov@l0.0_s50_finf` has no diversity penalty and no meaningful diversity cap. Calling it provenance/diversity-aware would be misleading. It is essentially UCB/physchem fusion with causal ymode.

### `make_ud.py` diff

Fix from `nproc` to `nproc --all` addresses the OMP-related under-parallelization. Remaining operational risk:

- Sequential comma-joined stages share one S3 prefix by assertion, good.
- Prior bare `wait` blocking on sync loop is mentioned in packet but not visible in diff; I cannot verify it is fixed. [UNVERIFIED]
- Spot-resume behavior depends on per-task idempotence and S3 sync; not assessable from excerpt.

Effect: launch/runtime only, not reported scientific numbers unless partial/stale files enter aggregates.

## ROLE 3. DATA / EVALUATION REVIEWER

Leakage routes and confounding are the central issue, not a side limitation.

Permeability / CycPeptMPDB-style data:

- Laboratory leakage was real: 178/6,960 peptides had wrong source annotation, and leave-labs-out Spearman dropped from about 0.30 to about 0.22 after correction. This is material. The manuscript now discloses it, but it should make readers distrust source labels unless every source-dependent artifact is regenerated and frozen.
- The two dominant laboratories are never held out in regime L. Since Townsend/Kelly are 65% of peptides and Townsend alone dominates hits, regime L does not test transfer away from the dominant chemical/laboratory regimes.
- Within-source standardization and top-10% thresholds use all labels from the source in primary L5. That is transductive and likely inflates hit yield. The single-seed check suggests the inflation is large. This must be resolved or the main yield number should be called an upper bound only.
- Series leakage remains: regime A is series interpolation; regime C removes identical stereo-free structures but leaves many near analogues. Scaffold-shift B is more relevant, and there the registered criterion is not met.
- Stereoisomer sibling handling appears improved by flat-structure grouping, but public peptide series often differ by N-methyl/D-L scans; flat grouping alone does not remove analog leakage.
- Descriptor models outperform fingerprints under some unseen chemistry/laboratory settings; this supports the paper’s own conclusion that simple physicochemical rules are strong baselines.

Binding benchmark:

- Pfam-family-disjoint is not protein-, compound-, analogue-, or document-disjoint. Same UniProt accessions cross families, αvβ6/β6 duplication exists, and exact compounds cross folds.
- Analysis I is not compound-disjoint: 11.6% of rows have the same compound in another fold; strict compound-disjoint reruns still fail controls, so exact duplicate leakage is not the whole problem.
- Near-duplicate rates remain high at Tanimoto ≥0.70 across folds. For cyclic peptides, fingerprint Tanimoto may understate scaffold/series relatedness; analogue leakage likely persists.
- Censoring is a severe no-target shortcut: 63.6% of inactives are censored “>” versus 3.1% of positives; inverted censoring indicator AUROC about 0.794. This alone undermines absolute claims on analysis I.
- M and M2 are invalid by construction or controls: M has cross-target binder/decoy similarity artifacts; M2 has typicality and fingerprint separability; M3 is infeasible.
- Protein-level folds_v2 also fail controls. This is important: the issue is not just Pfam packing.
- Contamination flags for pretrained corpora are planned/reported, but they cannot fully remove overlap with public source literature, CycPeptMPDB, BindingDB, ChEMBL, or derived corpora. Any pretrained comparator must be evaluated on contamination-controlled subsets and against no-target/nearest-neighbor controls.

Validity gates and control-adjusted rule:

- The gate is conceptually strong: no-target controls must be equivalent to chance, not merely have CIs crossing 0.5.
- However, it was applied retrospectively after M2 failed. That does not invalidate it as an audit, but it weakens confirmatory status.
- “SUPPORTED only if lower 95% bound of difference from strongest baseline exceeds zero for AUROC and top-5% enrichment” is appropriately stringent. Current arms apparently do not meet it.
- Because no benchmark passes, the correct conclusion is not “our models fail”; it is “this public benchmark cannot adjudicate the intended zero-shot/few-label claims without control adjustment.”

Family-disjoint folds:

- Pfam-Jaccard families are not enough for integrins and multi-subunit complexes. Protein-level folds_v2 are needed but still not sufficient if compounds/analogues/documents cross folds.
- Family-cluster bootstrap with 14–26 families has limited power and unstable CIs. The manuscript should describe gates as “failed or unverifiable,” not as precise estimates of benchmark bias.

Regime definitions and leave-laboratories-out set sizes:

- Regime A: in-distribution/series interpolation.
- Regime B: scaffold-shifted start, but needs exact definition and leakage audit in main text.
- Regime C: identical-flat-structure sensitivity only; not near-duplicate-free.
- Regime L: irregular eligible-small-lab holdout. It has 6–18 held-out labs per seed and 25.2–34.3% peptides; source-cluster tables use 6, 9, 11 evaluable sources by regime/metric. This should not be marketed as a clean leave-lab-out benchmark.
- L9 cap sensitivity is not run; any inference depending on irregular L design is provisional.

Power:

- Aim A has no data.
- L7 has only 10 development seeds; source-cluster analyses have few clusters. MDEs around 0.13–0.19 for some cluster contrasts mean nulls are low-power.
- Binding zero-shot analysis has MDE around 0.11 AUROC on I and worse on M2; lack of support does not imply small effects are absent.
- Anchor D1 is useful: no simulated anchor-panel design reaches 0.80 power for relevant ranking gains, so recommending anchors would be unsupported.

Multiple comparisons / arm selection:

- K_phys has 54 dependent contrasts and no multiplicity correction; exploratory only.
- T2 selected configuration freezes to lambda 0/no meaningful diversity. Any later “diversity” interpretation would be false.
- GPU/ChemBERTa files with n≤5 and incomplete aggregation must not enter claims.
- IH-LM ladder amendments are design-only until run.

Can public CycPeptMPDB-style data support the claims?

It can support a limited fixed-library retrospective statement: GBM-guided acquisition enriches high measured permeability compounds relative to random under interpolation-like conditions. It cannot by itself support claims about prospective molecular design, broad generalization to new laboratories, or superiority of language models. For binding, the public ChEMBL/BindingDB-style cyclic-peptide data in this packet cannot support clean zero-shot family-held-out claims because every constructed benchmark fails no-target/typicality/censoring controls or is infeasible.

## CLAIMS I WOULD DELETE

From PACKET 2, I would delete or downgrade the following before submission:

1. “L5 in-distribution loop − random +186.3” — downgrade to “transductive upper bound” until causal normalization is completed; current hit definition uses all source labels.
2. “Loop picks 346 of 500 from one laboratory in-distribution” — keep as an audit fact, but not as performance evidence; it indicates concentration/confounding.
3. “Regime-L yield contrasts … loop − random feedback +186.1” — downgrade for generalization; yield intervals are seed-based and dominant labs are never held out.
4. “Held-out-ranking contrasts with laboratories as the unit … aware loop − frozen excludes 0” — keep only as learner-dependent, low-cluster-count evidence; do not state model improvement on new laboratories.
5. “K_phys offline association … permutation p < 10⁻³” — keep offline association, but delete any implication that it helps loop performance.
6. “K_phys loop contrasts … 15 of 54 exclude 0” — downgrade to appendix exploratory; missing multiplicity correction and development seeds only.
7. “Across three retrospective loops … model-guided selection beats random and lookup reproduces most margin under shift” — downgrade; one replay is explicitly a small illustration, C2 original logs withdrawn, and tasks are heterogeneous.
8. “Cheap-tier general-purpose language models … far behind GBM” — keep only as exploratory appendix; 4 seeds and not central comparator.
9. “Anchor calibration not supported … needs a shared anchor panel” — modify: D1 says even shared panels are not recommended for ranking under the simulated conditions.
10. “IH-LM design and module status” — do not include in claims table as a scientific result; design/provenance only.
11. Any literature claim marked U, LIT-SNIPPET, LIT-UNVERIFIED, blocked, or not re-verified — delete or mark [UNVERIFIED] until primary sources are checked.
12. Any claim about IH-LM vs larger models, P1, T2 results, S2, or K_phys confirmatory effect — delete from results; these are planned/running, not evidence.

Claims currently missing a control:

1. In-distribution yield claim lacks completed causal source-normalization/hit-threshold control.
2. Near-duplicate robustness lacks a true Tanimoto-purged regime.
3. Zero-shot/few-label binding model claims lack a passed no-target/censoring/typicality gate.
4. K_phys loop benefit lacks multiplicity-controlled confirmatory seeds and source-cluster support.
5. Pretrained model comparisons lack contamination-controlled, nearest-neighbor, no-target, and information-privileged analog baselines because they have not been run.

## THE SINGLE MOST DAMAGING FLAW

The most damaging flaw is that the main positive permeability yield result appears substantially inflated by transductive within-source standardization and hit thresholds that use unrevealed labels from the same source.

Why this is most damaging: the strongest numerical success in the manuscript is the in-distribution loop’s +186 hits/500. But the packet’s own single-seed check suggests the result can collapse from 251 hits under the transductive convention to 151 with causal-from-labelled normalization, 64 with raw pooled labels, versus 47 random. If this generalizes, the headline “loop beats random strongly” is partly an artifact of using future/source-wide label information and laboratory-specific thresholds, not closed-loop learning.

Cheapest one-day test: run the already described causal-normalization arm for L5/P1 over at least seeds 0–9, with training normalization and hit thresholds computed only from revealed labels or with a fully raw-label endpoint reported side by side. Freeze a table: loop, random, physicochemical rule, nearest-neighbor/rule baseline under transductive, causal, and raw endpoints. If the loop advantage remains large under causal/raw definitions, the paper’s baseline loop claim survives; if it shrinks toward the single-seed result, the main positive claim must be rewritten as a transductive upper bound.
