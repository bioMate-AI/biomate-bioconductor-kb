<!-- model=openai/gpt-5.5 finish=stop tokens_in=19431 out=6083 reasoning=15 cost=0.279645 -->
# Reviewer GPT (openai/gpt-5.5)

## PART A. NOVELTY

### (a) In-house hybrid loop-native cyclic-peptide LM with M1–M5

**Closest real prior art**

- **Peptide/chemistry LMs and peptide representations:** peptide/molecule language models using SMILES/SELFIES/HELM-like representations, including PeptideCLM / PeptideCLM-2 [UNVERIFIED details beyond name], ChemBERTa, MolBERT-style chemistry encoders, and HELM-based peptide models [UNVERIFIED specific venues/authors in packet].
- **Retrieval-augmented prediction:** retrieval-augmented molecular/property models and nearest-neighbour molecular baselines; more broadly retrieval-augmented generation is standard.
- **Knowledge + neural hybrids:** Bayesian priors, random effects, mixed-effects models, hierarchical assay models, and residual learning over hand-engineered descriptors are all old ideas.
- **Matched molecular-pair / edit-effect modelling:** matched molecular pair analysis is established in medicinal chemistry; edit-effect prediction is not new in general.
- **Closed-loop molecular optimization:** Bayesian optimization / active learning loops for molecules and peptides are well established. Examples I am confident exist include Gómez-Bombarelli et al., 2018, *ACS Central Science* on automatic chemical design with a data-driven continuous representation; Griffiths and Hernández-Lobato, 2020, *Chemical Science* on constrained Bayesian optimization for automatic chemical design; and Brown et al., 2019, *ACS Central Science* on GuacaMol benchmarks.

**What is genuinely new, if implemented and ablated**

- The novelty is not the backbone, tokenization, retrieval, random effects, or priors individually. The defensible novelty is the **specific integration** for cyclic peptides:  
  `prediction = evidence-weighted cyclic-peptide knowledge prior + anchor-calibrated lab/assay offset + stereo-aware analog-retrieval residual + edit-space head + dual symbolic/neural loop memory`.
- The strongest potentially new module is **M2 anchor-based lab/assay offset inside a loop**, because the packet shows cross-lab effects are a dominant failure mode and the proposed anchor protocol directly targets that.
- **M4 edit-space head** could be useful and somewhat distinctive if it predicts transferable cyclic-peptide edits — N-methyl addition/shift, D/L flips, residue swaps, ring changes — under leave-labs-out evaluation. But matched-pair analysis itself is not novel.
- **M5 dual-memory loop** could be interesting if the paper demonstrates fast symbolic updating and slow neural updating with a measurable crossover. Right now it is only a design story.
- The architecture is only novel if the **same-base ablation ladder** shows additive value: plain backbone → +M1 → +M2 → +M3 → +M4 → +M5. Without this, the “IH-LM” label is packaging.

**What must NOT be claimed**

- Do **not** claim a new transformer architecture unless the backbone itself changes materially. The spec says the backbone is standard.
- Do **not** claim novel stereo-aware tokenization. Chirality-aware SMILES and peptide-specific tokenization already exist.
- Do **not** claim novel retrieval-augmented chemistry modelling. Retrieval is standard, and your own H4b results show nearest-neighbour is the bar.
- Do **not** claim the model generates better peptides. Retrospective replay with existing labels does not establish prospective molecular generation.
- Do **not** claim “knowledge helps” unless the knowledge-on arms beat strong controls. Current L5 aggregate does **not** show significant benefit: e.g. fp_A total 236.1 vs fuse_z_A 244.1, Δ 8.0 CI [-14.7, 48.0]; fp_B vs kn_B Δ 23.8 CI [-4.0, 54.0]. These are suggestive at best, not evidence.
- Do **not** claim small ≈ large unless L7 actually runs against external pretrained peptide/chemistry LMs under the same feedback budget. That result is pending.
- Do **not** claim target-biology learning from H4b few-label gains unless beating NN/FP-k. Current result says the gain is analog lookup.

**How to make it more novel/innovative**

1. Make M2 the centerpiece: require an **anchor-compound protocol** with k = 3/5/10 anchors per lab/assay and show leave-labs-out improvement over no-offset, source-ID-only, and pooled models.
2. Make M4 edit-based rather than molecule-based: predict **signed edit effects** in held-out labs and held-out scaffolds, not just absolute property. This is closer to medicinal chemistry practice and less likely to be solved by generic LMs.
3. Make M5 real: show separate learning curves for symbolic memory, neural memory, and combined memory; include shuffled-label feedback and data-matched one-shot controls.
4. Add a **hard “no retrieval” / “retrieval only” / “retrieval + LM residual” decomposition**. If IH-LM cannot beat retrieval-only, then the LM is ornamental.
5. Report module utility under strict regimes: leave-labs-out, family-disjoint, stereoisomer-within-scaffold, low-data sources, unseen monomer sets.

---

### (b) Family-disjoint matched-decoy cyclic-peptide benchmark with typicality/no-target validity gates

**Closest real prior art**

- **DUD-E**: Mysinger et al., 2012, *Journal of Medicinal Chemistry*, property-matched decoys for virtual screening. Known to have decoy bias; I am confident DUD-E exists, but not citing specific bias papers unless needed.
- **LIT-PCBA**: Tran-Nguyen et al., 2020, *Scientific Data*, designed to reduce artificial enrichment in virtual screening benchmarks.
- **DEKOIS**: Vogel et al. / Bauer et al. [UNVERIFIED exact citation], property-matched decoy benchmarking for docking.
- **MUV**: Rohrer and Baumann, 2009, *Journal of Chemical Information and Modeling*, designed to reduce analogue bias.
- **PDBbind and cleaned/split variants** exist, but exact “CleanSplit” reference in packet is [UNVERIFIED].
- Peptide-specific binding benchmarks likely exist in fragments — RFpeptides, protein-peptide complex sets, cyclic peptide docking sets — but the packet’s claim of a family-disjoint matched-decoy cyclic-peptide benchmark remains only partially searched.

**What is genuinely new**

- The benchmark idea may be useful if framed narrowly: **cyclic-peptide-specific, target-family-disjoint, matched-decoy retrospective recovery with explicit ligand-only/no-target validity gates**.
- The validity gate itself is a strength. The packet correctly identifies that if compound-only classifiers separate positives from decoys, zero-shot target claims are invalid.
- The control-adjusted rule — arm must beat strongest no-target/typicality/control baseline — is a good methodological contribution.

**What must NOT be claimed**

- Do **not** claim a clean benchmark. Your V3 says no benchmark passes cleanly:
  - Analysis I: C3 Morgan-count no-target control AUROC 0.584 [0.533, 0.636], not clean.
  - M2 invalid: C1 0.665, C2 0.690, C3 0.676.
  - M invalid: C3 0.315 [0.279, 0.352], below chance but still separable, so invalid.
  - M3 “not achievable” without collapsing power/families.
- Do **not** claim zero-shot family-held-out validity except under the explicitly caveated control-adjusted rule.
- Do **not** imply decoy matching solved ligand bias. Your own controls show it did not.
- Do **not** claim broad target generalization with 46 targets / 26 families if chemical-series bias remains and many targets have few cyclic compounds.

**How to make it more novel/innovative**

1. Reframe as a **benchmark failure/audit paper component**: “we attempted property/typicality matching and found cyclic-peptide positives remain compound-separable.”
2. Add **decoy-generation diagnostics**: report which features still separate positives: MW, length, ring topology, N-methyl count, halogens, O-fraction, charge, monomer novelty, macrocycle closure.
3. Add **hard negative types** separately: inactive cyclic peptides from same target/family; same-source inactive analogs; shuffled target labels; close analog decoys; property-matched non-binders.
4. Publish the gate as the contribution, not the benchmark’s cleanliness.
5. Make “control-adjusted AUROC” primary: score = arm AUROC − max(no-target controls), with cluster bootstrap CIs.

---

### (c) Stereo-resolved within-scaffold ranking protocol

**Closest real prior art**

- Experimental cyclic peptide stereochemistry/N-methylation permeability work exists. I am confident in broad examples such as Rezai et al. work on cyclic peptide permeability/chameleonicity and N-methylation; exact 2006 citation details are [UNVERIFIED].
- White et al. cyclic peptide permeability/N-methylation work is mentioned in packet; exact citation is [UNVERIFIED].
- ML papers using CycPeptMPDB and chirality-aware encodings exist [specific names in packet are UNVERIFIED].
- Chirality-aware molecular fingerprints and stereochemical SMILES are standard.

**What is genuinely new**

- The possible novelty is a **protocol**, not the biological fact: within-flat-scaffold or within-stereoisomer-group ranking, with a fixed seeded revealed/target split per group, explicitly avoiding the leave-one-out artifact.
- The correction about blind model within-group Spearman is important and strengthens the work. A leave-one-out group-mean predictor giving exactly −1.0 is a serious trap; documenting and fixing this is valuable.
- A stereo-resolved metric across cyclic peptide stereoisomers/N-methyl variants could be publishable as an evaluation contribution if paired with strong chirality-aware baselines.

**What must NOT be claimed**

- Do **not** claim “stereo matters” as new. It is known experimentally.
- Do **not** compare only against chirality-blind Morgan fingerprints. Your own audit says chirality-aware fingerprints improve overall Spearman by about 0.05 and within-group ranking must use a corrected split.
- Do **not** use the old within-group Spearman numbers as stereo evidence: blind −0.386 vs chiral +0.259 is explicitly not interpretable.
- Do **not** imply aggregate gains will be large. The baseline error analysis shows stereo-aware fingerprints improve random CV Spearman 0.713 → 0.766 and grouped 0.663 → 0.712: meaningful but modest.

**How to make it more novel/innovative**

1. Define groups rigorously: same flat structure, same sequence/topology with stereocenters/N-methyl positions varying, same source when possible.
2. Use a **single revealed/target split per group** and evaluate ranking only among target members.
3. Include baselines:
   - chirality-blind Morgan GBM,
   - chirality-aware Morgan GBM,
   - descriptor GBM with chirality/N-methyl features,
   - nearest-neighbour within group,
   - group-mean revealed reference,
   - IH-LM without stereo tokens.
4. Report paired order accuracy and cliff detection, not only Spearman.
5. Stratify by group size, source, N-methyl changes, D/L flips, and residue substitutions.

---

### (d) In-house hybrid vs larger pretrained peptide LMs compared inside a feedback loop

**Closest real prior art**

- Closed-loop molecular design / active learning exists.
- Molecular/peptide pretrained models exist.
- Comparisons of LLMs vs fingerprints on molecular property prediction exist; ChemBERTa is a real example of a transformer-based molecular representation model.
- LLM sample efficiency on small chemistry tasks is a known topic; specific packet-mentioned works such as Jablonka 2024 are [UNVERIFIED in detail].
- I do not know a clear prior paper that compares a cyclic-peptide-specific hybrid LM against larger peptide/chemistry LMs **inside the exact same retrospective feedback loop**. That part may be relatively novel, but only if run cleanly.

**What is genuinely new**

- Equal-information comparison inside a loop is the strongest novelty candidate:
  - same revealed labels,
  - same loop budget,
  - same acquisition rules,
  - same controls,
  - same family/lab splits,
  - same contamination audit,
  - same ablation ladder.
- The “small vs large” claim has been corrected to “IH-LM vs external pretrained peptide/chemistry LMs”; this is better and less brittle.

**What must NOT be claimed**

- Do **not** claim this result now. L7 is preregistered but not run.
- Do **not** compare IH-LM with external LMs that are fine-tuned “plainly” if IH-LM gets retrieval, lab offsets, priors, and edit heads. That is not a fair architecture comparison. You need two comparisons:
  1. same-base plain vs same-base + modules, for module attribution;
  2. IH-LM full system vs external plain systems, for practical performance.
- Do **not** claim scale is irrelevant unless large pretrained peptide/chemistry LMs receive the same feedback, retrieval option, and tuning budget.
- Do **not** ignore corpus contamination. Public cyclic-peptide datasets likely overlap with pretraining corpora [UNVERIFIED extent].

**How to make it more novel/innovative**

1. Make the headline: **“In feedback-limited cyclic-peptide ranking, explicit lab calibration and analog-aware residual learning dominate pretraining scale.”** Only if supported.
2. Include a contamination table for every external checkpoint: pretraining corpus, date, known inclusion of ChEMBL/CycPeptMPDB/literature peptide data [UNVERIFIED until audited].
3. Force equal-information arms:
   - frozen zero-shot,
   - fine-tuned on revealed labels only,
   - same retrieval context,
   - same loop acquisition,
   - same compute/label budget.
4. Treat cost as secondary. Performance first; cost-adjusted claims are easy to game.

---

## PART B. EVALUATION

### Ranked issues and concrete fixes

#### 1. Fatal current issue: benchmark validity gate fails

Your own V3 says no clean zero-shot/family-held-out benchmark exists. M3 is not achievable without losing almost all positives/families. Analysis I is “not clean” because no-target Morgan C3 AUROC is 0.584 [0.533, 0.636]. M2 is invalid. M is invalid.

**Fix**

- Make the validity failure explicit in the abstract/results if included.
- For any zero-shot target result, report **control-adjusted performance**: model must beat max(C1, C2, C3, B0–B4). If it does not, state no evidence of target-conditioned learning.
- Do not call any result on these benchmarks “valid zero-shot generalization” without the caveat.

#### 2. Fatal for central claim: L7 large pretrained comparator loop is not run

The central claim is IH-LM vs larger pretrained peptide/chemistry LMs in a loop. This is pending. Without it, the paper cannot claim the main result.

**Fix**

- Run the minimum L7 matrix:
  - fingerprint GBM,
  - chirality-aware GBM,
  - descriptor GBM,
  - nearest-neighbour,
  - atom LM / IH-LM base plain,
  - IH-LM full,
  - at least two external pretrained peptide/chemistry LMs if licensing allows.
- Use the same revealed labels and same acquisition budget.
- Freeze all hyperparameters before scoring.

#### 3. Leakage through analog series is the default explanation

H4b shows NN to revealed compounds is extremely strong:
- k=5: NN AUROC 0.753 [0.715, 0.789]
- k=10: 0.822 [0.784, 0.856]
- k=25: 0.869 [0.835, 0.899]

Nothing beats NN; FP-k is essentially tied. This means few-label gains are mostly analog lookup.

**Fix**

- Make NN/FP-k the primary baseline for H4b.
- Add analog-distance strata: exact stereosibling removed, close analog, medium analog, remote analog.
- Report model gain over NN within each stratum. If gain only occurs in close analogs, do not call it transfer.

#### 4. Pretrained comparator contamination is unresolved

External peptide/chemistry LMs may have seen ChEMBL, CycPeptMPDB, public cyclic-peptide papers, or exact sequences/SMILES.

**Fix**

- For each checkpoint, report training corpus and cutoff [UNVERIFIED until documented].
- Exact-match and near-match scan:
  - canonical SMILES,
  - stereo-stripped SMILES,
  - flat scaffold,
  - monomer sequence,
  - target/assay text if available.
- Run a contamination-controlled subset excluding any plausible overlaps. If impossible, mark comparator contamination as [UNVERIFIED] and avoid strong claims.

#### 5. Fold filters and family-disjoint splits are necessary but insufficient

Pfam-family disjointness does not prevent ligand-series leakage, target-paralog similarity, assay/source effects, or property-matched decoy bias.

**Fix**

- Report all split axes:
  - target family,
  - source/lab,
  - scaffold/flat structure,
  - monomer-set cluster,
  - stereo group,
  - publication.
- Use nested grouping where possible. If impossible, state which leakage remains.
- For binding tasks, add “leave-chemotype-out within family” if enough data exist.

#### 6. Series/label leakage in retrospective loop

Within-source Regime A has substantial near-duplicate inflation:
- 22.9% same fingerprint as initial peptide,
- 21.7% same flat structure,
- 60.7% same stereo-free scaffold.

Regime A can be reported, but not as generalization.

**Fix**

- Headline Regime B / scaffold-shifted / leave-labs-out, not Regime A.
- In Regime A, label as “series interpolation”.
- Report hit provenance: which source, which scaffold cluster, which publication.

#### 7. Leave-labs-out should be primary, not secondary

The packet says grouped CV Spearman ≈0.67–0.71 but leave-labs-out ≈0.30. That is the real generalization problem.

**Fix**

- Make leave-labs-out the primary split for permeability/property claims.
- Include anchor-calibration tests at k = 3, 5, 10.
- Compare:
  - no source term,
  - source ID only,
  - anchor random effect,
  - source-normalized labels,
  - descriptor-only K_phys.

#### 8. H4b few-label design is good but must not overstate biology

The packet already says the gain from k labels is analog lookup, not target biology. That is correct.

**Fix**

- Keep k = 0, 5, 10, 25.
- Report all-items and contamination-controlled subsets.
- Include “revealed-nearest-neighbour” and “revealed-only FP-k” as hard baselines.
- Add target-family cluster bootstrap, not compound bootstrap.

#### 9. Statistics: bootstrap unit and multiplicity need tightening

You mention source-cluster bootstrap and family-cluster bootstrap. Good. But multiple comparisons are abundant: modules M1–M5, ladder rungs, k values, regimes, targets, seeds, metrics.

**Fix**

- Predefine one primary endpoint per aim:
  - loop yield in leave-labs-out/scaffold-shifted replay,
  - H4b AUROC control-adjusted at k=5 or AULC across k,
  - stereo within-scaffold paired ranking.
- Use cluster bootstrap at the highest dependency unit:
  - source/publication for permeability,
  - target family for binding,
  - scaffold/series for analog tasks.
- Adjust secondary tests with Benjamini-Hochberg or clearly label exploratory.
- Do not select “best ladder rung” on dev seeds and then report the same seeds as confirmatory. Use nested dev/test seeds or frozen rung selection.

#### 10. The 90% non-inferiority margin is arbitrary and likely too permissive

“Yield ≥90% of strongest large model” might be reasonable operationally, but the margin needs justification. If absolute yields are low or noisy, 90% can hide meaningful differences.

**Fix**

- Justify 90% in terms of cost/experimental throughput.
- Also report absolute difference with CI.
- Require both:
  - ratio lower CI > 0.90,
  - absolute loss not worse than a pre-specified practical threshold.
- If the best large model is weak, non-inferiority is uninteresting.

#### 11. Power is unclear

You have many CIs crossing zero in L5. Thirty seeds do not solve source clustering if sources/families are few.

**Fix**

- Report effective sample size by cluster, not compound count.
- Power analysis should be cluster-based:
  - number of sources,
  - number of target families,
  - number of independent scaffold series.
- If underpowered, avoid null-as-equivalence claims.

#### 12. Retrospective-only limitation must be prominent

Retrospective replay can test ranking known compounds. It cannot prove prospective generation, novelty, developability, FTO freedom, synthesis success, or wet-lab hit rate.

**Fix**

- Put this limitation in abstract/discussion.
- Say “selection/ranking among known public compounds,” not “designs new peptides,” unless a prospective round occurs.

#### 13. Missing controls

Minimum missing or not-yet-scored controls:

- chirality-aware GBM as default, not optional;
- descriptor GBM / K_phys-only;
- NN retrieval-only;
- shuffled-label feedback;
- data-matched one-shot;
- random acquisition;
- source/lab-only model;
- typicality/no-target controls for every benchmark;
- same-base ablation ladder;
- contamination-controlled subset;
- leave-labs-out anchor calibration;
- planted-signal positive control for each adapter/scorer.

**What a skeptical reviewer would reject**

- Any IH-LM superiority claim without L7 external LM results.
- Any zero-shot target generalization claim on invalid benchmarks.
- Any “knowledge helps” claim from L5 because CIs include zero.
- Any “loop improves the LLM” claim if data-matched one-shot equals loop or shuffled-label feedback improves.
- Any “stereo-aware LM advantage” claim not beating chirality-aware GBM and corrected within-group protocol.
- Any “generation” claim from retrospective replay.

---

## PART C. RED TEAM

### What will go wrong

1. **IH-LM will not beat nearest-neighbour retrieval in H4b.** Current baselines are already very strong. Most “learning” will be interpolation within congeneric peptide series.
2. **IH-LM will not beat chirality-aware GBM/descriptor GBM on permeability.** The baseline is strong: grouped Spearman around 0.71 for chirality-aware fingerprints, and descriptor full model around 0.67.
3. **Knowledge modules will not show significant lift.** L5 knowledge/fusion arms have wide CIs crossing zero. Existing KB coverage is thin: 73 statements, 12/793 targets covered, many generic pharmacophore statements.
4. **Lab/source effects will dominate.** Leave-labs-out performance is reportedly ≈0.30, far below grouped CV. Without anchor calibration, pooled learning may mostly learn source identity.
5. **Validity-gated benchmark will remain invalid.** V3 already concludes M3 is not achievable. Positive cyclic peptide binders form chemotype series, so compound-only controls will keep separating positives.
6. **Large pretrained peptide/chemistry LMs may underperform for boring reasons.** Not because IH-LM is better, but because fine-tuning data are tiny, tokenizers mishandle ncAAs, or pretraining corpora mismatch cyclic peptides.
7. **Alternatively, large LMs may dominate because of contamination.** If they have seen ChEMBL or literature peptides, apparent superiority may be memorization.
8. **Module attribution will fail.** If all gains come from M3 retrieval or M2 source offsets, the “LM” contribution is minimal.

### Simpler explanations of positive results

- **Analog lookup:** H4b already shows NN AUROC up to 0.869 at k=25. Any LLM matching this may just be a soft nearest-neighbour model.
- **Lab effects:** Source offsets and source-specific chemotypes can explain high retrospective performance.
- **Typicality/decoy bias:** No-target controls above chance mean a model can recover positives by recognizing “looks like a cyclic peptide binder” rather than target biology.
- **Physchem priors:** TPSA, HBD, N-methyl count, logP, and related descriptors explain much permeability signal. An LLM may be rediscovering descriptors.
- **Duplicate/stereoisomer leakage:** Regime A has heavy near-duplicate overlap. Even grouped splits can leave close analogs.
- **Selection metric artifacts:** Yield curves can be dominated by one large source or one easy series.
- **Hyperparameter/rung selection:** Choosing the best module combination after seeing dev seeds can create apparent gains.

### What you are overclaiming

- “In-house hybrid cyclic-peptide LLM” is currently a specification, not a result.
- “Knowledge-prior fusion” is currently not empirically supported.
- “Family-disjoint matched-decoy benchmark” cannot be called valid without caveats.
- “Loop-native” is a design aspiration until loop updates beat one-shot and shuffled-label controls.
- “Comparable to larger pretrained LMs” is pending.
- “Stereochemical resolution” is only credible against chirality-aware baselines and corrected within-group splits.
- “Generation” is outside the evidence base.

### Results that likely will not replicate

- Any large Regime A gain depending on near-duplicates.
- Any knowledge gain from thin KB rules across unseen targets.
- Any zero-shot binding recovery on a newly cleaned benchmark.
- Any apparent target-family transfer if no-target controls are not subtracted.
- Any source-pooled permeability result when moved to leave-labs-out or a new lab.
- Any module gain selected from the same seeds used for final reporting.

### Cheapest decisive experiment that could falsify the central claim

Run a **minimal H4b / leave-labs-out decisive bakeoff**:

- Dataset: frozen Analysis I H4b plus permeability leave-labs-out subset.
- Arms:
  1. NN to revealed compounds,
  2. chirality-aware/descriptor GBM,
  3. IH-LM base plain,
  4. IH-LM full M1–M5,
  5. one external pretrained peptide/chemistry LM fine-tuned plainly,
  6. shuffled-label IH-LM full,
  7. data-matched one-shot IH-LM full.
- k = 5 and 25 only.
- Primary endpoint: cluster-bootstrap AUROC/yield gain of IH-LM full over max(NN, GBM, external LM), control-adjusted by no-target controls.
- Falsification: IH-LM full fails to beat NN/GBM at both k values, or shuffled/data-matched controls match it.

This is cheaper and more decisive than training v5 or expanding the benchmark.

---

## PART D. THREE HIGHEST-VALUE CHANGES FOR THE NEXT WEEK

1. **Run the smallest fair L7 bakeoff now.**  
   Freeze the arms, include NN/chirality-aware GBM/descriptor GBM/IH-LM plain/IH-LM full/one or two external peptide-chemistry LMs, and evaluate under the same H4b and leave-labs-out protocols. Without this, the central paper has no central result.

2. **Reframe benchmark claims around validity-gate failure and control-adjusted scoring.**  
   Stop trying to present M3 as a clean benchmark. State that clean matched decoys were not achievable, and make the contribution the audit protocol plus control-adjusted rule. This is more honest and more defensible.

3. **Make retrieval-only and lab-offset-only ablations unavoidable.**  
   Add explicit arms: NN only, source/lab offset only, K_phys only, retrieval + lab offset without LM, and IH-LM residual over them. If IH-LM cannot beat these, the conclusion should be “analog lookup and lab calibration explain performance,” not “LLM loop works.”
