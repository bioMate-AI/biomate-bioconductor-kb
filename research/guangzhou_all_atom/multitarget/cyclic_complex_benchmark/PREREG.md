# PRE-REGISTRATION: can a sample selector beat the default top-1 pick of co-folding models on experimental cyclic-peptide complexes?

Committed 2026-10-25 BEFORE any structure was generated or scored. Nothing in this directory so far (manifest, stats, README)
ran a co-folding model or looked at a prediction. Later changes go ONLY into the "Amendment log" at the bottom (dated, with reason);
the text above the log is never edited after commit.

## 0. Question and what would count as an answer
Given N samples a co-folding model produces for one cyclic-peptide/protein complex, does a ground-truth-free learned selector S
pick a better sample than what users get today (the model's own ranking)? "Better" = higher fraction of complexes whose selected
sample is DockQ-acceptable. A negative, no-headroom, or within-noise outcome is a valid result and will be reported as such.

## 1. Data
* Source: `manifest.csv` (884 PDB complexes; built from deposited covalent-link records). Deposit date cutoff 2023-10-01.
* EVALUATION set = `set==post` (deposit >= 2023-10-01). Tiers (NOT merged): STRICT = `runnable_strict==1` (32 complexes / 23 receptor clusters);
  CCD = `runnable_ccd==1` (98 / 48; STRICT is a subset of CCD).
* SELECTOR TRAINING set = `set==pre` & `runnable_ccd==1` (405 complexes / 105 receptor clusters). These are in the models' training data
  (leaky for the model, so model samples on them are expected to be easier/over-confident than on post); they are used ONLY to fit S.
* Leakage caveats (stated up front): Boltz-2 training cutoff reported as 2023-06-01 in secondary sources (UNVERIFIED primary; will be re-checked in Stage A
  and recorded in the amendment log). Chai-1 cutoff UNVERIFIED (recall 2021-01). The 2023-10-01 cutoff is kept, so post complexes are after both stated
  dates. Residual leakage is possible through homologous receptors/peptides deposited earlier (receptor-cluster overlap with pre is reported per complex via
  `receptor_cluster_also_in_pre_set`) and through unverified cutoffs. All headline numbers are therefore "post-cutoff by stated dates", not "provably unseen".
* Inputs to the models: receptor chains = chains listed in `receptor_chains` with the full SEQRES (entity_poly canonical sequence); peptide = the deposited entity
  with non-canonical residues as CCD modifications; cyclisation as a Boltz `cyclic: true` (head-to-tail) and/or `constraints: bond` (other closures between
  canonical residues). MSA: receptor via the ColabFold server (`--use_msa_server`); peptide MSA empty. No template, no pocket/contact conditioning, no knowledge
  of the ground-truth pose is given. Chains are renamed to single letters (receptors A,B,..., peptide Z) identically in prediction and ground truth.

## 2. Pilot set (Stage A) — fixed selection rule
Seed 20261025. Among post & runnable_ccd complexes with (sum of receptor-chain lengths + peptide length) <= 750 tokens (cost/memory cap on the 16-24 GB spot GPUs):
(a) one random complex for each STRICT receptor cluster, (b) then random complexes from distinct non-strict CCD-tier clusters (not already used) until 40 total.
If fewer than 40 qualify the pilot is smaller; the number is reported. Pilot complexes are post-cutoff evaluation complexes, so pilot results (default/oracle/ipTM
calibration) must not be used to tune S; S is trained on pre only.

## 3. Samples
Per complex per model: 25 samples nominal (5 seeds x 5 diffusion samples). If the model's trunk is deterministic given the seed (to be checked in the smoke test), an
implementation of 25 diffusion samples from fewer trunk passes is acceptable and will be documented as a deviation. Boltz first (version of the image recorded via
`boltz --version`); Chai-1 on the same pilot set where its input can be expressed (what cannot be expressed is documented, those complexes skipped for Chai).

## 4. Metrics (primary and secondary)
Ground truth: RCSB mmCIF, model 1, the single peptide copy used in the manifest, receptor chains as in the manifest, renumbered by label_seq_id so prediction
and truth share residue numbers.
* PRIMARY: top-1 success = DockQ(selected sample) >= 0.23 ("acceptable"); also reported at >= 0.49 ("medium"). Mean DockQ of the selected sample.
  DockQ = DockQ v2 (pip `DockQ`), peptide chain as ligand, interface = peptide vs the receptor chain with the most native contacts (primary interface);
  tie / multi-chain handling documented in code.
* SECONDARY: peptide interface RMSD (DockQ iRMSD), ligand RMSD after receptor-Calpha superposition (DockQ LRMSD), ring-geometry validity of the selected sample.
* Uncertainty: receptor-CLUSTER bootstrap (resample `receptor_cluster40` clusters with replacement, keep all their complexes; 10,000 reps, seed 1), 95% percentile CIs.
  Paired differences use the same resampled clusters for both methods.

## 5. Baselines (per model)
* B0 default: the model's own ranking (Boltz `confidence_score`; Chai `aggregate_score`), top-1 over all samples of the complex — what users get.
* B1 random sample: expected success of a uniformly random sample (analytic mean over samples).
* B2 oracle: best-of-N by DockQ (upper bound; uses ground truth, never a method).
* B3 single-feature selectors (each: top-1 over samples by that feature, sign fixed a priori, not tuned): ipTM (higher better), pTM (higher), interface pLDDT (higher),
  ring strain (lower; closure-bond deviation from ideal + angle deviations), clash count (lower).

## 6. Selector S
Features per sample, all computed WITHOUT ground truth: model confidences (confidence_score, ipTM, pTM, protein-ipTM, complex pLDDT, interface pLDDT, PAE-interface where
available); ring-closure geometry (closure bond-length deviation from ideal per closure type, bond-angle deviations at the two closure atoms, peptide ring planarity
proxy for H2T); steric clash score (count of inter-chain heavy-atom pairs < 2.2 A; peptide-receptor); interface contact density (peptide-receptor heavy-atom pairs
< 5 A divided by peptide length); CONSENSUS: mean pairwise peptide RMSD (after receptor Calpha superposition) to the other samples of the same complex (cluster centrality),
size of the largest pose cluster (greedy clustering of peptide poses at 4 A), and (only if both models pass the stop rule) Boltz-vs-Chai pose agreement. Each feature is used
raw and as within-complex z-score. Candidate learners (fixed hyper-parameters, no search on post): L2 logistic regression (C=1) predicting DockQ>=0.23, and a small
gradient-boosting classifier (max_depth=2, 100 trees, learning rate 0.1). Selection between the two is by receptor-cluster-grouped CV top-1 success on PRE only; the
chosen one is trained on all PRE and applied to POST exactly ONCE. The post set is never used for model selection, feature selection, or thresholds. Ties broken by model
confidence_score.

## 7. Claim rule
S is called "best" ONLY IF, on the POST set, its top-1 success (DockQ>=0.23) exceeds the strongest of {B0, B3 selectors} AND the paired cluster-bootstrap 95% CI of the
difference excludes 0; required separately for the CCD tier and (reported separately) the STRICT tier. "Strongest baseline" is the max-top-1 baseline measured on the same
post set (this is deliberately conservative: it picks the best of 6 baselines ex post). Anything weaker is reported as "no improvement" (point estimate <= strongest
baseline) or "improvement within noise" (point estimate > baseline but CI includes 0). The STRICT tier (n=32, 23 clusters) is below 30 independent clusters only
marginally and is described as underpowered where the CI is wide.

## 8. STOP RULE (Stage A -> Stage B gate)
After the pilot, compute for each model: oracle top-1 success minus B0 top-1 success (DockQ>=0.23) on the pilot. If this is < 10 percentage points (point estimate) for
the primary model (Boltz), there is no headroom for a selector: STOP, write up, spend nothing more. If Boltz passes, proceed to Stage B with Boltz; Chai-1 is included in
Stage B only if it also passes (otherwise the Boltz-vs-Chai agreement feature is dropped). If Boltz fails but Chai-1 passes, the stop rule is still applied to the primary
model (Boltz) and I stop, because the study is defined around the model users run by default; this is reported with the Chai numbers as an observation.
The pilot CI on the gap will be reported next to the point estimate (n~40 so it is wide), but the gate uses the point estimate.

## 9. Stage B (only if the gate passes)
Generate samples for all 98 post CCD-tier complexes, plus as many PRE training complexes as the budget allows, one per receptor cluster first (then additional complexes
per cluster in random seed-20261025 order). Fit S on PRE, evaluate once on POST. Stage C reports: learning curve of S vs number of PRE training clusters, feature
importances, failure analysis (complexes no sample solves), ring-validity statistics (is the predicted cyclic peptide chemically closed: closure atoms within ideal +/- 0.3 A).

## 10. Compute and cost rules
Spot GPU only (`biomate-gpu-spot-queue`, spot compute environment `biomate-gpu-spot-v1`); never on-demand. Budget cap USD 120 total. Cost log in `cost_log.md`: instance-hours x
a CONSERVATIVE spot price (USD 0.85/h for g6.2xlarge-class, the highest observed in the last 24 h; real g4dn spot prices were ~0.33/h) + startup overhead, stated assumptions.
Stop if the projected total would exceed the cap. A smoke test on 2-3 complexes with a written prediction precedes any fan-out.

## 11. Deliverables / verdict vocabulary
Scripts, tests, `results.json`, README section, result tables with CIs, `cost_log.md`, and a verdict from exactly one of: POSITIVE (claim rule met in the CCD tier),
NO-HEADROOM (stop rule triggered), NO-IMPROVEMENT (headroom exists but S does not beat the strongest baseline or is within noise), with a note on what a publishable claim would need.

## Amendment log
- 2026-10-25 A1 (before any pilot sample was scored): implementation facts found in the smoke test / source. (a) Image = Boltz 2.2.1 (Boltz-2), T4 16 GB spot GPUs. (b) Samples: 25 diffusion samples from ONE trunk pass (seed 0) instead of 5 seeds x 5, as allowed by s3; trunk determinism is being checked (see README) - if the trunk turns out stochastic this is a deviation that reduces sample diversity. (c) DockQ default mode is PRIMARY; the capri_peptide variant is computed as SECONDARY only. (d) Boltz `cyclic: true` only sets the positional-encoding period and enforces no covalent bond; ring-closure validity is therefore measured per sample (closure bond within ideal +/-0.3 A) and used as a feature, as already pre-registered in s6. (e) Boltz-2 structure cutoff 2023-06-01 is confirmed only by secondary sources (NVIDIA NIM model card, search summaries); primary paper unfetched -> still UNVERIFIED primary. (f) Chai-1 arm: see README for what was expressible.

## Amendment A2 (2026-10-26) — Stage B design, written BEFORE any Stage B sample is generated
Facts established since A1: (i) pilot (26 complexes ran): default top-1 80.8 %, random 80.3 %, oracle 96.2 %, gap 15.4 pp [3.8, 30.8] — the stop rule did not trigger (`results/PILOT_RESULT.md`);
(ii) Boltz-2's component library has 45,227 entries; 51/884 complexes carry a missing code (`results/ccd_check.json`); (iii) the earlier "98 runnable post-cutoff" claim was wrong.
**Selection (`scripts/stageB_select.py`, seed 20261026):** TRAIN = pre-cutoff, runnable, ≤ 600 tokens, ≤ 3 complexes per receptor cluster → 317 complexes / 157 clusters. TEST = all eligible post-cutoff → 117 complexes / 56 clusters
(52 complexes / 34 clusters have a receptor cluster absent from TRAIN: the "novel-receptor" subset, reported separately). 24 test complexes were already scored in the pilot; 2 (`8XIP_6`, `8XIR_6`) are regenerated after the YAML fix.
**Method S (`scripts/selector.py`):** within-complex z-scored features → L2 logistic regression (C = 0.3, fixed in advance) predicting DockQ ≥ 0.23; pick = argmax within complex. Features exclude every ground-truth column (asserted).
**One-shot protocol:** fit on TRAIN only; evaluate ONCE on TEST; no feature/hyper-parameter changes after seeing TEST. Secondary (labelled secondary): grouped-by-receptor-cluster CV within TEST; ablations (consensus-only, ring-only, confidence-only).
**Disclosure:** the first 26 test complexes were examined in the pilot, including a descriptive screen of single-feature selectors (56 candidates, so optimistic) — selector design was frozen before Stage B data, but it was not blind to that pilot.
**Claim rule (unchanged):** S is "best" only if its top-1 success (DockQ ≥ 0.23) on TEST exceeds the strongest of {default, ipTM, pTM, interface-pLDDT, ring-strain, clash-count} with a paired receptor-cluster-bootstrap 95 % CI of the difference excluding 0 — on ALL test complexes AND on the novel-receptor subset. Anything weaker is reported as "no improvement" / "improvement within noise".
**Predictions (written now):** P(generation completes for ≥ 90 % of the 410 complexes) ≈ 75 % (risks: OOM near 600 tokens, further CCD surprises); P(S beats the default with CI excluding 0 on ALL test) ≈ 30 %; on the novel-receptor subset ≈ 15 %;
most likely outcome = point-estimate gain of +2 to +8 pp, CI spanning 0. Default ≈ random is expected to replicate (P ≈ 65 %). Oracle − default on the full test set expected 10–20 pp.
Cost estimate ≈ 41 GPU-h ≈ $15–25 (cap $120; spent so far < $10).

## Amendment A3 (2026-10-26) — compute strategy only; claim rule, selection and predictions UNCHANGED
The first Stage B submission (35 spot jobs x ~12 complexes) failed: AWS evicted the spot `g4dn.2xlarge` nodes (us-west-2c) within ~1 min of launch, 93 attempts were used, jobs exhausted their 3 retries, 10 new complexes finished (37/437 incl. pilot). No result was inspected.
Change: job definition `cycbench-cofold` revision 2 (retry attempts 10, same container), and 12 longer jobs (4 test x 23 complexes first, 8 train x ~38) so fewer nodes are requested at once. The driver skips finished complexes, so retries lose at most one complex + the 8 GB cache restore.
If the training set cannot be fully generated, the selector is fit on whatever fraction completed (reported), never on test data; the TEST set must be complete for the one-shot evaluation, else the claim is reported on the completed subset with that stated.

## Amendment A4 (2026-10-26) — compute cutoff on test size; made BEFORE any Stage B test result was scored or inspected
Measured Spark timings: ~3.5 min (≈250 tokens), 18 min (621 tokens), 43 min (1,069 tokens); cost grows super-linearly, so the 4 largest test complexes (1,836 / 2,316 / 2,390 / 3,545 true tokens) would take hours each and block the rest.
Change: TEST is restricted to complexes with ≤ 1,200 true tokens → 113 test complexes (4 excluded, listed in `results/stageB_selection.json: test_excluded_over_1200_tokens`). TRAIN is restricted to ≤ 600 true tokens (the 34 training complexes above 600 are dropped; the 16 GB AWS GPUs cannot run them).
This is a compute limitation, stated as a limitation in any write-up; it is not outcome-dependent (no result has been scored). Claim rule, baselines, selector and predictions unchanged.

## Amendment A5 (2026-10-27) — evaluation trigger; made BEFORE any Stage B sample was scored
To fix the timing of the one-shot evaluation (preprint v1 target date: 2026-10-27), the selector is fit and evaluated once, at the earlier of: (a) all 113 capped test complexes have finished generation, or (b) 6 h after this commit. TRAIN = every capped train complex (≤600 true tokens) finished at that moment; no further train complexes are awaited. Test complexes still missing at trigger (b) are excluded and listed by ID with reason "not generated in time" (reported, not silently dropped). Claim rule, baselines, selector and disclosure are unchanged.
Disclosure: at commit time 98/113 test and 135/283 train complexes were generated and none was scored.

## Amendment A6 (2026-10-27) — selector variant S1; made AFTER train-only diagnostics, BEFORE any test score was opened
Scores for TEST complexes exist on disk but have not been read by any analysis (no evaluation, no feature screen, no summary). Everything below used TRAIN only.
Train-only finding (135 complexes): 94 have every sample acceptable, 4 have none, only 37 are "mixed"; the original selector S0 fits all samples, so 98 complexes add label noise and no ranking information.
Grouped (receptor-cluster) 5-fold CV on train with S0 gave top-1 success 82.2 % vs default 83.7 % vs random 83.7 % (oracle 97.0 %).
Change: add variant S1 = same features and model, trained only on mixed complexes (fit option `mixed_only`).  S1's regularisation C is chosen by receptor-cluster 5-fold CV on TRAIN only, repeated over 5 fold seeds, from the fixed grid {0.01, 0.03, 0.1, 0.3, 1}: choose the C with the highest mean top-1 success at DockQ >= 0.23; ties -> smaller C.
Reporting: BOTH S0 (as originally registered) and S1 are evaluated once on TEST. The primary claim rule (CI lower bound > 0 vs the strongest baseline, on all test complexes AND on novel receptors) is applied to S1; S0 is reported alongside as the originally registered selector. If S1 does not clear the rule the result is reported as not supported; no further selector variants will be tried on this test set.
Multiplicity disclosure: two selectors are evaluated on the same test set; the claim is made for S1 only.
