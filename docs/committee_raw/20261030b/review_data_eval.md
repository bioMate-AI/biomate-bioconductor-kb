# Independent data / evaluation-design review (read-only, CPU, recomputed from raw files)

Reviewer scope: CycPeptMPDB loop data, binding_affinity_v1 + retro_recovery frozen benchmark (I, M, M2, M3, H4b, gates C1-C3), loop regimes A/B/C/L, and the five named docs. All numbers below were recomputed by me unless marked [REPORTED] (read from a project doc, not recomputed) or [UNCERTAIN]. Scratch scripts are in the session scratchpad (a1..a6, b1..b4, g1); no repo file was edited. Machine was heavily loaded, so only one expensive experiment (n = 1 seed) could be run.

## 0. Bottom line
1. The benchmark is family-disjoint only at the level of Pfam-Jaccard target labels. It is not protein-disjoint: the same UniProt subunits, and even the same antigen (alphav-beta6), appear in different "families" and different folds, with the same compounds. This is the only CRITICAL finding; it directly touches the alphav-beta6 subset and the "no alphav-beta6 training signal" blind rule.
2. The validity-gate failure (C3 = 0.584) is NOT caused by this leakage: I reran C3 with compound-, accession- and Tanimoto-purged training sets and it stays 0.578-0.588. The negative finding ("no benchmark passes the gate") is robust to the leaks I found; the reported *arm and baseline numbers* are not guaranteed to be.
3. The loop gain in regime A is partly produced by evaluation design: transductive within-source standardisation (single-seed check: about half the A-regime gain disappears when source statistics are estimated from labelled peptides only), and near-duplicate density between initial set and pool (42% of the pool has Tanimoto >= 0.9 to one of only 100 initial peptides). Regime C does not remove near-duplicates. Regime L is the only clean regime for held-out-lab claims.
4. Label construction in I has a perfect-ish censoring confound (63.6% of inactives are ">" censored; 0% of positives) that no gate control looks at.
5. Several headline data-profile numbers are correct (6,960 / 2,460 / 71%); two are not the numbers of the frozen benchmark (17,120 / 851; "45 sources").

## 1. Ranked findings

### CRITICAL

**F1. "Family-disjoint folds" are not protein-disjoint (target identity leaks across folds).**
Evidence (`a2.py`, `a3.py` on targets.csv, folds_v1.csv, pair_labels, items_*):
- Family = connected components of Pfam-set Jaccard >= 0.67 over "targets", where a target is the sorted UniProt-accession *set* of an assay row. Complexes and single subunits are therefore different targets with different Pfam sets, so they split. ITGB3 alone = F1aeb1980 (fold 2); ITGAV+ITGB3, ITGA2B+ITGB3, ITGA5+ITGB1, ITGA4+ITGB1, ITGAV+ITGB6, ITGAV+ITGB5 = F21103b9e (fold 3); ITGAV, ITGA2B, ITGA4, ITGA5 alone = Fd0868d62 (fold 4); ITGB5, ITGB6 alone = fold 2. HDAC3 alone fold 2, HDAC3+NCOR1 fold 4, "HDAC1..HDAC11" pooled target fold 2.
- 29 of 775 accessions occur in more than one family; 24 span more than one fold.
- Targets that have a same-accession target in a different fold: 6 of 46 targets in I (ITGB3, ITGA2B+ITGB3, ITGA4+ITGB1, ITGA2B, ITGA4, HDAC6); 9 of 20 targets in M2, covering 44.3% of M2 items (43.6% of positives); 23 of 299 in M (8.8% of items).
- alphav-beta6: target `P06756,P18564` (fold 3) and target `P18564` (beta6 alone, fold 2) have 77 labelled pairs each, 70 shared compounds (66 shared flat structures), 39 positives each in M, 33 shared positives. They are the same data counted twice. The "M / alphav-beta6 targets: 2 targets (2 families)" row in V1 therefore treats one antigen as two independent families, and any arm fitted on "other-family" labelled pairs (S1d profile, rule induction draws, PT, C2/C3 leave-fold-out) sees the twin's alphav-beta6 positives (code: `03_run_arms.py` lines ~178-200 exclude only `fam == F`).
Affected claims: Methods "target-family-disjoint folds"; V1 alphav-beta6 and integrin subset rows; M2 gate (effective independent families < 14); the blind-rule statement in PREREG s3 ("nothing trained may contain alphav-beta6 compounds"); power calculations (family count is overstated for integrin/HDAC groups).
What would change: the alphav-beta6 and integrin results were INCONCLUSIVE/null already, so the *direction* of conclusions is unlikely to change; but the "no alphav-beta6 training signal" premise is false for the fitted arms, and the integrin subset cannot be called held-out.
Fix: build families from the union of accession-sharing first (connected components over shared accessions after splitting complexes into subunits, plus ortholog clustering), then Pfam; re-freeze folds_v2 and re-run gates. Quarantine all beta6/alphav-containing targets as one fold for alphav-beta6 claims.
Uncertainty: I did not rerun the arms; the size of the inflation of S1d/PT on alphav-beta6 is unmeasured.

### MAJOR

**F2. Cross-fold compound and near-duplicate leakage, asymmetric between classes.**
- 1,057 of 14,492 labelled compounds (7.3%) have pairs in more than one fold; 1,007 of 13,161 flat structures. In items_I: 351 compounds in >1 fold = 11.6% of rows (matches the draft's 11.6%).
- Nearest neighbour (Morgan r2, 2048 bits, chirality-free) of each item compound among compounds labelled in OTHER folds (`a5.py`): I positives: 11.7% >= 0.99, 15.8% >= 0.90, 26.8% >= 0.80; I inactives: 27.8% / 30.7% / 39.7%. M2 positives: 60.1% >= 0.99, 71.3% >= 0.90; M2 decoys: 91.5% >= 0.99. The classes differ by 10-30 points, so "this compound is known elsewhere" is itself a class signal (the depth baselines B4 partly capture this; M2 matches depth only within +-0 after tightening).
- Gate robustness (my reimplementation of C3, `g1.py`; registered number reproduced exactly): registered 0.584 [0.533, 0.636]; compound-disjoint 0.580 [0.530, 0.630] (3.2% training rows dropped); + accession-disjoint 0.578 [0.532, 0.626]; + Tanimoto >= 0.9 purge 0.583 [0.538, 0.631]; + >= 0.8 purge 0.588 [0.542, 0.637] (5.8% dropped). So the gate failure survives all purges. The draft's compound-disjoint rerun is confirmed; accession and near-duplicate purges have not been reported and are now done.
Affected claims: zero-shot PT 0.539 and S1d numbers (training rows overlap test compounds); "I is family-disjoint but not compound-disjoint" (correct but incomplete: also not accession- or analog-disjoint). Not affected: the gate verdict.
Fix: report compound/accession/Tanimoto-0.8 disjoint versions of every I and M2 number as the primary, not as a sensitivity.

**F3. Label construction confounds in analysis I (relation censoring, assay mix, thresholds).**
- Relations (items_I joined to pair_labels): positives 96.9% exact "=", 0.4% "<"-type; inactives 36.4% exact, 62.4% ">" (63.6% any ">"), 0% for positives. Per-target AUROC of a "relation is censored" indicator averages 0.186 (i.e. 0.81 inverted; range 0.0-0.45 over 46 targets).
- Assay types (pair-level): IC50 62.7% of inactives vs 54.0% of positives; Ki 11.2% vs 18.3%; EC50 20.3% vs 13.8%; Ki/Kd indicator mean per-target AUROC 0.567. Positives pool functional EC50 potency with binding Ki; pair label = median over mixed assay types.
- Thresholds: positive = median <= 1 uM, inactive = > 10 uM, 1-10 uM dropped (5,701 of 30,310 pairs = 18.8%). Inactive value_nM median 26 uM, max 1e8 nM. 80.6% of I items are positives; 21 of 46 targets have < 30 inactives (min 19).
- Interpretation [UNCERTAIN, not testable with the stored columns]: ">" inactives are most plausibly single-concentration or selectivity-panel results for compounds designed against other targets, so I partly tests "designed for this target" vs "designed for something else", consistent with C3 0.58 and NN 0.75-0.87. Document/year identifiers are not in the stored table, so a document confound cannot be tested; the one proxy I tried (CHEMBL-id order, 8 families only) gave 0.387, weak and low-coverage.
- Source (BindingDB-only / ChEMBL-only) is NOT a confound: family-mean AUROC 0.520 / 0.461.
Affected claims: "same-target measured inactives" framing of I; the usable-benchmark discussion. The gate has no relation, assay-type or document control, so it cannot tell a compound-intrinsic signal from a measurement-regime signal.
Fix: add controls C4 (relation/censoring indicator), C5 (assay type), C6 (document id; carry ChEMBL document ids into the table); report I restricted to exact "=" inactives with Ki/Kd only; consider a censoring-aware label (inactive only if "=" > 10 uM).

**F4. Transductive within-source standardisation in the permeability loops.**
- Code: `run_loop_prior.py`: `y = source_normalize(y_raw, srcs)` standardises each source using ALL its peptides (initial, pool, unrevealed); `thr` is the 0.90 quantile of that vector; training targets are `y[L]` (these standardised values). A deployed loop cannot know the mean/sd of a lab it has barely sampled.
- Coverage: sources 41 (20 with >= 20 peptides; 176 peptides in smaller sources pooled as "other"). Share of the pool lying in sources with fewer than 5 initial labels: regime A 14.4%, regime B 84.8% (10 seeds); mean |mu_init - mu_full| / sd_full over covered sources 0.21 (A), 0.13 (B). So in B a causal learner has no offset estimate for most of the pool, yet the leaky version receives it for free.
- Single-seed experiment (seed 0, fp-greedy, 10 rounds x 50, chirality fingerprints, hits defined on the full-data standardised label as in the paper), `b3.py` [INDICATIVE ONLY, n = 1, crude causal rule: source z-score from labelled peptides if >= 5 of that source else global labelled z]:
  regime A: leaky 251 hits, causal 151, raw pooled labels 64, random 47 (gain over random 204 -> 104, about half lost);
  regime B: leaky 31, causal 35, raw 10, random 31 (no detectable effect in this seed either way).
  The causal arm is handicapped by noisy statistics, so this is an upper bound on the damage; the 30-seed A result (+186) may be overstated by up to roughly 0.5x, B is not informative from one seed. [UNCERTAIN: needs >= 10 seeds; I could not afford them on the loaded machine.]
- [REPORTED] `l5_label_audit.json`: re-estimating source mean/sd from a 30% subsample flips 99.7 of 6,960 hit labels (Jaccard 0.867); this measures hit-definition sensitivity, not the training-signal leak above.
- Regime L evaluates held-out labs with their own statistics (disclosed as a "transductive convention"). Within-source Spearman is invariant to that; pooled E-AUROC/EF5 with a global threshold is not, so L numbers that use `thr` depend on it.
Affected claims: P1 (+186.3 loop - random in A), C regime (+163.4), B/L if pooled thresholds are used, and every knowledge-arm contrast (K signals are also source-standardised on all data; label-free, so no label leak, but the scale matches the leaky labels).
Fix: causal normalisation (statistics from revealed labels only, shrinkage to global with anchor compounds) as the primary arm; report leaky normalisation as an oracle ceiling; or define hits by a fixed raw-label rule within each source's own deployment-time statistic.

**F5. Regime leakage between initial set, pool and evaluation set (10 seeds A/B/C ... 5 seeds measured).**
Means over seeds 0-4, 800 pool peptides sampled per seed, nearest neighbour vs the 100 initial peptides (Morgan r2 bits, chirality-free) (`b2.py`):
| regime | pool same flat structure | same stereo-free scaffold | NN Tanimoto >= 0.9 | >= 0.8 | median NN |
|---|---|---|---|---|---|
| A (in-distribution) | 21.7% | 60.9% | 42.2% | 69.3% | 0.873 |
| B (scaffold-shifted) | 0.0% | 0.0% | 3.4% | 14.6% | 0.533 |
| C ("near-duplicate aware") | 0.0% | 51.3% | 26.9% | 62.6% | 0.841 |
| L loop pool vs init | 35.6% | 82.1% | 66.0% | 90.4% | 0.940 |
| L held-out labs vs ALL training labs | 0.2% | 5.1% | 0.8% | 3.5% | 0.549 |
Reproduces the audit log's A (22.9 / 21.7 / 60.7) and B (0 / 0 / 0). Findings: (a) A is interpolation within analogue series; 100 labels cover 42% of the pool at >= 0.9. (b) C removes identical flat structures but not analogues (26.9% still >= 0.9, 62.6% >= 0.8), so labelling C "near-duplicates removed" and citing it as a sensitivity check that A's gain is not near-duplicate-driven is too strong (+163.4 retained, as expected). (c) B is scaffold- but not lab-shifted: the pool still contains the same top-2 laboratories. (d) L is clean across the held-out boundary (stereoisomer siblings, 0.2%; analogues >= 0.9, 0.8%) but its *selection pool vs initial set* is as leaky as A, so L yield claims (+165 vs random feedback) are series-interpolation yields; only the E (held-out-lab) ranking contrasts are cross-lab. (e) L is irregular: seed 0 holds out all 18 eligible labs (2,385 peptides, 34%), others 6-17 labs; 25-34% of peptides.
Fix: add regime C2 with Tanimoto >= 0.8 purge (or Butina clusters at 0.7) between pool and initial set; add a lab-shifted B (initial from labs X, pool excludes X); keep E-only for L cross-lab claims; fix the held-out set size per seed.

**F6. Data-profile numbers: two wrong/mis-scoped, three correct.**
- Correct: 7,027 PAMPA rows (>-9.99) -> 6,960 unique Structurally_Unique_ID (67 duplicate rows); 6,958 unique canonical SMILES [REPORTED, plausible]; 2,460 flat structures; 70.6% of peptides sit in flat groups of size >= 2 (412 groups, max 116), matches "71%"; chirality-blind Morgan fingerprints give 2,380 distinct values (chiral: 6,583); PAMPA range -9.46 to -3.90; raw mean -5.75, SD 0.79 (0.793); `Permeability` differs from `PAMPA` on 73 rows; between-source variance share 27.0% vs 27.7% quoted (minor).
- Wrong: "45 sources" (stratification doc s) for the 6,960 set: I count 41 sources (42 among PAMPA rows, 56 in the whole file); 15 sources with >= 30 peptides and 20 with >= 20 are correct.
- Mis-scoped: the draft (Benchmark for binders) says "17,120 peptide macrocycles across 851 targets ... frozen ... target-family-disjoint folds". The frozen benchmark has 16,195 compounds / 14,599 flat structures; 793 targets with labelled (pos/inactive) pairs; 14,492 compounds with labelled pairs; 24,583 labelled pairs (20,562 positive, 4,021 inactive, 5,701 gray excluded). Upstream I confirm 36,102 cyclic rows, 17,911 unique cyclic SMILES, 923 target keys (ledger D17) and 16,991 SMILES after null-target/affinity filters; I did not recompute how 17,120/851 arise [UNCERTAIN]; they are not the frozen benchmark's counts. The manuscript v4 line "351 with >= 5 positives; 30 with >= 20 inactives" also differs from the frozen eligible_M = 344 (flat-distinct) and eligible_I = 46.

### MINOR
- m1. 21 CycPeptMPDB unique IDs were measured in >1 source; the loader averages across sources and assigns the first row's source (67 duplicate rows). Inflates between-lab consistency of a few high-profile peptides (cyclosporin etc.) and mislabels source for standardisation.
- m2. Affinity table contains 4 rows <= 0 and 29 rows > 1e9 nM (up to 1.0e20) among cyclic rows: these unit/parse errors were excluded, but they show parse errors exist; in-range unit errors cannot be excluded [UNCERTAIN].
- m3. Fold structure is highly unbalanced by construction: family F997e29c2 (class A GPCR Pfam PF00001, 130 targets) is one fold (28% of compounds, 14 of 46 I targets, 43.8% of I positives); two families hold 76.5% of I positives (I verified; docs say 77%). Family-mean aggregation protects against this, but the leave-fold-out controls train on folds that are missing the largest family when it is tested.
- m4. Atom-LM pretraining corpus membership differs by class in I (inactives 72.3%, positives 49.8%); handled by the contamination-controlled subset, but corpus membership as a secondary control passed, which suggests the control's family-mean AUROC hides a per-item imbalance.
- m5. M2 tolerance was tightened from (0.05, 1) to (0.02, 0) because baselines were outside 0.45-0.55, dropping 99% of eligible positives (188 of ~17.8k kept; 20 targets, 14 families): disclosed, but M2 is an isolated-chemotype subset, so its failure (typicality 0.665) tells little about decoys in general.
- m6. Seeds in the loops are replicate initial sets on one fixed library; intervals over seeds do not generalise to new laboratories (the draft says so).
- m7. All frozen files verify against FROZEN_HASHES (9/9 sha256 match, folds_v1.csv matches its json): reproducibility of the frozen artefacts is good.

## 2. Answers to the numbered questions
1. Family-disjoint? Pfam-Jaccard 0.67 components are used (rejecting an earlier chaining rule; verified: 317 families, largest 130 targets, all PF00001). Not disjoint at protein level (F1), 7.3% of compounds and 11.6% of I rows cross folds, and 16-31% of I items have a >= 0.9 analogue in other folds (F2). Stereoisomer sibling handling: within a target, siblings are collapsed by flat key; across targets/folds they are not (1,007 flat structures in >1 fold). I ignored but did not test same-compound-under-different-identifier beyond canonical isomeric SMILES (compound_id = sha1 of isomeric SMILES of largest fragment, so salts/tautomers/charge-state variants that RDKit does not canonicalise identically would be separate IDs) [UNCERTAIN].
2. Positives/decoys consistent? Thresholds are uniform (<= 1 uM / > 10 uM), but relation, assay type and censoring are strongly class-confounded (F3); size, charge and RGD baselines are near chance (V1: 0.49-0.54), so those trivial confounds are controlled. In M-type designs decoys are positives of other families, hence unlabelled-possible binders; I-type inactives are mostly censored values. Trivial-confound passability: the passability that exists is via censoring/measurement regime and analogue lookup (NN 0.62 on I; 0.914 on M), not size/charge/source.
3. Loop regimes leakage and standardisation: F4, F5. Quantified.
4. Data profile: F6.
5. Robustness: gate verdict robust (0.578-0.588 under all purges). Loop claim P1 (A) probably overstated; P2/P3 (B, L) conclusions (not met, not detected) would not become positive by removing leaks (leaks favour the loop), so the null/negative statements are conservative. alphav-beta6 subset conclusions: unaffected in direction (inconclusive), but not "held-out".
6. Missing designs: see s4.

## 3. Verified correct (explicit list)
- Frozen hashes (9/9) and fold file hash.
- 5-fold family-grouped assignment is deterministic and matches folds_v1.json counts; fold sizes 4524 / 2941 / 2941 / 2941 / 2940 compounds.
- I = 9,432 items, 7,600 positives, 46 targets, 26 families; M2 = 3,486 items, 188 positives, 20 targets, 14 families.
- Registered C3 value reproduced exactly by independent reimplementation (0.584 [0.533, 0.636]) and compound-disjoint 0.580 [0.530, 0.630].
- Regime B scaffold/flat disjointness (0.000); regime A near-duplicate rates (22.9/21.7/60.7 reproduced as 21.7/60.9).
- 6,960 / 2,460 / 70.6% / 2,380 / label range / 73-row label discrepancy.
- Source (DB) is not a confound; size/charge/RGD fractions are balanced (RGD in I positives 1.8% vs decoys 3.4%, build log).
- Power statement: 2 families hold ~77% of I positives, and the gate has ~0.11 MDE with 26 families (reported; arithmetic consistent).

## 4. Missing evaluation designs a skeptical peer will ask for
1. A protein-level/ortholog-clustered split and an accession-disjoint fold for all I/M2/H4b numbers; a hold-out of alphav-beta6 AND alphav/beta6 subunit and complexes together.
2. Compound-disjoint and Tanimoto-0.8-disjoint (or Butina) versions as primary results; analogue-distance strata for zero-shot arms (done for H4b only).
3. Negative controls on the loops: planted-null label shuffle exists; add (a) label-permutation within source with leaky vs causal standardisation, (b) an "oracle-source-offset" arm to price the leak, (c) a pool-only-duplicate control (random pick restricted to analogue series).
4. Cross-lab replication that is not lab-confounded: L has 11 sources and irregular held-out sets; pre-fix the held-out count, report per-lab, and use lab-level intervals; add an assay-matched replication (Caco-2 / RRCK) beyond PAMPA.
5. Temporal split (year) for both datasets: Year exists in CycPeptMPDB (2006-2024); document/year absent in the binding table.
6. Censoring-aware and assay-stratified binding benchmark (exact Ki/Kd only; inactive only if exact > 10 uM).
7. Prospective or blind new data: none exists; at minimum a blind set of recently published (post-freeze) alphav-beta6 and cyclic-peptide permeability results deposited with hashes before scoring.
8. Noise ceiling: dataset-specific duplicate-measurement floor for PAMPA (exists in L7) and for binding (none); report skill as fraction of the ceiling.
9. Multiplicity: the K_phys contrasts (54 dependent) and the gate secondary controls are exploratory; keep that labelling.

## 5. Concrete fixes (priority order)
1. Rebuild families from accession-union components (+ orthologs), re-freeze folds_v2, quarantine alphav/beta6; re-run gates and H4b (CPU-only, hours).
2. Add C4-C6 (censoring, assay type, document) to the gate; report I-exact-Ki/Kd.
3. Make causal source standardisation the primary loop arm; keep leaky normalisation as an oracle; re-run A/B/C/L at 30 seeds.
4. Replace regime C with Tanimoto >= 0.8 purge; add a lab-shifted B.
5. Correct manuscript numbers: 16,195 compounds / 793 targets (frozen) or state 17,120 / 851 as pre-filter; 41 sources not 45; describe folds as "Pfam-family-disjoint, not protein-, compound- or analogue-disjoint".
6. Fix the held-out-lab count per seed in L.

## 6. Uncertainty register
- F4 effect size: n = 1 seed, crude causal rule; direction credible (the pool in B is 85% uncovered), magnitude not.
- F1 inflation of S1d/PT/NN on alphav-beta6: not measured.
- 17,120 / 851 provenance: not recomputed.
- Compound identity beyond canonical isomeric SMILES: not tested.
- Document-level confound: untestable with stored columns.
- Near-duplicate rates in b2 use a random sample of 800 pool peptides per seed and 5 seeds (A/B/C), standard error about +-1-2 points.
