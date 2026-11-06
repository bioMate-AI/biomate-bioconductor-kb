# Cyclic-peptide manuscript program — status you can verify (2026-10-27)

Purpose: every line below points to a file, a commit or a command, so the status does not depend on anyone's recollection. Written after the user's complaint that status reports could not be trusted. If a pointer does not show what is claimed, the claim is wrong and should be struck.

## 1. What is measured (evidence exists)
| claim | evidence |
|---|---|
| Pilot (26 complexes): default pick 80.8 %, ipTM 76.9 %, random 80.3 %, oracle 96.2 % (DockQ ≥ 0.23) | `research/guangzhou_all_atom/multitarget/cyclic_complex_benchmark/results/PILOT_RESULT.md`, `pilot_results.json` |
| Train-only CV (135 complexes, grouped by receptor cluster): oracle 97.0 %, default 83.7 %, random 83.7 %, S0 82.1 %, S1 84.3 %, S2 (3 pLDDT features) 86.4 %, contrastive best 84.4 % | `results/stageB_cv_train.json`, `stageB_cv_features_train.json`, `stageB_cv_contrastive_train.json` |
| Only 37 of 135 train complexes have any selection signal (94 all-succeed, 4 none) | recompute: `scripts/stageB_cv.py` inputs; numbers quoted in `PREREG.md` A6/A7 |
| Display-binding "win" is not distinguishable from family memorisation on 3 of 5 targets; PADI4 is the exception | `docs/20261027_SELECTOR_LEAKAGE_AUDIT.md`, `research/guangzhou_all_atom/cyclic_llm/results/leakage_audit_{PADI4,FIKK13,Abeta42,hIAPP,hPCSK9}.json` |
| 4 complexes had a 0-byte sample file; Boltz exited 0 | commit `6ee3c1a65`; quarantine prefix `s3://biomate-nextflow-work/cyclic_peptide/cofold_bench/quarantine/zero_byte_sample_20261027/` |

## 1b. Stage B result (one-shot, 2026-10-27 18:37 CDT) — PRIMARY CLAIM NOT SUPPORTED
Files: `research/guangzhou_all_atom/multitarget/cyclic_complex_benchmark/results/stageB_eval_S2.json`, `stageB_eval_S0.json`; protocol outcome appended to `PREREG.md` (commit `50fba9dbb`). 104 post-cutoff test complexes: default 57.7 %, random 59.6 %, strongest baseline 60.6 %, selector S2 59.6 % (−1.0 pp, CI −4.6..+2.1), oracle 76.9 % (oracle − default +19.2 pp, CI 8.8..28.5). Novel receptors (68): S2 51.5 % vs 52.9 %. 9 of 113 test complexes not generated in time (listed).

## 1c. Permeability loop result (2026-10-27) — CONFOUNDED BY ONE SOURCE (see L3); do not cite as a within-laboratory gain
Correction found later the same day: 78 % of top-decile peptides (557/711) come from one source (2013_CHUGAI); the N-methyl rule's hits are 98.5 % from it. Within-source re-run pre-registered as amendment L3 (commit `0618c77e7`) and running. The figures below are the pooled, confounded outcome.

Files: `research/guangzhou_all_atom/cyclic_llm/loop_retro/results/loop_result.json`, `loop_res/` (120 per-task files), `rule_baseline.json` (exploratory); protocol outcome in `PREREG_LOOP.md` (commit `94aed12a5`). Hits in 500 picks (30 seeds): in-distribution random 49.9 vs greedy 396.7 (+346.8, CI 280..389); scaffold-shifted 106.6 vs 366.7 (+260.1, CI 125..318). Knowledge features: +21 [-11,63] / -40 [-211,113] (not supported). Exploratory: N-methyl-count rule alone finds 276 / 304 (70 % / 83 % of the loop's yield).

## 2. What is NOT measured (no evidence yet)
- (Stage B is now measured; see 1b.)
- The language model on a family-disjoint split (needed for the PADI4 comparison).
- Any rules-and-knowledge generation result. No manuscript exists for it.
- Any wet-lab result.

## 3. Failures and errors in this session (so they are on the record)
1. Reported "98/113 test complexes done"; the true number was 92 (directories were counted, not `run.json` markers). Live count at the time of writing: test 104/113, train 155/283 (`aws s3 ls .../samples/boltz/ --recursive | grep run.json`).
2. A job script hung 30 min on `wait` (the logging `tee` is a background job). Fixed in `loop_retro/job_loop.sh`; the scoring script was fixed on S3.
3. The permeability loop ran 2 h 15 min serially on a spot instance, wrote results only at the end, and was reclaimed (`Server.SpotInstanceTermination`, 2026-10-27 20:21 UTC): result lost. Replaced by the parallel, per-task-checkpointed runner (commit `f3ae09170`).
4. The sync loop was reported as running when it had exited after one pass; fixed (persistent monitor). One earlier statement ("7 SH3 domains" etc.) was corrected in a previous session.
5. A leaking feature screen (irmsd/lrmsd as features) was excluded earlier; the selector now asserts no ground-truth columns.

## 4. Compute used today (instance-hours, not dollars; dollar cost not computed)
- c6a.4xlarge spot, scoring: ~0.6 h (finished, terminated).
- c5.4xlarge spot, loop + audits: ~2.3 h (loop result lost; audits saved).
- m6i.4xlarge spot, loop re-run: running.
- GB10 workstation: generation of Stage B structures, no cloud cost.
Check cost yourself: Cost Explorer filtered on tag `project=cyclic-selector`.

## 5. Open decision for the owner
`biomate-nextflow-ce-v2` (production Batch compute environment) still has min 8 vCPU = one always-on r5.2xlarge. Not changed; needs an explicit choice.

## 6. Next gates
1. Stage B evaluation fires at the earlier of all test complexes done or the time recorded in `PREREG.md` A5 (6 h after commit `760a9812c`). Remaining test complexes missing now: 8UTL_2, 8XIP_6, 8XIR_6, 8XZJ_6, 8ZBE_5, 8ZCJ_6, 9BT6_2, 9BT7_2, 9DEK_2.
2. Validation-set model choice (A8), then the one-shot test run (`scripts/stageB_eval.py`).
3. Fill the placeholders in `docs/20261027_PREPRINT_V1_PUBLIC/manuscript.md` and `manuscript_loop.md` from the outputs, never by hand.
