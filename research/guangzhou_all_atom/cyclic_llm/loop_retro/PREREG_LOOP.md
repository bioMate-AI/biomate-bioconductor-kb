# PRE-REGISTRATION: retrospective closed loop on real measured cyclic-peptide permeability (committed 2026-10-27 BEFORE any run)

Question: does a model-guided design-test-learn loop find more permeable cyclic peptides per experiment than random selection, when each "assay" result is a REAL measurement
(CycPeptMPDB, PAMPA rows) revealed only after the loop selects that peptide? No wet lab is needed: the held-back labels play the assay. This is the standard retrospective
active-learning benchmark; it tests the loop's selection/learning logic, not wet-lab behaviour (stated limitation).

Data: `data/raw/CycPeptMPDB_Peptide_All.csv`, rows with PAMPA permeability (column `Permeability`, log Papp, valid number, not the -10.0 detection-floor sentinel). Duplicate
structures (same `Structurally_Unique_ID`) collapsed to the mean. Features: Morgan count fingerprint (r=2, 2048) from SMILES.
Hit definition (fixed a priori): Permeability >= the 90th percentile of the pool (top 10 %).
Loop: start with 100 labeled peptides; 10 rounds x 50 picks (total 600 labeled). Model: bootstrap ensemble of 5 HistGradientBoostingRegressors, retrained each round.
Policies: RANDOM; GREEDY (highest predicted mean); UCB (mean + 1.0 x ensemble std). Reference: ORACLE (picks true top). 30 seeds (seed controls the initial 100 and the bootstrap).
Two regimes, both reported:
 (A) IID: initial 100 drawn at random from the whole pool.
 (B) SHIFT: initial 100 drawn only from the 2 largest `Source` groups; the pool is scaffold-disjoint (Murcko scaffold) from the initial set, i.e. the loop starts on chemistry it must extrapolate from.
Primary metric: cumulative hits found in the 500 loop picks (excluding the 100 seed labels). Paired differences across seeds (same initial set), 95 % percentile bootstrap CI over seeds.
Claim rule: "the loop beats random" requires GREEDY or UCB minus RANDOM CI lower bound > 0 in BOTH regimes. A null or negative result in regime B is reported as such.
No tuning of the hit threshold, model, batch size or ucb weight after seeing results. Changes only as dated amendments.
Second experiment (display NGS, separate pre-registration to follow): same loop on PADI4 round-trajectory labels with Hamming-family-disjoint pool and the k-mer baseline as the bar.

## Amendment L1 (2026-10-27) — knowledge arm; declared BEFORE the first loop result was read
The fingerprint-only run (above) is still computing. We add ONE arm, run on the same seeds/regimes/outcome: "knowledge-augmented" = Morgan count fingerprint (2048) PLUS literature-derived permeability descriptors computed from the SMILES with RDKit: molecular weight, TPSA, H-bond donors, H-bond acceptors, Crippen logP, rotatable bonds, N-methylated amide count, ring size, heavy-atom count, fraction of sp3 carbons (the descriptors named in beyond-rule-of-5 / cyclic-peptide permeability literature).
Policies unchanged (random, greedy, uncertainty-aware, oracle). Question: does adding rule/knowledge features raise hits found in 500 picks vs fingerprint-only (paired over seeds, 95% CI), in regime A and regime B.
Claim rule: "knowledge helps" requires the CI of (knowledge-arm minus fingerprint-arm) for greedy or uncertainty-aware to exclude zero in BOTH regimes; otherwise reported as not supported. No other feature sets will be tried.

## RESULT (2026-10-27; all 120 tasks complete; aggregated once with aggregate_loop.py; nothing changed after reading)
Fingerprint arm, hits in 500 loop picks (mean over 30 seeds): regime A random 49.9, greedy 396.7, uncertainty-aware 395.4; regime B random 106.6, greedy 366.7, uncertainty-aware 371.5; oracle 500 by construction.
Primary claim (greedy or uncertainty-aware beats random, CI lower bound > 0, in BOTH regimes): SUPPORTED. greedy - random: A +346.8 [280, 389]; B +260.1 [125, 318].
Amendment L1 (knowledge arm = fingerprints + 10 literature permeability descriptors, minus fingerprint-only): NOT SUPPORTED. greedy: A +21.3 [-11, 63]; B -39.7 [-211, 113]; uncertainty-aware: A +16.1 [-17, 45]; B -24.3 [-177, 54].
EXPLORATORY, not pre-registered (results/rule_baseline.json): zero-learning rules that rank the pool by one descriptor and take the top 500 find: N-methyl count A 276.3, B 304.0; low TPSA A 93.3, B 51.7; high logP A 29.6, B 42.6; low HBD A 33.7, B 5.4. A single classical rule (N-methylation) therefore recovers about 70 % (A) and 83 % (B) of the learned loop's yield.
Files: results/loop_result.json, results/loop_res/ (120 per-task files), results/rule_baseline.json.

## Amendment L2 (2026-10-27) — knowledge as PRIOR / FUSION in the loop; declared BEFORE any L2 run; motivated by a challenge to the L1 reading
Why: L1 tested only descriptor columns appended to a 2,058-feature regressor (not supported). That does not test knowledge in the role it plays in practice (prior and gate steering early rounds). Observed facts that motivate L2 (disclosed): a one-line N-methyl rule alone recovered 70-83 % of the loop's yield; the fingerprint already encodes much of the same chemistry.
Knowledge scores (computed from SMILES only, no labels; z-scored over the pool, an unsupervised statistic):
 K_nme = N-methylated amide count (named after seeing the baseline result: EXPLORATORY choice, disclosed);
 K_z   = z(N-methyl count) - z(H-bond donors) - z(TPSA), equal weights, chosen a priori from the cyclic-peptide permeability literature (no logP term).
Integration modes (greedy policy only; model = same 5-member gradient-boosting ensemble on fingerprints):
 resid_K: fit y = a*K + b by least squares on the labelled peptides each round, learn the ensemble on the residual, rank by a*K + b + ensemble residual prediction (knowledge as prior mean, data as correction).
 fuse_K : rank by (1-w)*z(model prediction) + w*z(K) over the unlabelled pool, w = 100/(100 + n_labelled) (knowledge weight fades as labels accumulate).
Arms: resid_nme, resid_z, fuse_nme, fuse_z, plus fp (fingerprint-only greedy re-run, same seeds, WITH per-round hits). Same regimes (A in-distribution, B scaffold-shifted), 30 seeds, same hit definition, same 10 rounds x 50 picks.
Outcomes: PRIMARY = hits in 500 picks; SECONDARY (cold start) = hits in the first 200 picks. Paired differences vs fp over seeds. Because 4 knowledge arms are compared, intervals are 98.75 % percentile (1 - 0.05/4); a claim "knowledge as prior/fusion helps" requires at least one arm with interval lower bound > 0 in BOTH regimes at 500 picks. Also reported: all 4 arms, both regimes, both outcomes.
No other knowledge scores or modes will be added after the first L2 result is read.
