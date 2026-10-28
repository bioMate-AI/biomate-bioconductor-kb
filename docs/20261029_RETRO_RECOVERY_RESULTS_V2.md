# Multi-target retrospective recovery study — V2 results (2026-10-29)
Extends `docs/20261028_RETRO_RECOVERY_RESULTS_V1.md`. Pre-registration: PREREG §13 (A5: M2, generalised arms, coverage layer; committed `76c0ed766` before any M2 scoring) and §14 (A6: folds, `470b4f5fc`). Results files: `retro_recovery/results/results_V2_{I,M2,M}.json` (V1 files unchanged). Baselines/arms scored with the same code and seeds as V1 (identical numbers for the shared arms).

## 1. Headline
**No arm is SUPPORTED on the registered rule (lower 95 % bound > 0 for both AUROC and EF5 vs the strongest baseline).** Primary analysis I (46 targets, 26 families): S1d physchem-profile (fitted on other-family data) 0.565 [0.505, 0.622] vs strongest baseline B3_nn_neg 0.620 (−0.055 [−0.134, +0.020], INCONCLUSIVE); rule-induction arms 0.512–0.518 (NOT_SUPPORTED); RGD/KB gates ≈ 0.50 because they are constant on 43–46 of 46 targets. The memorisation shortcut is closed in M2 (below) but M2 is small (20 targets, 14 families, 188 positives), and the arms are at chance there.

## 2. M2 (matched decoys): baseline gap closed, power low
Baselines: B3_nn_neg 0.530 (M: 0.914), B4_depth_neg 0.495 (0.748); size/charge/RGD 0.49–0.51. S1a rules: AUROC 0.519 [0.500, 0.542] (−0.010 [−0.032, +0.015] INCONCLUSIVE) but EF5 +0.18 [+0.02, +0.38] vs the strongest EF5 baseline — a single-metric nominal hit from an RGD gate that is non-constant on only 6 of 20 targets; not claimed (the registered rule needs both metrics; ties dominate EF5). S1b-KB / contaminated KB-active similarity: constant on all 20 targets (0/20 coverage; no KB-mapped target survives M2). S1d-profile: 0.367 [0.257, 0.503], below chance; hypothesis (not verified): M2 decoys are binders of other targets, so a model trained on binder-vs-inactive ranks matched decoys above isolated-chemotype positives — a property of the decoy design, to be tested with an inactives-based variant.

## 3. Coverage per arm (targets with a non-constant score / total; items scored 100 % everywhere)
| arm | I (46) | M2 (20) | M (299) |
|---|---|---|---|
| S1a RGD rules | 3 | 6 | 16 |
| S1b KB gate (experience_kb) | 0 | 0 | 4 |
| S1b-leaky KB actives (diagnostic, contaminated) | – | 0 | 2 |
| S1b-induction (10 SMILES predicates, rule_induction.induce) | 46 | – | – |
| S1c-induction (31 real chemistry predicates, same learner) | 46 | – | – |
| S1d physchem-profile (18 descriptors, logistic, other-family fit) | 46 | 20 | 299 |
Knowledge-derived arms (KB gates) have coverage ≤ 6 % of targets and add nothing where they apply; the arms with full coverage are *fitted* (induction, profile), not knowledge. The learner `rule_induction.induce` requires every active to satisfy a rule: with 5 diverse actives it returns short or empty conjunctions, so its scores are near-constant ties — expanding to 31 predicates (S1c) did not change that (0.512 vs 0.518). Induced rules per family: `results/induced_rules_S1{b,c}_induction.json`.

## 4. Other tables
I strata and integrin subsets: all INCONCLUSIVE or NOT_SUPPORTED (see json). M (diagnostic only, strongest baseline 0.914): all arms NOT_SUPPORTED; S1d-profile 0.433.

## 5. Components ran vs bypassed
Unchanged from V1 §4 (`results/component_log_V2.json`): ran `experience_kb.all_entries`, `rule_induction.induce`, target_kb examples (leaky diagnostic); added sklearn logistic profile (fitted, not a BioMate component). Not run: chain `loop.py`/`loop_batch.py` → `physics_batch` → `execution_grader` (S2: plan only), workflow DB docking/QSAR/Boltz/OpenFE workflows, `medchem_kb*`, `acceptance_gate`/`pharmacophore_knowledge`/`knowledge_liability_flags` (HELM input), multi-source data layer.

## 6. S3 and S2 readiness
S3: `run_s3.py --name <model> --scores <csv> [--round k]` (verified with a planted-signal file: SUPPORTED on I and M2; the contamination-controlled subset removes 5 of 46 I targets' worth of compounds' labelled items and drops M2 to 16/20 targets, INCONCLUSIVE — power loss is real); partial folds supported, `folds_scored` reported; loop-replay scores can be passed per round. S2: subset frozen (`data/s2_pilot_subset.csv`, sha256 `f2189a2b…4522`), plan and cost bound in `docs/20261029_AVB6_S2_PHYSICS_PILOT_COST_PLAN.md`; **not executed**.

## 7. Caveats / not verified
M2 positives are an isolated-chemotype subset (A5). Pfam-Jaccard families are not sequence-identity families. I has 26 families (2 of them hold 77 % of positives; family-mean aggregation prevents that dominating). S1d on M2 below chance is unexplained beyond the stated hypothesis. The EF5 hit on M2 S1a was not adjudicated beyond noting ties and 6/20 coverage.
