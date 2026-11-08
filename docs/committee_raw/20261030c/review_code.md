# Independent code + statistics review (cyclic-peptide closed-loop study)

Scope read: cyclic_llm/loop_retro (run_l7a, run_loop*, aggregate_l7/_prior/_loop, loop_models partly, tests, launch scripts), technique_sprint/acquisition (acq, run_acq, aggregate_acq, make_ud, tests), ihlm_ladder (core, runner, adapter, aggregator), ihlm symbolic memory (partly), stratification (stats, enrich, common), qa_audit (aggregate_integrity, cluster_recompute), multitarget/integrin_chembl/retro_recovery (validity_gate, harness, 19_folds_v2), figures_paper (common, f_l5_loop). I did not read ihlm_v2 beyond greps, ihlm/model.py, p0_intrinsic, stratification annotate/mmp/cliffs, retro_recovery scripts 01-18/20-24, run_l7a_llm. No docs/*COMMITTEE*, *REDTEAM*, *LEDGER* read.
Executed (CPU, niced): loop_retro/test_aggregate_l7.py (7 PASS), stratification/test_stats.py (5 PASS), acquisition/test_aggregate.py (all PASS), plus five ad-hoc probes (below). pytest of test_l7a.py/test_l5 etc. was started but killed after ~8 min of CPU on a loaded machine (10 tests had passed; not completed -> test_l7a core NOT confirmed by me). Machine load avg ~18.

## Ranked defects

### D1 (MAJOR, claim-affecting) L5 "95%/99% CI" is a seed spread, not a CI of the mean; the figure caption/claims inherit it
- loop_retro/aggregate_prior.py:8 (`ci`, own NOTE admits "central range (spread) ... NOT a CI of the mean"), :27/:36 (`lower_gt0`, `CLAIM_*` use the spread); loop_retro/run_loop.py:68 (`ci()` = sorted-seed index; at n=30 it is literally min..max); aggregate_loop.py:8 same. figures_paper/f_l5_loop.py:44-57,86-88 labels it "95% percentile CI over 30 paired seeds" and "(b) 99% CI; every interval includes 0".
- Verified from results/l5_aggregate.json: regime B loop-minus-random spread [-1.6, 44.1] (flag lower_gt0=False) vs bootstrap CI of mean [17.7, 26.5]. Knowledge arms: kn_B spread99 [-4.0,54.0] vs mean-CI [17.2,30.0]; fuse_z_B [7.3,21.0]; fuse_nme_B [0.8,14.3]; fuse_z_A [1.8,14.7]; resid_z_A [0.3,12.2] all EXCLUDE 0. So "every interval includes 0" and "knowledge does not help" are artefacts of using the spread; a power statement was made with a dispersion statistic.
- Caveat on the other side: seeds share one dataset/pool, so even the mean-CI is a seed-level (optimisation/split) interval, not a population interval.
- Cheapest confirmation: python3 -c 'import json;d=json.load(open("results/l5_aggregate.json"));print(d["kn_B"]["d_total"])'.
- Fix: report ci_mean + source/lab-cluster interval; relabel spread as "central range"; re-derive CLAIM_* flags.

### D2 (MAJOR) Transductive per-source label standardisation removes the lab offset the regimes are supposed to test
- loop_retro/run_loop_prior.py:96 and run_l7a.py:228 (`K.source_normalize(y_raw, srcs)` over ALL peptides incl. unrevealed pool, E and held-out labs); thr = 0.9-quantile of those z-scores (run_l7a.py:228). Same in acquisition/acq.py:29 (ymode="trans" default; the causal mode exists only from amendment A2), ihlm_ladder zt scheme, stratification/common.py:25 (descriptive only; fine there).
- Measured on the 6,960-peptide set: raw hit rate (top-10%) is 1.8% in the two largest labs vs 24.4% elsewhere; after normalisation 11.9% vs 6.8%; lab raw-mean SD 0.50 vs overall SD 0.79. Regime B ("train on 2 labs, search the others") and L ("leave labs out") therefore never face the dominant shift (lab offset); the held-out lab's own mean/SD (from unrevealed labels) is used to define its labels and hits. In regime L the learner can never be asked to predict an unknown lab offset.
- Failure scenario: a learner that is great within-lab but blind to lab offset looks identical to one that handles offsets; any "generalises across labs" claim from L5/L7 transductive runs is oracle-assisted. (Mitigated where causal zc/`causal_z` was used: acq.py:78-87, ladder_core.causal_labels. Those runs are the only ones free of this.)
- Cheapest test: re-run one GBM L task with labels = causal_z (acq.causal_z) and compare loop-minus-random in B/L.

### D3 (MAJOR) Provenance of aware/blind GBM is carried only by directory names; runner never records it
- run_l7a.py:334 `out.update(backend=alias, backend_spec=..., ...)` has no `learner` and no FP_CHIRAL value (grep: no "learner" in run_l7a.py). aggregate_l7.py:80-91 `learner_key` docstring says the `learner` field is used "when present (new runs)" - no runner writes it. Aware/blind/confirm/srcmatch/detK are told apart purely by substrings of the directory name (`"blind" in name`, `"confirm" in name`, `"res7m_"`, `"res7q_"`).
- Scenario: a result dir copied/renamed or collected under another prefix (collect_l7.sh only syncs `PRE res7[af]_` prefixes!) is silently re-keyed or dropped. collect_l7.sh:5 glob `res7[af]_` cannot collect res7k_/res7m_/res7q_ at all, so a rerun of collect_l7.sh would silently omit the confirmatory and detK dirs (aggregator then reports fewer groups, no error).
- Test: mv res7f_gbm_blind res7f_gbm_x && aggregate -> blind results are merged into gbm_aware, `ValueError` only if arm sets overlap (they do here), otherwise silent merge via `cur.update(r)` (aggregate_l7.py:107).
- Fix: write learner=alias+FP_CHIRAL+git sha into every result JSON; aggregator keys on it and refuses dir-name inference.

### D4 (MAJOR) Frozen / shuffled controls in aggregate_l7 cannot fail
- aggregate_l7.py:157-159: control "passes" iff CI lower bound <= 0. (a) frozen: state never changes -> gain is exactly 0, CI [0,0] -> passes by construction (acq/test_l7a.py:60 even asserts it). That control would pass with a completely broken model. (b) shuffled: a strongly NEGATIVE gain (upper CI < 0, i.e. the shuffled arm degrades the model) also "passes"; a mean gain of +0.08 AUROC with CI [-0.01, 0.17] passes at n=10. The criterion is one-sided in the wrong direction for a leak detector and has no equivalence margin (compare ihlm_ladder MARGIN_Y/MARGIN_AUC, which does it right).
- Cheapest test: feed o["E_auroc_gain"]["shuffled"]={"n":10,"mean":-0.3,"ci":[-0.4,-0.2]} -> passes=True.

### D5 (MAJOR) Percentile bootstrap of the mean at n=10 seeds under-covers; no multiplicity control across the L7 contrast grid
- aggregate_l7.py:17-23 (`ci`), used for every yield/AUROC contrast; dev grids use 10 seeds. Simulated: percentile-bootstrap 95% interval for a mean at n=10 (normal data) covers 0.894; t3 data 0.897. aggregate_acq/ladder use "wider of bootstrap and t" (better); aggregate_l7 does not.
- The only multiplicity handling is a hard-coded 99% level when "kphys" or "kn" is in the contrast name (aggregate_l7.py:149); ~11 yield + 5 AUROC contrasts x ~9 learners x 4 regimes are each reported at 95% with no Holm/BH. Substring test `"kn" in name` is also brittle.
- Seeds are not independent draws of the lab population (same data); the lab-cluster bootstrap exists only for E source-rho (aggregate_l7.py:41-77) and only for 6 contrasts.

### D6 (MAJOR) Frozen T2 config makes `div` identical to `greedy` and `prov` = fuse+UCB; S3 (diversity) cannot be met
- technique_sprint/acquisition/frozen_config.json: lam=0.0, cap_src=50 (= BATCH, so `src_cnt < 50` is never binding within a 50-pick batch, acq.py:123), cap_flat=BIG. select_diverse then reduces to plain top-k (test_acq.py:36 confirms). Verified: run_arm("div") picks == run_arm("greedy") picks (True) on the synthetic fixture with this cfg; "prov-div" ablation (aggregate_acq.py:97) is therefore prov vs a duplicate of greedy.
- Cause: pre-registered selection rule applied to 3 development seeds (frozen_config.json note says "unreplicated"); rule max mean(rel_B, rel_L) s.t. rel_A>=0.9 picked the degenerate cell. Not a code bug, but the arm named "diversity-aware provenance" has no diversity in the evaluation; any S3 verdict is about UCB+fusion.
- Also: aggregate_acq.load keys (label, regime, seed) across ALL dirs given; if the dev dir (seeds 100-102, label "greedy") is passed together with eval dirs, `arr(R,"greedy",...)` mixes dev seeds into best_baseline_mean and mean_hits (paired contrasts are unaffected). Minor.

### D7 (MAJOR) Silent overwrites / drops in aggregation
- ihlm_ladder/aggregate_ladder.py:36-37 `table()`: `[r["seed"]] = rec` overwrites silently when two files share (regime, scheme, k, seed); :22 `except Exception: pass` drops any unreadable/truncated ladder_*.json without a count. Compare aggregate_acq.load (accounting + AccountingError) and aggregate_l7.load_small (collision ValueError) - the ladder aggregator has neither. Test: duplicate a result file with different hits -> last-sorted wins, no warning.
- aggregate_l7.py:113-120 `load_llm`: `R[(model, regime)][seed] = r` overwrites silently; also `except Exception: continue`.
- aggregate_l7.py:100-101 (`load_small`) swallows unreadable JSON (`except Exception: continue`) with no count in `inputs`.
- aggregate_l7.py:107 `cur.update(r)` merges two files for one task when arm sets are disjoint, but overwrites top-level fields (E, init, params, curve, seconds) from the later file without checking they are equal; two runs with different --n-init/params but disjoint arms would be merged into one frankenstein task.

### D8 (MAJOR) qa_audit "independent" check re-uses the same naming logic and does not fail by default
- qa_audit/aggregate_integrity.py:9-10 hard-codes dir->learner map (same dir-name inference as D3), :71 exits non-zero only with `--strict`; default run prints "problems" but returns 0. Dir names not in LEARNER (res7k_*, res7m_*) are reported "UNMAPPED". It cannot catch a mis-key that the aggregator and the map share.

### D9 (MAJOR) Stratification enrichment p-values assume independent peptides within a lab; both controls are blind to clustering
- stratification/enrich.py:43-61, stats.py:28-33: within-source SMD variance s2*(1/n1+1/n0) treats peptides as iid; peptides cluster in stereoisomer groups/scaffolds/series (flat_size up to >=8). p-values are anti-conservative; BH on them inflates "significant" counts. The within-source permutation null (enrich.py:86-92) and the iid planted random feature (enrich.py:93-96) preserve exchangeability / independence, so they pass regardless of clustering. DL meta uses normal approximation with k>=3 sources (enrich.py:55), no Hartung-Knapp; at k=3-5 sources the interval is too narrow.
- stats.cluster_boot exists but is not used here. Cheapest test: permute labels at the flat-structure level (permute whole stereoisomer groups' z jointly) and count BH discoveries; expect >> 0.

### D10 (MINOR/MAJOR) Launch scripts mask failures
- loop_retro/launch_l7q_resume.sh:25-33: `wait "${PIDS[@]}"` ignores job exit codes; no `set -e`; per-job logs are uploaded only by the 45 s loop, never after the final wait, so the tail of a crashed job is lost; `echo DONE > done.flag` and `shutdown -h now` run unconditionally -> a half-finished grid yields a DONE flag. pip/dnf output sent to /dev/null (lines 5-6).
- technique_sprint/acquisition/make_ud.py:5-9,43-47: preflight2 stage records `echo $?` into *.rc files but nothing reads them; later stages run regardless; JOB_DONE flag written unconditionally; shutdown_h +400 timer. repro_audit exit code is likewise only a file.
- job_loop.sh: same pattern (run_loop_par exit status not checked). Test: make one job exit 1 and observe done.flag.

### D11 (MINOR) Vacuous / weakened assertions (verified by reading)
- loop_retro/test_l7a.py:205 `assert ... == ... or True` (always true; the real check is the Spy.fit length assert).
- acquisition/test_a2.py:83 `assert t_ci(...)[0] < boot_ci(...)[0] + 1e-9 or True`; test_a2.py:60 `0.0 <= la <= 1.0` (tautological for a fraction).
- ihlm_v2/test_ihlm_v2.py:116 `isinstance(p.margin, float) or True`.
- ihlm_ladder/test_ladder.py:154 `A and B and mean==40 or abs(mean-40)<12` - the `or` branch makes the positive_holm requirement optional; :157 `st == "adds" or zt is None` passes when the zt criterion is unassessable.
- test_acq.py:44-45 enshrines transductive standardisation (mean 0 per source) as the specification of prepare().
- test_l7a.py:7 hard-codes a session scratch path as default SCRATCH; fails on any other machine unless SCRATCH is set.

### D12 (MINOR) Other
- ladder zt scheme: ladder_core.causal_labels(scheme="zt") returns y_transductive of the *true* indices (ladder_core.py:17,73) so a `shuffled` arm under zt would see TRUE labels (shuffle is applied to yseen only). Not used in current contrasts (zt only for R0-R4 sign check) but R4_shuf under --scheme zt is a mislabelled control. Also the "same sign under zt" criterion (aggregate_ladder.py:150) is sign equality only (50% by chance), and `planted_test_passed` is a CLI string, not derived from data (:141).
- run_acq.py:41-46 shuffle control uses ONE fixed permutation (seed 31337) for all tasks; seeds 2000-2003 vary only init/rng -> the null is a single draw, not a null distribution.
- aggregate_l7.py:192-197 non-inferiority: ratio drops pairs with q==0 (`if q > 0`) while n_pairs counts them; ratio-of-hits mean-of-ratios; margin 0.90 tested with a two-sided percentile interval at n<=10.
- aggregate_l7.py:41-77/164-171: cluster contrast "loop - one_shot [E source-rho]" is silently never computed because the one_shot record has no `E_scores_final` (run_l7a.py:129-133; verified on a real file: keys lack it). And `build(csv,"knn")` re-derives y/srcs from the full CSV: results made with `--v4-subset` (different index space, run_l7a.py:226) would be mapped to the wrong rows if present (none present in l7_collect).
- run_l7a.py:151,158: *_sub arms strip `picked_all` (arm-specific) from the shared 150-candidate sample, so candidate sets differ slightly between arms after round 0 (docstring says "identical for every arm"). Effect is small and unbiased but the pairing claim is approximate.
- run_loop.py:80 `i not in set(init)` rebuilt per element (O(n^2)); harmless.
- validity_gate.fp/multi-proxy (retro_recovery): leave-fold-out classifiers do not purge compounds shared across families unless `excl` is passed (default None) -> control AUCs can be inflated (direction: conservative for the gate). Family-level percentile bootstrap with as few as 8 families (MIN_FAMILIES) under-covers (same as D5) which makes the TOST equivalence claim liberal. harness.evaluate: "SUPPORTED if lo>0" per arm x metric with no multiplicity.
- Regime "L" anchors (ladder_core.world, k=5 per held-out lab revealed to ALL arms) reveal held-out-lab labels, so ladder-L is "few-shot lab adaptation", not leave-labs-out; by design for M2 but should not be pooled with L7-L language.

## Checked and found CLEAN
- Seed splits: seeds 0-1..8-9 and 10-12..28-29 in launch_l7q_resume.sh cover 0-29 exactly once; parse_seeds correct; no off-by-one.
- Slice disjointness: make_eval_slice/make_flat_slice/make_source_slice/setup_L and the asserts at run_l7a.py:326/330 and ladder_core.py:34,50-52; E/Ef/Es/init/pool/anchor disjoint; regime-L training vs held-out labs disjoint (assert + tests).
- Sorted iteration used wherever sets/dicts of strings feed RNG draws (kshuf, shuffled_labels, make_flat_slice keys, cluster_contrast); K_shuf deterministic across PYTHONHASHSEED (tests exist and the code matches).
- aggregate_l7 cluster bootstrap: per-seed/per-source tables, NaN guard, constant-score = rho 0, seed-only interval recomputed with same statistic; tests pass (7/7 run).
- aggregate_acq: accounting + duplicate-different-content raises, conservative union of percentile+t, exact sign-flip for n<=16, Bonferroni level for S1; 'null' scenario correctly yields NULL_KILL. Holm and BH implementations in aggregate_ladder (holm, bh) and stratification.stats.bh_fdr are correct step-up/step-down with monotone adjustment.
- acq.causal_z / ladder causal_labels use only revealed labels (tests wreck unrevealed labels and assert invariance; code agrees). K_phys is label-free; kn/kphys fusion uses no labels.
- loop arms: shuffled draws from the pool label vector (no item association), noisy permutes 20% of a batch, frozen never feeds back, one_shot uses compute-matched steps (test + code agree), rule_kphys swaps backend and restores it (try/finally).
- Edit priors default neutral and opt-in priors refuse held-out sources (symbolic.py:13-35).
- figures_paper/common.py reads committed artifacts, records hashes, writes an assertion log.
- harness.tie_aware_auc / tie_aware_ef are correct (average ranks; tie-straddle expectation).

## Planted-signal controls: could they pass with a broken model?
- test_l7a arms test (GBM, planted sig): requires loop > random_fb by 10 hits and AUROC gain > shuffled; would fail for a label-ignoring model. Not vacuous.
- aggregate_l7 "controls" block: vacuous for frozen (D4).
- enrich planted/null controls: cannot detect clustering (D9).
- ladder P-K/P-offset/P-edit planted tests assert effects >0.15-0.3 against shuffled-K; adequate. The ladder aggregator test (test_ladder.py:154) is weakened by the `or` (D11).
- T2 planted1/planted2 (run_acq.py) use the real Kphys as a (non-informative) prior, which is the right negative control for `prov`; acceptance thresholds are not enforced anywhere in code (reported only).

## What I did not verify
ihlm/model.py net/training code, ihlm_v2 adapter, p0_intrinsic, stratification annotate/mmp/cliffs/feat_analysis, retro_recovery gating scripts 01-18,20-24 and chem.py, run_l7a_llm.py (LLM runner; only its `subset` equality is covered by a test), loop_models.py adapters (HF/LoRA/GP internals). test_l7a.py core and test_l5/test_loop_* were not run to completion.
