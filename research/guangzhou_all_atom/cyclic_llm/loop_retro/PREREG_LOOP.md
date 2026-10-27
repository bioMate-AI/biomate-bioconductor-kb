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
