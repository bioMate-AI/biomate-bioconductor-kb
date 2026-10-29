# Frozen start: chirality-aware vs chirality-blind vs physchem GBM — pre-registration (written 2026-10-28 ~23:00 CDT, before any new-seed run)

File date follows the owner's naming request. Owner approval: "aware-versus-blind frozen comparison ok". Code: `research/guangzhou_all_atom/cyclic_llm/loop_retro/frozen_ab/` (planted_run.py, aggregate_frozen_ab.py, make_ud_frozen_ab.py, test_frozen_ab.py).

## 1. Question and what was already seen
In the committed L7 replay (10 seeds), regime L, the **frozen** arm of the chirality-aware GBM scored 201.3 hits [192.0, 211.4] and the chirality-blind GBM 214.3 [209.3, 219.6]; physchem GBM 210.8. The aware-minus-blind paired difference over seeds 0–9 is −13.0 hits (SD 14.1, SE 4.5; regimes A/B `frozen_sub`: −0.9 (SD 5.4) and −2.5 (SD 5.2)). **These numbers were read before this pre-registration was written**, and the contrast was chosen because of them. Seeds 0–9 therefore cannot confirm themselves: a **replication check on the 30 new seeds (10–39) alone is a pre-registered secondary output** (section 5).

What "frozen" is: a GBM ensemble fitted **once on the 100 initial labelled peptides** (training-lab peptides only in regime L) and never updated; it ranks the pool and its top 50 per round are picked for 10 rounds (500 picks). It is **not** a pretrained or foundation model. (The phrase "pretrained start" used in earlier notes for this arm is wrong; it is a 100-label learner.)

## 2. Definitions (unchanged code; no label, split or threshold is altered)
- Learners: **aware** = backend `gbm`, `FP_CHIRAL=1`; **blind** = backend `gbm`, `FP_CHIRAL=0`; **phys** = backend `gbm_physchem` (10 RDKit descriptors).
- Regimes A (in-distribution), B (scaffold-shifted), L (leave-labs-out, seeded held-out laboratories; `setup_L`, defined for any seed). Splits (init, pool, evaluation slice) depend on regime and seed only, so they are identical across learners; the aggregator asserts this.
- Yield = total hits over the 10 rounds, hit = source-standardised label ≥ the global 90th percentile, exactly as in L7 (**transductive** per-source standardisation: unrevealed labels enter the standardisation and the hit threshold; learners are affected identically, but absolute yields inherit that convention).
- Endpoint arm per regime (the committed headline arm): L → `frozen` (full pool); A and B → `frozen_sub` (150-candidate subsets). The other arm is reported descriptively.
- Seeds 0–39, paired by seed.

## 3. Hypotheses
H0 (equivalence): |aware − blind| ≤ 10 hits. H1: aware and blind differ (two-sided; the direction seen in seeds 0–9 is negative, but no direction is pre-specified). Same two statements for physchem − aware and physchem − blind.

## 4. Contrasts, intervals, multiplicity, margin
- **Primary family (Holm over 3):** aware − blind in regime L (`frozen`), regime A (`frozen_sub`), regime B (`frozen_sub`). Regime L is the pre-designated headline; Holm treats the three symmetrically.
- **Secondary (Holm over 6, labelled exploratory):** physchem − aware and physchem − blind in A, B, L.
- **Descriptive only:** the other arm in each regime; paired difference of the initial held-out AUROC (`auroc_E0`); replication on seeds 10–39 alone; source-cluster bootstrap; lab-exclusion jackknife.
- **Interval types are always labelled:** `t_mean` (t-interval of the mean of paired differences over seeds), `boot_mean` (percentile bootstrap of the mean over seeds, B = 10,000, seed derived from the data), `cluster_source` (bootstrap over the sources the picks come from, of the summed per-source difference in hits, seeds averaged within source; this is where source clustering enters, because yield is a per-task total with no source index). The seed-level intervals treat seeds as independent; in regime L they are **not** independent lab draws (a few labs are held out in most seeds), so they are anti-conservative; the jackknife that drops each held-out lab in turn is reported next to them.
- **Equivalence margin: ±10 hits** (of 500 picks), fixed by the owner's directive before any new-seed run. Caveat fixed now: in regime B the frozen yield is about 24 hits and in A about 78, so ±10 is 40 % and 13 % of the level; an equivalence conclusion there is weak evidence and will be reported as such, not as "no difference".

## 5. Decision rule (applied mechanically by `aggregate_frozen_ab.py`)
Per contrast, with n = number of paired seeds (40 planned):
- **DIFFERENT**: Holm-adjusted two-sided paired-t p < 0.05 **and** the 95 % percentile-bootstrap CI and the 95 % t-interval both exclude 0. If additionally both 90 % intervals lie inside (−10, 10) the label is `DIFFERENT_BUT_WITHIN_MARGIN`.
- **EQUIVALENT**: both 90 % intervals (t and bootstrap) lie inside (−10, 10) and DIFFERENT is not met.
- **INCONCLUSIVE**: otherwise.
- **Replication flag (descriptive):** the sign of the mean on seeds 10–39 alone is compared with seeds 0–9; disagreement is reported as a failure to replicate.
Power projection (uses the committed seeds 0–9, so it is conditional on what was already seen): with the paired SD of 14.1 hits in L, SE at 40 seeds is about 2.2 hits; a true difference of −13 would be detected with very high probability, and a true difference of 0 would give a 90 % t-interval of about ±3.7, inside the margin.

## 6. Checks that must pass before any contrast is read
1. **Regression:** for seeds 0–9, every arm present in both the new and the committed task file (`res7f_gbm_aware`, `res7f_gbm_blind`, `res7f_gbm_phys`) must have identical per-round hits, picks and final held-out scores, and identical evaluation slice and initial set. Already checked locally for aware/regime L/seed 0 (frozen, frozen_sub) and blind/regime A/seed 0 (frozen_sub): identical. Any mismatch stops the analysis and is reported as an audit problem.
2. **Pairing:** identical initial set and evaluation slice across learners for every (regime, seed).
3. **Planted controls** (seeds 0–9, regimes A and L, aware vs blind only; real splits and thresholds, labels replaced by synthetic ones by `planted_run.py`):
   - *chiral*: label = fraction of assigned CIP centres labelled S (a function of stereochemistry only) + noise; **pass** if the aware − blind 95 % t-interval has a lower bound above 0.
   - *flat*: label = Crippen logP (a function of the 2-D graph only; stereoisomers identical) + noise; **pass** if the 90 % t-interval of aware − blind lies inside ±10 hits.
   If either control fails in either regime the real-data contrasts are reported with that failure next to them and are not read as evidence about chirality.

## 7. Cost and execution (spot only, hard cap USD 2)
44 single-process jobs (36 real = 3 learners × 3 regimes × 4 ten-seed chunks; 8 planted), each about 25 s of feature building plus about 10 s per task (measured locally: 26 s wall, 0.76 GB peak for one seed), run with `xargs -P <vCPU>` on one c5.9xlarge/c6i.8xlarge spot instance (about USD 0.65–0.70/h): about 10 minutes of compute plus about 5 minutes of install and pre-flight, i.e. under USD 0.4; `shutdown -h +120` caps the worst case at about USD 1.4. IAM profile `ecsInstanceRole`, SG `sg-0de9af2d4437a8c90`, AMI `ami-0829b74b2a8c619b7`, 40 GB gp3, tags `project=cyclic-selector`. Results sync to `s3://biomate-nextflow-work/cyclic_peptide/loop_retro/res_frozen_ab/`. The code on S3 (`code7q`) is byte-identical to the repository for `run_l7a.py`, `run_loop.py`, `run_loop_par.py`, `run_loop_prior.py`, `loop_models.py` (sha prefixes checked). No bare `wait`; the instance is terminated at the done flag.

## 8. Not tested here
Other learners (ChemBERTa, atom LM), the loop arms, the causal-standardisation variant, and any claim about generative loops. A significant aware − blind difference in `frozen` yield would show only that, with 100 initial labels, one fingerprint choice ranks a fixed pool differently; it says nothing about which model is "better" at design.
