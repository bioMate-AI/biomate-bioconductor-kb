# Referee report: cyclic-peptide feedback-loop manuscript (main draft 20261029 and reframed v2 20261030)
Reviewer role: independent senior referee (comp. chem / ML for drug discovery). Read: main draft (Abstract, 1-8, App. headings; sections 4.4-4.10 and appendices only skimmed), v2 in full, REVIEW_BRIEF. Artifact spot checks run against committed JSON (below).

## 0. Verdict
- Main draft: REJECT (as written). A model/instrument paper whose model comparison has no result, with a lab-notebook structure. 
- v2: MAJOR REVISION (borderline reject at a selective venue). It is the stronger and only defensible framing, but its one positive result is self-declared inflated and its benchmark fails its own gate.
- Single most damaging flaw: the evidence base is not frozen and the headline measurements carry a known, unquantified leak. The loop-vs-random result uses transductive source standardisation and hit thresholds (single seed: 251 leaky vs 151 causal vs 47 random; the causal arm "is running"); the L7 aggregate already flipped direction/significance once (key collision); all K_phys-vs-shuffled numbers are [REGEN-K] and must not be cited; confirmatory seeds do not exist. A referee cannot evaluate a paper whose headline numbers the authors say must not be cited.

## 1. Claims: supported vs overclaimed
Spot-checked 12 numbers against committed files (all match unless noted):
1. l5_aggregate.json: loop-random A +186.3, spread 158.5-209.0, boot-mean 181.1-191.5; random 49.8; B +22.2 (-1.6 to 44.1; 17.7-26.5), random 30.1. OK.
2. l5_aggregate PICK_SOURCE_MEANS: Townsend 346.1 (loop) vs 206.1 (random). OK.
3. l5_label_audit.json: 368/697 hits = 0.528. OK.
4. l7_aggregate gbm_aware|L yield: loop-random 186.1 (179.5-192.9), -frozen 47.3 (34.6-58.2), -shuffled 117.7. OK. Blind 165.0/13.2/79.5. OK.
5. contrasts_cluster aware L: loop_sub-frozen_sub +0.075 (0.037-0.115); loop_sub-shuffled_sub +0.034 (-0.063-0.121). OK. Physchem +0.155 (0.071-0.241). OK. K_phys-kshuf physchem L -0.035 (-0.069 to -0.007). OK.
6. SHA-256 e5da79e9... matches l7_aggregate.sha256 and the file. OK.
7. validity_gate_I.json: C1 0.503 (0.458-0.550), C2 0.559 (0.499-0.619), C3 0.584 (0.533-0.636). OK. (Note C1/C2 use 25 families, C3 26; text says 26 throughout.)
8. h4b_baselines.json: zero-shot PT 0.539 (0.478-0.605); FP-k at k=5 0.750. OK.
9. kb_audit/lolo_group_permutation_null.json: median rho 0.252, group p 2e-4, 10/21 labs p<0.05. OK.
10. c2_audit A_ext: learn-random|famdisjoint +0.143 (0.102-0.197); learn-nn|famdisjoint +0.002 (-0.018-0.047). OK. But omitted: learn-nn|full background +0.046 (0.003-0.069) excludes 0, and learn-nn|none -0.077. The "learn = lookup" statement is true only under the family-disjoint background; it should be stated as a function of background.
11. 5-of-15 mean-based knowledge variants (l5 lower_mean_gt0) OK.
12. kshuf_paired_audit aware A K_phys-none yield +4.7 OK.
Numerics are clean; the problems are interpretation and design, not transcription.

Supported: (a) a GBM loop selects far more top-decile peptides than random in-distribution (as an upper bound); (b) fingerprint control on analysis I is at 0.584, i.e. the gate fails; (c) nearest-neighbour lookup is as good as fitted models at k=5-25 on that analysis; (d) per-lab K_phys correlation is nonzero offline.

Overclaimed or unsound:
- "Loop beats random" is the wrong headline contrast. Regime L: frozen model alone yields 201.3/500 vs random about 62.5 (248.6-186.1); about 75% of the "+186 vs random" is the pretrained initial model, not feedback. The physchem learner's loop-frozen yield is +4.9 (-4.4 to 14.1): no feedback yield benefit at all. Abstract leads with +186.
- "Pre-registered claim not met" in regime B rests on the 95% spread of per-seed differences (a prediction-interval quantity), not a CI of the mean difference. With the CI of the mean (17.7-26.5) the loop clearly beats random (30 -> 52 hits, ~75% relative). The text uses spread to reject the loop, then boot-mean to say the rule "ties"; the interval type is chosen per conclusion. State one test, and a TOST/non-inferiority margin for "ties".
- "Gain is mostly one laboratory" is shown only by pick counts (346/500 from Townsend vs 206 random). No hits-by-source decomposition is given, so it is not shown that the gain comes from locating Townsend (Townsend may simply be the most predictable series; 69% of picks vs 53% of hits).
- Discussion (i) says the in-distribution margin "survives removing near-duplicates"; regime C removes identical structures only (26.9% of pool still Tanimoto >= 0.9, per the authors) and the abstract says the margin is likely overstated. Direct contradiction.
- Regime L ranking evidence (P3): the abstract's positive instance is loop-minus-frozen, but the status note says the frozen arm is zero by construction and a sanity check, not a test. The valid feedback control (shuffled labels) fails in L for the aware learner (+0.034, -0.063 to 0.120) and for blind. The remaining positive (physchem, +0.155) is in a learner where random feedback beats the loop (A, B): internally incoherent. Percentile cluster intervals over 6-11 clusters are, by the authors' own note, anti-conservative and t-intervals remove several of the excluded-zero claims; ▲ marks in the v2 table and the abstract still rely on them.
- Ranking contrasts use *_sub arms (loop_sub, frozen_sub, shuffled_sub) whereas yield contrasts use full arms; the "yield vs ranking" dichotomy (core of the Discussion) compares different protocols. Not explained in the text.
- "Unexplained" physchem K_phys negatives: not unexplained. K_phys (TPSA, HBD, logP, Veber-type) is collinear with the features of a physicochemical-descriptor learner; a knowledge channel that duplicates inputs, shuffled, acts as noise injection. K_phys itself is textbook medicinal chemistry (Veber, White 2011 N-methylation), so "post hoc rule" and "real association" are unsurprising.
- Few-label result (P5) is built on analysis I, which the paper shows is confounded: censoring indicator alone AUROC 0.206 (i.e. 0.794 inverted), 63.6% of inactives censored vs 3.1% of positives; secondary proxy o_frac AUROC 0.391 (CI 0.303-0.471) also excludes chance. NN-on-labelled-same-target-analogs "beating" fitted models on this set is expected (within-series SAR, well known) and tells nothing about transfer. This claim should be deleted, not reported "relative".
- Lab-offset/anchor result: 21 peptides in >=2 labs; kill criterion met; planted gain only +0.100. A null on a design that cannot be powered (best power 0.34) is not a finding.
- IH-LM numbers (M3 rho 0.525 vs 0.70 etc.) are from a synthetic planted world; they should not appear in a results-bearing paper.
- LLM-prompting arm: n_pairs 3-4, own rule requires >= 8 pairs; noninferiority status "inconclusive (power)". Tagged VERIFIED in the abstract; it is not evidence of anything.
- Pre-registration is overstated: validity gate applied after M2 failure was known, margin +/-0.05 and 98.3% flag chosen post hoc, rules added after first result, interval type switched. Call it "protocol with disclosed amendments".

## 2. Internal inconsistencies
1. Main abstract/Title option 2/Intro/Hypotheses H1-H5/Related work frame an untested IH-LM comparison ("Two aims, one paper"); results contain none. v2 states "we do not propose a new architecture" yet keeps C5-C6 in the contributions table and ~900 words of IH-LM/P0/corpus-filter/edit-leak material in its "planned follow-up".
2. [REGEN-K] notice forbids citing any K_phys-minus-shuffled number; v2 prints the full column with ▼ marks, and the main Discussion states "K_phys never better than shuffled knowledge with laboratories resampled" as a finding. Same for "2 of 3 GBM backends" and "15/54, 9/54, Holm 1/54".
3. Notice says percentile cluster intervals are anti-conservative; Abstract/P3 use them as primary.
4. Frozen arm: "sanity check, not a test" (notice) vs lead evidence in P3 and the abstract.
5. Amirahmadi Table 6 (GP 0.897/0.804): [LIT-SUMMARY] in main, [LIT-VERIFIED] in v2. One of them is wrong. Also main says only Amirahmadi was read in primary text; everything else (PepBenchmark ID/venue, Klamt et al. numbers, LLMNN, Liu et al.) is summary/snippet level.
6. Discussion "survives removing near-duplicates" vs regime C not near-duplicate-free vs abstract "likely overstated".
7. Aware, blind and physchem learners disagree in sign/significance across most contrasts; the abstract nevertheless draws a single "mainly selection yield" conclusion.
8. Family counts 25 vs 26 across controls; "Pfam-family-disjoint" yet integrin/alphavbeta6 acknowledged not held out; the title of v2 says "binding data" while the gate-failed analysis is the only binding evidence.
9. v2 abstract is ~600 words and cites 20+ numbers; the main text is the notebook (commit hashes, 'workstream', 'coordinator message', spend table, licence table) - not a manuscript.

## 3. Publishability and venues
- Main: not publishable. Three papers in one (loop controls; benchmark audit; model/system plan), none complete; the title promises a pre-registered model test with no data. After IH-LM/ladder results exist it could be a different paper (ML4Mol-type workshop at NeurIPS/ICML, then a journal). Unverifiable; I will not predict acceptance.
- v2: stronger. A concise negative/controls paper: "gains in retrospective cyclic-peptide loops are lookup + lab concentration; a no-target validity gate fails every benchmark we built". Plausible venues I am confident exist: Journal of Chemical Information and Modeling (benchmark/validation articles), Journal of Cheminformatics, Digital Discovery (RSC). NeurIPS Datasets & Benchmarks would require releasing a usable validated benchmark/tool, which this does not have (no benchmark passes). A workshop paper (ML for molecules/drug discovery) is the realistic near-term fit. To be competitive, v2 must cut to ~6-8 pages of results, run the missing analyses below, and present one library only if a second is added.
- Note the paper's own limits: one permeability library (two labs ~2/3 of peptides), one binding collection, GBM learners, development seeds. Generality is the principal referee objection at JCIM.

## 4. Novelty vs prior art (confident items only; [UNVERIFIED] where unsure)
- Retrospective-benchmark hidden bias: DUD-E bias (Chen et al. PLoS One 2019, cited); LIT-PCBA memorisation (Huang et al., arXiv 2025 [UNVERIFIED id]); Sieg, Flachsenberg, Rarey, JCIM 2019 "In need of bias control" (exists; not cited) - the no-target/"null model" control is established practice there. The gate as an equivalence test with an UNVERIFIABLE state is a refinement, not a new idea.
- Inter-laboratory noise: Kalliokoski et al. PLoS One 2013 (mixed IC50 data) and Landrum & Riniker JCIM 2024 (combining Ki/IC50 from different sources is noisy) exist; neither is cited, and they pre-empt "lab effects bound achievable performance". The PROTAC inter-lab ceiling preprint (Klamt, Nejdl, Tang; details [UNVERIFIED]) is the closest direct analogue and the draft correctly concedes it; but the draft does not run the equivalent same-compound ceiling on its own 21 shared peptides.
- Peptide benchmarks: PepBenchmark (exists; closest; id/venue [UNVERIFIED]); CycPeptMPDB (Li et al. JCIM 2023, exists); Liu et al. 13-method CycPeptMPDB benchmark [UNVERIFIED]. Novelty vs these is only "lab-held-out + no-target gate + loop replay".
- Tanimoto-kernel GP/ECFP strength: Amirahmadi et al. (cited), GAUCHE (Griffiths et al., NeurIPS D&B 2023, exists, not cited) and Praski et al. (embeddings vs ECFP) all show fingerprint+Tanimoto baselines are hard to beat. Result "lookup is as good" is therefore consistent with, not new relative to, this literature.
- LLM/retrieval + nearest-neighbour: LLMNN-type work (Gupta, Hartford, Liu; [UNVERIFIED] details); MolRAG/MolE-RAG [UNVERIFIED]. Active learning on molecule pools: Graff et al., Chem. Sci. 2021 and the Bayesian optimisation literature (GAUCHE) provide the proper loop baselines (GP + UCB/Thompson) - the paper's loop is a bootstrap HistGBM ensemble, a weak and unusual baseline for BO.
- Claim "we found no study": do not make it; the draft's own survey rated it medium risk.

## 5. Innovation test ("innovation or no publication")
Genuine technique/system contributions (modest):
- Validity gate as two-sided equivalence test over no-target controls with explicit UNVERIFIABLE state (C1). Real but small; margin and flag level chosen post hoc; the authors show it cannot certify even an unbiased benchmark at 14-26 families. Needs a positive control (a benchmark known to be clean passes) and a negative control (a known-biased one fails) to count as a method.
- Evaluation protocol hygiene (C2): lab-cluster bootstrap, within-group split, finding that source-aware standardisation leaks. The leak finding is a real audit contribution once the causal arm is quantified on >=30 seeds.
Audit/negative-result contributions: loop = lookup + lab concentration; every benchmark fails; fusion nulls; K_phys offline association; skill drop to about a third for unseen labs (0.67 -> ~0.22); NN as strong as models. Useful, but each corroborates known literature.
Not contributions (delete or demote): anchor calibration (null, unpowered), T1/T1b fusion (null), T2 (no result), IH-LM scaffold and "ladder" (no performance claim; the authors list backbone, tokeniser, retrieval, shrinkage as non-novel), ihlm_v2 integration, "rewards never become labels" (design principle, standard in RL/verifier pipelines), cost accounting.
What I would delete: Sections 3 (hypotheses), 4.4-4.5 and 4.10 (planned design), IH-LM what-is-it/P0/corpus-filter/edit-prior/contamination text, T2/C4-C6, API-LLM arm, 54-contrast K_phys, spend/licence/decision tables, commit hashes and process language, regime C/D2 sensitivity detail, anchor section (move to one sentence), few-label P5 on analysis I, the Related-work paragraph on PeptideCLM-2 etc. that is not used. Under the "innovation or no publication" criterion, the contribution is a validated audit procedure plus a clean causal re-estimate of what loops buy; that must be the entire paper.

## 6. Analyses a referee will demand
1. Causal-normalisation primary arm (stats from labelled peptides only, hit threshold fixed from the initial/pool-independent reference), >=30 confirmatory seeds, frozen in a registered file; report A/B/L with leaky as ceiling.
2. In-loop baselines that matter: frozen model, NN lookup, K_z/physchem rule, Tanimoto-kernel GP with UCB/Thompson, diversity-matched random, source-matched random (L7m is pending). Cluster CIs for yield, not just ranking.
3. Hits-by-source decomposition of the loop-random gain; leave-Townsend-and-Kelly-out regime (the two labs that hold ~2/3 of peptides are never held out in L).
4. Proper small-cluster inference: t / wild-cluster bootstrap or a mixed model with lab random effect; one multiplicity scheme over the stated family; equivalence margins for all "no effect"/"ties" statements.
5. Noise ceiling: same-compound inter-lab reproducibility from the 21 shared peptides (and Landrum-Riniker style estimate), to bound achievable Spearman across labs and give the 0.22 leave-lab-out figure meaning.
6. Second dataset (another permeability set such as Caco-2/RRCK within CycPeptMPDB; or a small-molecule multi-source ADME set) to claim anything general.
7. Binding: exact-Ki/Kd only analysis (censoring removed), compound-disjoint and protein-disjoint folds as the primary (folds_v2), and positive/negative controls for the gate.
8. Learner strength: a chemprop/Tanimoto-GP or pretrained-embedding learner in the loop, not only HistGBM; otherwise "lookup suffices" is a statement about GBM.
9. Per-source results table with n, hits, loop vs frozen, so readers can see heterogeneity.

## 7. Recommendations
- Main framing: REJECT. Central comparison absent; claims about "Aim A" cannot be reviewed; excess surface area and unresolved leaks; post hoc rules. Resubmission only after IH-LM/ladder produce audited results; otherwise fold into v2.
- v2 framing: MAJOR REVISION. Conditions: (i) causal arm and confirmatory seeds done and frozen, REGEN-K resolved; (ii) correct headline contrast (vs frozen/NN/rule) and one coherent interval policy; (iii) delete P5 and the IH-LM/follow-up material; (iv) add noise ceiling and a second dataset; (v) rewrite the abstract to ~200 words and resolve the inconsistencies in section 2. If (i) and (iv) cannot be done, I would recommend rejection for JCIM/J Cheminform and resubmission as a workshop paper.
