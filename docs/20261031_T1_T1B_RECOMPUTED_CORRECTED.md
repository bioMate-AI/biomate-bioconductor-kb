# T1 / T1b permeability few-label cells recomputed on the corrected source annotation (2026-10-29)

Status: **recomputation, same code, same pre-registered protocol, corrected data.** CPU only, local, USD 0. Nothing in the manuscripts, the ledger or the writer's files was edited. Binding cells (T1 and T1b) do not read the permeability annotation and were **not** recomputed.

## 0. What changed (summary)
| item | before correction | after correction |
|---|---|---|
| **T1 F2 (primary), registered (b) "complementary at some k"** | NO at every k, outcome **NULL** | **YES at k = 5** (+0.058, percentile 95% lab-bootstrap [0.010, 0.108], t [0.002, 0.113]); outcome by the letter of the rule becomes **SUPPORTED at k = 5 only**; fails the Bonferroni(3) t reading; nested-n0 version still positive at k = 5 (+0.040 [0.005, 0.077]) |
| T1 F1 (registered original; failed planted control (i)) | (b) YES at k = 25 only, percentile only (t95 lower bound −0.000) | (b) YES at k = 10 (percentile only, fragile) and k = 25 (percentile **and** t95: [0.006, 0.061]); still fails Bonferroni(3) t |
| T1 (a) non-inferiority, F2 | point yes; CI-lower-bound reading fails at k = 10, 25 | passes at every k under the point rule and both CI-lower-bound readings (> −0.05) |
| **T1b F2b (primary)** | NULL | **NULL** (unchanged; formal NI (95% lower > −0.05) now met at every k, was not) |
| T1b F1b | FAILED | **FAILED** (unchanged) |
| baselines PT / PT+k (k = 5, 10, 25) | 0.419 / 0.368 / 0.381 and 0.454 / 0.429 / 0.419 | 0.401 / 0.369 / 0.388 and 0.425 / 0.418 / 0.429 |
| "fusion did not go beyond lookup" (permeability) | supported by T1 F2 NULL | **No longer supported as worded**: against the best single component (K or A) the primary fusion F2 gains +0.058 at k = 5 (lower bound > 0 under percentile and t95) and F1 gains at k = 10, 25. Against the learned prior (PT, PT+k) fusion still does not win (T1: F2 − PT+k = −0.132 [−0.240, −0.015] at k = 5, −0.066 at k = 10, −0.009 at k = 25) and T1b F2b is still NULL vs PT+k. |

Reading: the corrected data move the T1 rule-prior fusion from a null to a small, lab-fragile positive against its own components, but nothing here shows fusion beats the learned prior PT+k, which is the stronger baseline. The T1b conclusion is unchanged.

## 1. Protocol identity (how verified)
1. **Code byte-identical.** Every `.py` in `technique_sprint/fusion` and `fusion_b` used here is byte-identical to the repository version at HEAD `041a68490` (`cmp` on all files). Two summarizer scripts were *added* because the originals were inline snippets that were never committed (§7); each was validated to reproduce the old committed file exactly from the old cells.
2. **Regression on the pre-correction annotation.** Running the same `perm_testbed.py --smoke` on the annotation and `mmp_pairs_pampa.csv.gz` from `e2d1069bf^` reproduces the committed `perm_cells.csv` rows for the same two labs exactly: **600 of 600 cells, maximum |difference| 0.0**. Pilot 1 independently reproduced all 606 cells of the committed file on the pre-fix annotation (0 mismatches, max difference 1e-16; commits 45ca49fc0, caa82b3cb, b7fc4354c).
3. **Only the data changed**: `stratification/data/annotations.csv.gz` and `mmp_pairs_pampa.csv.gz` (commit `e2d1069bf`, 2026-10-28 19:04). The source correction moved **150 peptides of `2023_Ohta` into `2013_CHUGAI`** (719 → 878 peptides) and changed 15 other sources by a few peptides each (e.g. 2018_CHUGAI 9 → 0). With the registered eligibility rule (`MIN_SRC_N = 20`) the eligible lab count falls **21 → 20** (2023_Ohta no longer exists) and the evaluated peptide count is 6,784 (was 6,776 in the old shuffle log). Per-k lab counts: k = 5: 17 → 16; k = 10: 15 → 15; k = 25: 9 → 9. No protocol parameter, margin, grid, seed or interval rule was touched.
4. **Brute-force audits re-run and pass**: T1 `audit_perm.py` worst |diff| 8.3e-17; T1b `audit_perm_b.py` worst |diff| 5.6e-17 (both need a smoke cells file that the repository had deleted; regenerated with `--smoke` / `--labs 2`).
5. **Planted-signal controls**: the unit tests are synthetic and data-independent; results are **identical** to the registered ones: T1 F1 fails control 6.1(i) (k = 5: 0.571 vs threshold 0.573; k = 10: 0.428; k = 25: 0.181; prior alone 0.717) and F2 passes all three worlds; T1b F2b misses control 6.1(i) marginally at k = 10 (0.608 vs 0.609 = 0.85 × PT) and passes (ii)–(iv). `planted_tests_*.txt` record 8 passed / 1 failed (T1) and 3 passed / 1 failed (T1b), the same disclosed failures.

## 2. Baselines (per-lab mean Spearman, mean over labs; `perm_baselines_summary.json` rebuilt by `summarize_baselines.py`)
| k | labs old → new | PT old → new | PT+k old → new | RF (revealed only) old → new |
|---|---|---|---|---|
| 5 | 17 → 16 | 0.419 → 0.401 | 0.454 → 0.425 | 0.213 → 0.210 |
| 10 | 15 → 15 | 0.368 → 0.369 | 0.429 → 0.418 | 0.295 → 0.298 |
| 25 | 9 → 9 | 0.381 → 0.388 | 0.419 → 0.429 | 0.381 → 0.444 |
These match the PT / PT+k values reported by pilot 1.

## 3. T1 registered outcomes (R4), permeability; difference vs the best single component (chosen on the evaluation labs, as registered); lab-cluster percentile bootstrap 95%
| arm, k | best component | old: mean [95% pct] (labs) | new: mean [95% pct] (labs) | registered (b): mean ≥ +0.02 and lower bound > 0 |
|---|---|---|---|---|
| F2_5 (primary), k = 5 | K | +0.041 [−0.001, 0.090] (17) | **+0.058 [0.010, 0.108]** (16) | old no → **new yes** |
| F2_5, k = 10 | A | +0.027 [−0.062, 0.111] (15) | +0.031 [−0.035, 0.100] (15) | no → no |
| F2_5, k = 25 | A | −0.004 [−0.102, 0.077] (9) | +0.025 [−0.019, 0.073] (9) | no → no |
| F1_5, k = 5 | K | +0.041 [−0.043, 0.144] (17) | +0.072 [−0.008, 0.167] (16) | no → no |
| F1_5, k = 10 | A | +0.041 [−0.001, 0.083] (15) | **+0.041 [0.004, 0.080]** (15) | old no → **new yes** (percentile only) |
| F1_5, k = 25 | A | +0.031 [0.007, 0.056] (9) | +0.034 [0.012, 0.056] (9) | yes → yes |
(a) non-inferiority (point ≥ −0.03 at every k): F2 yes → yes (+0.058, +0.031, +0.025; was +0.041, +0.027, −0.004); F1 yes → yes.

### 3.1 Interval-type readings of the "gain" criterion (`reeval_intervals.json`; mean ≥ +0.02 and lower bound > 0)
| arm, k | percentile 95% | t 95% (df = n−1) | percentile Bonferroni(3) | t Bonferroni(3) |
|---|---|---|---|---|
| F2_5, k = 5 | old F → **new T** | old F → **new T** (lower 0.002, two-sided p = 0.042) | old F → **new T** | F → F |
| F1_5, k = 10 | old F → **new T** | F → F | F → F | F → F |
| F1_5, k = 25 | T → T | old F → **new T** (lower 0.006, p = 0.024) | T → T | F → F |
All other T1 permeability cells: false under all four readings, before and after. **No cell passes the most conservative reading (t, Bonferroni).**

### 3.2 Robustness of the changed readings (drop-one-lab, percentile lab bootstrap)
- **F2 vs K, k = 5**: holds when any single lab is dropped (lowest lower bound +0.003; 0 of 16 drops reach ≤ 0; weakest drop 2021_Comeau: +0.050 [0.003, 0.101]); labs with a positive difference: 10 of 16. The nested-n0 (n0 chosen by inner leave-one-lab-out CV) F2 gain at k = 5 is +0.040 [0.005, 0.077] (old +0.026 [−0.004, 0.060]); at k = 10, 25 it is −0.001 and −0.016 (not positive).
- **F1 vs A, k = 10**: fragile (8 of 15 drop-one-lab versions have lower bound ≤ 0). **F1 vs A, k = 25**: holds under every drop (weakest drop 2021_Kelly: +0.028 [0.007, 0.051]) but only 9 labs.
- Not corrected for the selection of the best component on the evaluation labs (as registered) or for the 3 k × 2 arms grid beyond the Bonferroni(3) columns above.
- Bonferroni(3) 98.3% percentile interval for F2 at k = 5: [0.004, 0.124] (`perm_extras.json`).

## 4. T1b (learned prior PT), permeability, vs the best comparator (PT+k at every k); percentile lab-bootstrap
| arm | k | old mean [95%] | new mean [95%] | decision (unchanged) |
|---|---|---|---|---|
| F2b_5 (primary) | 5 / 10 / 25 | −0.010 [−0.046, 0.015] / +0.006 [−0.020, 0.029] / +0.025 [−0.057, 0.134] | −0.004 [−0.033, 0.019] / +0.002 [−0.032, 0.031] / +0.042 [−0.034, 0.129] | **NULL**: (a) point-NI holds; (b) not met (no cell ≥ +0.02 with lower bound > 0); formal NI (95% lower > −0.05): old not met, **new met at every k** |
| F1b_5 | 5 / 10 / 25 | −0.041 [−0.072, −0.013] / −0.006 / −0.025 | −0.032 [−0.063, −0.000] / −0.002 / +0.015 | **FAILED** ((a) point-NI fails at k = 5 in both) |
Under no interval type does any T1b permeability cell show a gain. Binding T1b: unchanged, not recomputed.

## 5. Controls on the corrected data
- **T1 shuffled-label control (5 shuffles; registered: each arm mean within ±0.03 of 0 with CI containing 0)**: old PASS for A, F1, F2 and **FAIL for K** (K non-constant in only 2–4 labs); new **PASS for K, A, F1, F2** (e.g. F2 +0.023 [−0.001, 0.052] at k = 25).
- **K null control, 40 shuffles** (`k_null_control.py`): K non-constant in 92/800 (shuffle, lab) rows (11.5%; was 55/840, 6.5%), mean rho +0.017 (was +0.015).
- **T1b shuffled-training-label control (3 shuffles)**: old PASS only for A; new PASS for **A and F1b**, **FAIL for PT, PT+k and F2b** (all at k = 25: PT +0.022 [0.000, 0.046], PT+k +0.026 [0.003, 0.050], F2b +0.038 [0.005, 0.081]).
- **T1b post-hoc 40-shuffle null diagnostic** (E[rho] = 0 exactly for any pipeline that cannot see the held-out labels): old 1 of 15 intervals (shuffle-cluster) excluded 0; **new 5 of 15 exclude 0, all positive** (k = 10 PT +0.012, PT+k +0.014; k = 25 PT +0.020, PT+k +0.019, F2b +0.012). The cause is **not diagnosed**. The positive bias sits in arms that contain the learned prior PT and would cancel in differences vs PT+k (as in §4), but it is a caution for any absolute level claim on the corrected data.

## 6. Verdict changes for routing (not applied to any manuscript text)
1. **T1 F2 (primary) permeability outcome: NULL → SUPPORTED at k = 5 by the registered rule** (percentile and t95; fails t-Bonferroni; 16 labs; best component K at k = 5). The registered label for F2 stays "not failing any planted control"; F1 stays "failed planted control (i)".
2. **T1 F1 k = 25** is now supported under t95 as well as percentile (previously percentile only); still not under t-Bonferroni; **F1 k = 10** newly passes the percentile rule (fragile).
3. **T1 (a) non-inferiority** now holds under the CI-lower-bound readings for F2 (it failed at k = 10, 25 before).
4. **T1b: no change** in outcomes (F2b NULL, F1b FAILED); formal NI for F2b now met at every k.
5. **"Fusion did not go beyond lookup" (permeability)**: no longer a supported statement for the rule-prior fusion vs its components; remains true vs the learned prior (PT, PT+k).
6. **Shuffle controls**: T1 K control now passes; T1b shuffle control still fails for PT, PT+k, F2b (k = 25). The T1b 40-shuffle diagnostic shows 5/15 positive intervals (§5).
7. **Reference values**: PT and PT+k reference values change as in §2 (and the lab counts 17/15/9 → 16/15/9).
8. Claims that did **not** rest on these cells: binding fusion, C2, L5, the validity-gate results.

## 7. Limitations and notes
- 5 seeds per cell (registered). Intervals are over 16, 15 or 9 labs; the k = 25 results rest on 9 labs. Lab-cluster bootstrap B = 2000, seed 3, as in the originals; t intervals use df = n−1.
- `summarize_baselines.py` and `summarize_nested.py` are **reconstructions**: the originals were inline snippets. Each reproduces the committed old file byte-for-byte from the old cells (B = 2000, seed 3), then was applied to the corrected cells. `perm_extras.json`, `perm_summary.json`, `perm_shuffle_summary.json`, `perm_b_*_summary.json` and `reeval_intervals.json` were regenerated by the original scripts.
- Stale files were excluded: the original `*.log` (without `.txt`) files are copies of the old logs. The T1b real and shuffle runs now write one log (`perm_b_real.log.txt`) because `perm_b.py --shuffles 3` was run in one process.
- The recipe was reconstructed from code and logs because the original commands were not recorded: `perm_testbed.py` (real), `--shuffle 5`, `--no-pt`, `k_null_control.py 40`, `nested_n0.py`, `extra_perm.py`, `summarize_perm.py real|shuffle`, `audit_perm.py` (after `--smoke`); `perm_b.py --shuffles 3`, `perm_b_null.py` (40 shuffles), `summarize_b.py perm|perm_shuffle`, `reeval_intervals.py`, `audit_perm_b.py` (after `--labs 2`). Evidence the recipe matches: the arms, k values, seeds and cell structure are identical to the committed files, and the pre-correction regression (§1.2) reproduces the committed cells exactly; row counts differ as expected from the changed lab set (e.g. T1b shuffle rows 7,527 vs 7,878).
- Scripts were run from a scratch copy (outside the repo) so the committed pre-correction result files stayed untouched; outputs are in `results_corrected/` next to the originals.
- Not recomputed: binding cells (unaffected), the T1/T1b documents' text, any manuscript number.

## 8. Files (all under `research/guangzhou_all_atom/cyclic_llm/technique_sprint/`; hashes in `summaries_corrected/MANIFEST_SHA256.txt`)
`fusion/results_corrected/` (perm_cells.csv, perm_cells_nopt.csv, perm_shuffle_cells.csv, perm_nested_n0_cells.csv, perm_summary.json, perm_baselines_summary.json, perm_extras.json, perm_shuffle_summary.json, perm_nested_n0_summary.json, k_null_control.json, audit_perm.txt, planted_tests_T1.txt, logs); `fusion_b/results_corrected/` (perm_b_cells.csv, perm_b_shuffle_cells.csv, perm_b_null40_cells.csv, perm_b_summary.json, perm_b_shuffle_summary.json, perm_b_null40_summary.json, reeval_intervals.json, audit_perm_b.txt, planted_tests_T1b.txt, logs); `summaries_corrected/` (old and new printouts); `fusion/summarize_baselines.py`, `fusion/summarize_nested.py`.
