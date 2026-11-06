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

## 9. Results (aggregated 2026-10-29 00:10 CDT by `aggregate_frozen_ab.py`; file `research/guangzhou_all_atom/cyclic_llm/loop_retro/results/frozen_ab_aggregate.json`; all numbers below are copied from that file by script)

**Checks first.** Regression vs the committed files (seeds 0–9, every arm present in both): aware|A 10/10; aware|B 10/10; aware|L 20/20; blind|A 10/10; blind|B 10/10; blind|L 20/20; phys|A 20/20; phys|B 20/20; phys|L 20/20 identical, 0 mismatches (`regression_ok=True`). Pairing violations: 0. Run: 440 task files (360 real + 80 planted) from two spot instances (the first was reclaimed by AWS after 18.7 min with 432/440 files; the resumed run skipped finished tasks and completed the rest).

**Mean frozen yield (hits of 500 picks, n = 40 seeds):** aware|A 86.28; aware|B 21.98; aware|L 191.35; blind|A 86.8; blind|B 23.1; blind|L 207.72; phys|A 90.53; phys|B 26.82; phys|L 207.32 (L = `frozen`, A/B = `frozen_sub`).

**Primary family (Holm over 3). Interval types: t_mean / boot_mean.**

| contrast | mean diff | SD | t_mean 95 % | boot_mean 95 % | t_mean 90 % | p_holm | outcome |
|---|---|---|---|---|---|---|---|
| aware − blind, regime A | -0.525 | 5.756 | [-2.4, 1.3] | [-2.4, 1.1] | [-2.1, 1.0] | 0.567 | **EQUIVALENT** |
| aware − blind, regime B | -1.125 | 4.369 | [-2.5, 0.3] | [-2.5, 0.2] | [-2.3, 0.0] | 0.223 | **EQUIVALENT** |
| aware − blind, regime L | -16.375 | 23.413 | [-23.9, -8.9] | [-23.6, -9.2] | [-22.6, -10.1] | 0.000227 | **DIFFERENT** |

Replication on the 30 new seeds only (seeds 10–39 vs 0–9): A: -0.9 → -0.4 (t_mean 95 % [-2.6, 1.8], same sign True); B: -2.5 → -0.667 (t_mean 95 % [-2.2, 0.8], same sign True); L: -13.0 → -17.5 (t_mean 95 % [-27.2, -7.8], same sign True).

**Secondary (physchem, Holm over 6, exploratory):** phys-aware regime A 4.25 (t_mean 95 % [1.8, 6.7], DIFFERENT_BUT_WITHIN_MARGIN); phys-blind regime A 3.725 (t_mean 95 % [1.4, 6.1], DIFFERENT_BUT_WITHIN_MARGIN); phys-aware regime B 4.85 (t_mean 95 % [3.0, 6.7], DIFFERENT_BUT_WITHIN_MARGIN); phys-blind regime B 3.725 (t_mean 95 % [1.7, 5.8], DIFFERENT_BUT_WITHIN_MARGIN); phys-aware regime L 15.975 (t_mean 95 % [7.8, 24.1], DIFFERENT); phys-blind regime L -0.4 (t_mean 95 % [-7.2, 6.4], EQUIVALENT).

**Descriptive.** Other arm (aware − blind): A `frozen` -9.3 (t_mean 95 % [-15.8, -2.8]); B `frozen` -2.075 (t_mean 95 % [-4.3, 0.1]); L `frozen_sub` -1.95 (t_mean 95 % [-3.9, 0.0]). Initial held-out AUROC of the frozen model, aware − blind: A -0.0095 ([-0.0175, -0.0015]); B -0.0131 ([-0.0303, 0.004]); L -0.004 ([-0.028, 0.02]).

**Source-cluster bootstrap (interval type `cluster_source`; statistic = summed per-source seed-averaged hit difference):** A: -0.5 [-1.3, 0.2] over 23 sources, largest contributors [['2021_Kelly', -0.27], ['2022_Bhardwaj', -0.15], ['2018_Kaneda', 0.12]]; B: -1.1 [-2.7, 0.4] over 24 sources, largest contributors [['2024_Faris', 0.43], ['2016_Furukawa', -0.4], ['2015_Wang', -0.3]]; L: -16.4 [-64.8, 17.4] over 20 sources, largest contributors [['2020_Townsend', -20.98], ['2021_Kelly', 6.65], ['2015_Bockus_1', -0.78]].

**Regime L lab structure.** 34 distinct held-out lab sets in 40 seeds; most frequently held out: {'2013_CHUGAI': 40, '2016_Furukawa': 40, '2017_Pye': 34, '2022_Taechalertpaisarn': 31, '2022_Bhardwaj': 30, '2020_Barlow': 29, '2021_Golosov': 29, '2023_Ghosh': 29}. Mean aware − blind difference over the seeds in which a given lab is NOT held out (labs with ≥ 10 such seeds): {'2015_Ahlbach': {'n_seeds': 12, 'mean': -10.0}, '2015_Wang': {'n_seeds': 14, 'mean': -19.21}, '2018_Naylor': {'n_seeds': 12, 'mean': -20.92}, '2020_Barlow': {'n_seeds': 11, 'mean': -0.82}, '2020_Furukawa': {'n_seeds': 15, 'mean': -10.2}, '2020_Le Roux': {'n_seeds': 13, 'mean': -6.31}, '2021_Comeau': {'n_seeds': 18, 'mean': -8.61}, '2021_Golosov': {'n_seeds': 11, 'mean': -13.91}, '2021_Wang': {'n_seeds': 13, 'mean': -12.31}, '2022_Bhardwaj': {'n_seeds': 10, 'mean': -9.4}, '2023_Ghosh': {'n_seeds': 11, 'mean': -9.55}, '2024_Faris': {'n_seeds': 14, 'mean': -16.57}, '2024_Koch': {'n_seeds': 13, 'mean': -9.69}, '2024_Ly': {'n_seeds': 11, 'mean': -6.27}}.

**Planted controls (seeds 0–9, aware − blind, hits):**

| control | n | mean | t_mean 95 % | t_mean 90 % | rule | passes | Δ initial AUROC |
|---|---|---|---|---|---|---|---|
| chiral|A | 10 | 43.3 | [37.2, 49.4] | [38.4, 48.2] | aware-blind lower 95% bound > 0 | **True** | 0.2662 |
| chiral|L | 10 | 170.4 | [154.8, 186.0] | [157.8, 183.0] | aware-blind lower 95% bound > 0 | **True** | 0.1326 |
| flat|A | 10 | 1.7 | [-2.6, 6.0] | [-1.7, 5.1] | 90% t-interval inside +-10 hits | **True** | -0.0066 |
| flat|L | 10 | -5.7 | [-25.2, 13.8] | [-21.5, 10.1] | 90% t-interval inside +-10 hits | **False** | -0.0044 |

`controls_valid = False`.

## 10. Reading under the pre-registered rules (no new analyses)
1. **Formal outcomes.** Regime L: aware − blind = −16.4 hits, **DIFFERENT** (blind higher; Holm p = 2.3e-4; both 95 % intervals exclude 0; the 90 % intervals are not inside ±10); the 30 new seeds alone reproduce the sign and size (−17.5). Regimes A and B: **EQUIVALENT** within ±10 hits (−0.5, −1.1), with the weak-margin caveat of section 4 (the margin is 13 % and 40 % of the level).
2. **The planted-control rule is not met in regime L.** The flat-label control (a label that cannot depend on chirality) gives aware − blind = −5.7 hits with a 90 % t-interval of [−21.5, 10.1]; the rule requires it inside ±10, so by section 6.3 **the regime-L contrast must not be read as evidence about chirality**. The point estimate is small and the interval is wide because paired differences in regime L are noisy (the real-data SD is 23 hits; the control has 10 seeds); the failure is of the pre-registered rule and is reported as a failure, not rescued. The chiral control passes in both regimes (aware higher by +43.3 and +170.4 hits; initial AUROC +0.27 and +0.13), so the pipeline can detect a chirality-dependent label, and the flat control passes in regime A.
3. **The regime-L difference is concentrated in one laboratory and is not a ranking-quality difference.** The source-cluster 95 % interval is [−64.8, 17.4] (includes 0); 2020_Townsend alone contributes −21.0 hits (more than the whole −16.4). The seed-level intervals treat seeds as independent although two labs are held out in all 40 seeds (34 distinct held-out sets), so they are anti-conservative. The initial held-out AUROC of the frozen model does not differ in regime L (−0.004, 95 % [−0.028, 0.020]). Dropping seeds by held-out lab leaves the sign unchanged in all 14 labs examined, but the mean falls to −0.8 over the 11 seeds in which 2020_Barlow is not held out (exploratory; not pre-registered).
4. **Physchem comparison (exploratory).** In regime L the descriptor GBM equals the blind fingerprint GBM (−0.4, EQUIVALENT) and beats the aware one by 16.0; in A and B it is 3.7–4.9 hits higher than either fingerprint model (DIFFERENT_BUT_WITHIN_MARGIN). So in regime L the aware learner is the odd one out, which is what a reader of the committed numbers (201.3 vs 214.3 vs 210.8) would already see; this experiment adds that the gap is stable over 40 seeds and that the stereo-aware learner is not better as a frozen 100-label start.
5. **Not claimed.** That chirality-aware fingerprints are worse in general; that the regime-L effect is a laboratory-independent property (it is driven by one lab and the flat control fails); anything about the loop arms (feedback), larger models, or design quality.

## 11. Record
Spend: two c6i.8xlarge spot instances, 18.7 min + 6.0 min = 24.7 min at about USD 0.53/h ≈ **USD 0.22** (cap USD 2). Both instances terminated (`i-031d993c56fff20c5` reclaimed by AWS, `i-0198fb7e9684fd6b3` terminated at the done flag). Audit findings during the work, all fixed before any contrast was read: (i) the aggregator called `contrast()` without the seed list in the planted-control branch and looked up `auroc_E0` at the top level of the task file instead of inside the arm record (the latter would have returned silent `None` in the descriptive block and a crash in the controls); both found by a dry-run on the committed files and by the first full run; (ii) the first run's watcher timed out while the instance had been reclaimed after 18.7 min, which delayed the resume by about 40 minutes; (iii) the phrase "pretrained start" for the frozen arm is wrong (section 1).
