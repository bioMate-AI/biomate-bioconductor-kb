# Audit of the overnight pilots (protocol compliance and honesty)
Auditor: independent read-only pass, 2026-10-29 ~11:50 UTC. Sources: git log/diffs, committed result JSON/CSV, file mtimes in the worktree, `aws ec2/s3` listings (read-only). No compute, no downloads.

## Bottom line
No pilot's verdict is contradicted by its committed numbers, no pre-registered margin or gate was silently moved in a way that favours a result, and every headline number I recomputed matches. The problems are (a) understated or mis-worded controls and decision vocabulary in pilot 1 and pilot 2, (b) code for pilot 2 and idea A committed only with the results, (c) unlogged or unverifiable spend, (d) a few text-vs-file mismatches. Git commit order (the only trustworthy clock) puts every pre-registration before its result in all 7 items.

## Ranked problems

### 1. MEDIUM - Pilot 1: negative control failure is understated; gate-metric (hard stratum) control values never reported
- Doc (RESULTS item 6) reports only the OVERALL shuffled-label Spearman (max 0.080) and calls it "marginally fails ... looks like noise".
- File `ihlm_backbone/pilot1/results/control_small_shuffle.json` has the HARD stratum, which is the gate metric: k=25 A 0.126, GP_fp 0.121, GP_fpemb 0.104; k=5 PT+k 0.082. All exceed the registered |x|<0.05, and the hard-stratum values are 2-3x larger than the overall ones quoted. Command: `python3 -c` over `budgets[k][arm]['hard']` (recomputed by me).
- The doc does say the pilot is "formally INVALID by its own rule", which is the right consequence; the omission is the size of the failure on the metric that decides the gate. Also a single permutation only, CIs not computed (admitted).

### 2. MEDIUM - Pilot 1: reported recommendation uses a vocabulary the registration did not allow
- A3.5 (caa82b3cb) defines outcomes: GO only if gate passes; "NO-GO-detectable only if it fails with MDE <= 0.03 at >= 2 budgets; otherwise INCONCLUSIVE (underpowered)". Result: MDE80 0.21-0.55 >> 0.03 at every budget (extras_*.json), so the registered label is INCONCLUSIVE. RESULTS item 7 says "Recommendation: NO-GO for fine-tuning compute" and "observed ... differences are negative". 
- "Differences are negative" is false for small k=5 (+0.047 [-0.091,+0.177]); only k=10 small excludes 0. A compute decision is a legitimate output but it should be stated as INCONCLUSIVE + a judgement call, and the pilot is invalid by control (item 1).
- Minor: doc counts inconsistent: "9/8 labs (k=5)" (A2 caveat 2) vs "8/8" earlier; k=25 "10 labs" (A2 count) vs 9 labs in T1 doc and 4 test labs in results.

### 3. MEDIUM - Pilot 1 A3 ("committed before any test-half number was opened") is not verifiable and is tight
- mtimes: `test_small_real.json`, `test_base_real.json`, `test_cells_*.pkl` written 10-28 23:49:00-23:49:01; A3 commit caa82b3cb is 23:49:25 (24 s later). A3 itself says the test jobs had already been started. Selection files written 23:45:03, committed 23:46:49 (before result files: OK). The dev SD for the MDE is pre-registered from the dev half (clean); the repeated-split and Caco-2 additions only add stringency/UNDERPOWERED labels, so I see no direction of bias, but "not opened" rests on the author's word.
- Code diff in results commit b7fc4354c to `pilot1.py` is additive (new `--assay/--labs` args); core test path unchanged. Verified by reading the diff.

### 4. MEDIUM - Pilot 2: model code was not committed before results; several registered details deviated
- `pilot.py`, `pilot2.py`, `ceiling.py`, `embed.py` first appear in 87f909ade (results). The pre-reg commit 0e00f067b and A1 5a60622b7 contain only docs + `prep_pairs.py`. So nothing prevents post-hoc code choices; S3 `edit_pilot/code/pilot2.py` (14,945 B, uploaded 00:09) equals the committed file (14,945 B), and the result JSON sizes equal the S3 outputs (11,107 / 18,056 B), so at least the committed code is what ran.
- Deviations (the doc lists a-d): scheme C sampling (D flip 30 of 238 ordered splits vs "99 distinct" in A1.2; N-Me 10 of 20); D flip has 7 qualifying sources, registration said 8 (listed in the table, not under "Deviations").
- Text vs file: "null edit and shuffled ... all models |rho| <= 0.03". N-Me shuffled `gbm_emb` = -0.055 (results2_nme.json, B_controls.shuffled_within_source.point). Registered control for these is "ours must not beat the baseline and CI includes 0", which holds, so the control conclusion stands, the sentence does not.
- "No gain detectable above MDE" wording: correct (MDE 0.191/0.089 > 0.05). "NO-GO" for compute is allowed by A1.2 ("otherwise NO-GO or UNDERPOWERED").

### 5. LOW-MEDIUM - Pilot 4: leakage check explained away, NO-GO sentence inaccurate, test-stage code patched after A1
- c4_leak.json `feature_matrix_only: false`. The registered L1(i) is "asserted on function signatures"; the check failed (string-matching bug per the author), was not fixed or rerun, and was replaced by "by reading". Substantively the permutation/scramble checks pass, so low risk, but an unfixed failing check is a protocol miss.
- Results header: "dev and test point estimates are non-positive against the best baseline". Test f0: +0.008 (k=3), +0.008 (k=5) vs best test baseline; +0.043 vs dev-chosen nn at k=5. Not non-positive. The verdict (NOT DETECTED/UNDERPOWERED, MDE 0.13-0.19) is right; the NO-GO rationale should rest on MDE, not on sign.
- `p4eval.py` (mtime 00:46:32) and `p4extras.py` (00:46:52) were modified after A1 (00:46:09) and before the test stage (commit 041d6014f 00:47:51). Diff read: adds an optional `t=` argument, restores `t.p` after override, threads the controls/AL loops; I see no semantic change, but dev and test were evaluated by different code revisions. The planted-potency draw was rewritten inline (same seeds recipe, RNG stream order may differ).
- Disclosed (and checked as disclosed): one test target (P21452) was evaluated before A1 and is in the final numbers. Fold models are shared between dev and test evaluation, so dev hyper-selection used models trained with other-fold (including test-family) labels; this cannot inflate test results. No dev/test source overlap found (split by sha256(family)).
- Recomputed from `eval_test.csv.gz` (family-equal, my script): hard Spearman k=3 f0 0.163 / d 0.155 / GP 0.065 / NN 0.069; k=10 GP 0.275 vs f0 0.243 -> diffs +0.008, +0.008 (k=5: 0.202-0.194), -0.032; g k=3 -0.058. All match the doc table.

### 6. LOW - Document-stated times are later than their own commit times
Pilot 2 prereg "~23:50 CDT" (commit 23:25:12); pilot 2 A1 "~00:20 CDT 10-29" (commit 23:53:53 on 10-28); pilot 4 A1 "~00:50" (commit 00:46:09); T2 A4 "~21:35" (commit 21:18:31); frozen A/B "~23:00" (commit 22:55:38). Impossible as literal times; the "before the data" claims are therefore supported only by commit order and mtimes, which I checked and which hold. Recommend removing hand-typed clock times.

### 7. LOW - Spend statements: mostly unlogged or no longer verifiable
- Pilot 2: "about four spot c6i.8xlarge, well under USD 1, not logged". S3 prefixes edit_pilot..edit_pilot4 show 4 launches (23:38-23:43, 23:58, 00:14-00:21, 00:33-00:46); plausible (~USD 0.3-0.6), no cost file.
- Pilot 4: "USD 0.3-0.5, not read from a cost log". Timeline from file mtimes (train 00:10, dev eval 00:45, test eval 01:00, summary 01:12) suggests ~50-70 instance-minutes over 3 c6i.8xlarge plus boot, i.e. at the upper end or slightly above 0.5; no log.
- Frozen A/B: USD 0.22 (24.7 min x 0.53/h); both instances aged out of `describe-instances`; unverifiable. Pre-reg estimated 0.4, cap 2.
- T2: doc says total >= USD 10.2 (cap 20) as a stated lower bound. Only `t2_cost_log_eval.csv` (1 instance, 1.905 USD) is committed; the A3.1 file `t2_cost_log.csv` (3.97 USD) and the dev-grid 4.09 USD are not in the repo; transductive/controls/relaunch ~0.25 estimated. Spend within cap even with generous error.
- Pilot 1, idea A, T1/T1b recompute: "USD 0, local CPU" - plausible, nothing to check.
- Unlogged-spend list: pilot 2 (~4 spot launches), pilot 4 (3 spot launches), T2 controls/evalt/relaunch (~0.25).

### 8. INFO - Instance state (item 6)
- `aws ec2 describe-instances --filters Name=tag:project,Values=cyclic-selector`: ONE instance, `i-0ed58573d57314488` m6i.8xlarge spot, Name `gen-pilot3-b1`, launched 2026-10-29 11:49:37 UTC (about 4 minutes before this audit). That is pilot 3 (generation, out of scope), not a leftover from the seven audited pilots. One active spot request `sir-fspfngng` (consistent). All terminated instances of the audited pilots have aged out of the API, so I cannot confirm termination times, only that none is running.
- S3 prefixes: pilot 2 uses four disjoint prefixes (edit_pilot, edit_pilot2/3/4), pilot 4 `ihlm_pilot4`, frozen `loop_retro/res_frozen_ab` (491 objects; the reclaimed and the resumed instance share it by design, resume skips finished tasks; 440 task files + extras), T2 `technique_sprint/t2/res_*` (one prefix per stage; evalc holds 480 files from one instance; controls relaunch wrote into the same stage prefix as the dead instance, which the doc lists as audit problem 2). I found no prefix with two concurrent writers.

### 9. LOW - Wording that goes slightly past the evidence
- Frozen A/B 10.3: "not a ranking-quality difference". Initial-AUROC difference in L is -0.004 [-0.028, +0.020], i.e. not detected, not shown absent.
- Frozen A/B A/B "EQUIVALENT" with a +-10 margin that is 13%/40% of the level: authors flag it as weak; acceptable.
- Idea A: "no-go on further compute" next to a formal gate of UNDERPOWERED (5 labs, 2 with n~50); numerically NOT SUPPORTED is right by the registered rule, tone is slightly firmer than "no gain detectable".
- T1/T1b: verdict flips NULL -> SUPPORTED at k=5 by the letter of the rule, with "best component chosen on evaluation labs", 16 labs, fails t-Bonferroni and the doc says so; good. Recipe was reconstructed (commands not recorded) and two summarizer scripts are reconstructions, validated byte-for-byte on old cells.

## Verified clean (with how)
- Ordering (git log): pilot 1 A1 6a7679da8 (23:17) < backbone < A2 45ca49fc0 (23:43) < dev-selection commit 22c12a9dd (23:46:49) < A3 caa82b3cb < results b7fc4354c (23:59); dev outputs mtime 23:45 (after A2). Pilot 2 prereg 0e00f067b < A1 5a60622b7 < results; S3 shows the pre-A1 launch ended in 4 minutes with 0-byte logs, so no number was read. Idea A prereg 00:07:53 < `run_ideaA.py` mtime 00:08:31 < controls 00:30 < real 00:47 < results commit. Pilot 4 prereg 00:07:19 < A1 c76e67bae 00:46:09 (frozen_config mtime 00:45:37) < test eval 01:00 < results 01:13. Frozen A/B prereg 22:55 < results 00:06. T2 frozen_config commit 21:18:31 < evalc instance launch 02:34 UTC (21:34 CDT) < results 00:37.
- Margins, gates, baselines unchanged between registration and result in every item except those stated: pilot 1 baseline changed from the pre-fix 0.454/0.429/0.419 to "best of recomputed baselines incl. GP_fp, chosen on test" in A2 BEFORE any embedding score (stricter, disclosed, with a 606-cell regression proving the pre-fix numbers).
- Recomputed headline numbers (own scripts): 
  - Pilot 1: test hard-stratum means and diffs for small and base (e.g. small k=10 diff -0.169 [-0.310,-0.025], gate FAIL, 0/50 splits) match `test_*_real.json`/`extras_*.json`; overall control values match.
  - Pilot 2: LOSO N-Me diff -0.120 [-0.176,+0.022], MDE 0.191, D flip +0.001 [-0.079,+0.026], MDE 0.089, 0/10 and 0/30 splits, planted 0.541/0.630 >= 0.5, from `results2_*.json`.
  - Idea A: per-lab Spearman and mean paired diff -0.059; controls 0.023 / 0.814 / 0.411 vs 0.409; verdict NOT SUPPORTED.
  - Pilot 4: learning-curve and gate numbers (above), C1 NN 0.548 GP 0.561 prior 0.038, C2 no failing cells, 0/50 splits.
  - Frozen A/B: t-intervals recomputed from mean/SD/n (A -0.525 [-2.4,1.3]; L -16.375 [-23.9,-8.9]); seed-split weighted mean -13.0/-17.5 -> -16.375; phys-aware +15.975; flat|L control FAILS and is reported, `controls_valid=False`, contrast not read as chirality evidence. Aggregator patch (AUROC lookup) is descriptive-only and disclosed.
  - T1/T1b: from `perm_cells.csv` PT 0.401/0.369/0.388, PT+k 0.425/0.418/0.429, F2-K k=5 +0.058 [0.011,0.108] (doc 0.010), k=10 +0.031, k=25 +0.025.
  - T2: S1 B +16.7 [7.0,26.3] holds, B2 fails, L -13.1 fails, S2 holds, S3 false everywhere, VERDICT PARTIAL, `div` == greedy disclosed.
- Controls reported where they failed: frozen flat|L (yes), pilot 1 negative (yes, understated, item 1), pilot 4 L1 check false (yes), T1b shuffle failures (yes), T2 weak shuffle control (yes).
- Leakage routes: pilot 1 selection used dev half only, selection file committed before test result; pilot 2 hyperparameters via GroupKFold on dev/outer-train; pilot 4 family-disjoint folds, selection on dev families, one disclosed test-target peek; idea A uses fixed settings, no tuning; no overlapping dev/test sources found.

## Could not verify
- That test-half result files were not opened before A3 (pilot 1) or that pre-A1 pilot-2 S3 outputs were unread (only that logs were empty).
- Raw per-seed frozen A/B task files and T2 per-seed files (only aggregates are committed; S3 not downloaded), so frozen/T2 numbers were checked through summary statistics and internal consistency, not from raw.
- Termination time and cost of any finished spot instance (aged out of EC2 API); PubChem/PeptideCLM-2 pretraining overlap (declared unchecked by authors); transductive baseline files "not opened" claim in T2 A2.
- That local pilots (1, idea A, T1 recompute) cost USD 0.
