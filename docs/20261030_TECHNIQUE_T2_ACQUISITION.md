# Technique sprint T2 — provenance-aware acquisition for the closed loop (2026-10-30)

Owner: fork T2. Files: `research/guangzhou_all_atom/cyclic_llm/technique_sprint/acquisition/` and this document. Read-only dependence on `loop_retro/` (imports `run_loop`, `run_loop_par`, `run_loop_prior`; `setup_L` is copied and tested for equality against `run_l7a.setup_L`). **Part 1 below is the pre-registration, committed BEFORE any scored run; results (Part 2) are appended after the runs. Nothing in Part 1 is edited after its commit; changes are dated amendments.**

## Part 1 — Pre-registration

### 1.1 Problem (measured, not hypothesised)
L5 (`PREREG_LOOP.md`, `docs/20261028_LOOP_L5_RESULTS.md`): the greedy loop's in-distribution picks concentrate in the largest source (69 % of picks from a source holding 41 % of peptides); a zero-learning physchem rule ties the loop under scaffold shift (52.8 vs 52.3); scaffold-shifted gain over random is +22.2 (−1.6, 44.1) so L5 claim C1 is not met. Hit yield may therefore reflect *locating one laboratory's series*, not learning SAR.

### 1.2 Hypothesis
An acquisition function that is (i) **diversity- and provenance-aware** (within-batch similarity penalty; per-source cap per round; per-flat-structure cumulative cap) and (ii) **uncertainty-aware with an early knowledge prior** (ensemble mean + c·SD, fused with the leak-free textbook physchem prior K_phys with weight w_n = n0/(n0+n)) gives
- **H-T2-a:** higher yield per label than the best of {greedy, UCB, K_phys rule} in the scaffold-shifted regime (B) or the leave-labs-out regime (L);
- **H-T2-b:** without losing in-distribution (A) yield beyond a 10 % margin;
- **H-T2-c:** with lower concentration of picks (higher source entropy, lower top-source share) in A, B and L.

### 1.3 Data, loop and regimes (identical to L5 / L7f unless stated)
CycPeptMPDB, PAMPA label column, chirality-aware Morgan count fingerprints (`FP_CHIRAL=1`, `LABEL_COL=PAMPA`), labels standardised within source (`source_normalize`, groups < 20 pooled). Loop: N_INIT = 100, 10 rounds × 50, ensemble of 5 bootstrap HistGradientBoosting regressors (`R.fit_ens`), RNG `np.random.default_rng(seed)`. Hit definition 1 (primary): y ≥ pooled 90th percentile of within-source-standardised labels; definition 2 (sensitivity): y ≥ within-group 90th percentile (per-group threshold, as L5 addendum). Regimes: **A** (iid), **B** (scaffold-shifted from the two largest sources, `P.setup`), **L** (leave-labs-out: `setup_L` of L7f — loop pool and initial set from training sources only; held-out labs never revealed), **C** (sensitivity: pool excludes stereo-free duplicates of the initial set, `P.setup` regime C). Primary regimes A, B, L; C descriptive. Seeds: **evaluation 0–29** (paired with L5/L7 seeds and pools), **development 100–104** (hyperparameter selection only), **debugging ≥ 900** (never reported). Scope: PAMPA permeability only.

### 1.4 Arms (all paired by seed, init and pool)
| arm | selection score on the pool U at each round |
|---|---|
| `random` | rng.random (as L5) |
| `greedy` | ensemble mean μ (as L5 `fp`) |
| `ucb` | μ + 1.0·σ (σ = ensemble SD, ddof 0; as L5 UCB_W) |
| `rule_phys` | K_phys (equal-weight mean of source-standardised −TPSA, −HBD, +logP; L7f; no label-mined parameter) + 1e-6·random tie-break |
| `nn_greedy` | similarity-weighted mean label of the 5 most similar revealed peptides (binary Tanimoto on chirality-aware fingerprint bits) |
| `fuse` (prior fusion only) | (1−w_n)·z(μ) + w_n·z(K_phys), w_n = 100/(100+n_labelled) (as L5 fuse) |
| `div` (diversity only) | z(μ) with the diversity-aware batch selection of 1.5 |
| `prov` (full) | (1−w_n)·z(μ + 1.0·σ) + w_n·z(K_phys), with the diversity-aware batch selection of 1.5 |
z(·) = z-score over the current candidate set U. Ablation contrasts (descriptive): prov − fuse (diversity+UCB), prov − div, prov − ucb.

### 1.5 Diversity-aware batch selection (used by `div` and `prov`)
Sequential selection of the 50 picks of a round: at step t choose argmax over eligible candidates i of `s_i − λ·m_i`, where m_i = max Tanimoto similarity (binary fingerprint bits, chirality-aware) between i and the picks already made **in this batch** (0 for the first pick). Eligible: fewer than `cap_src` picks from i's source in this batch, and fewer than `cap_flat` cumulative picks (all rounds, excluding the initial set) from i's stereo-free flat structure. If no eligible candidate remains, the caps are relaxed for the remaining picks (best score first). Ties broken by index (deterministic). Hyperparameters (λ, cap_src, cap_flat) are chosen on the development seeds (1.6) and frozen.

### 1.6 Hyperparameter protocol (development seeds only; frozen before the evaluation run)
Grid: λ ∈ {0, 0.5, 1.0} × cap_src ∈ {50 (= none), 25} × cap_flat ∈ {∞, 5} = 12 configurations of `prov` (λ=0, none, ∞ is the no-diversity UCB+prior ablation), run in regimes A, B, L on development seeds 100–104 against `greedy` on the same seeds. **Selection rule (fixed now):** let rel_R(config) = mean over dev seeds of hits_prov / hits_greedy in regime R. Choose the configuration maximising mean(rel_B, rel_L) subject to rel_A ≥ 0.90; ties by higher mean pick-source entropy; if no configuration satisfies the constraint, choose the one with the highest rel_A and record that the constraint failed. The chosen configuration is written to `frozen_config.json` and committed before any evaluation seed (0–29) of any new arm is run. The same configuration is used for `div` (diversity only) and for every control. No other hyperparameter is tuned (c = 1.0, n0 = 100, k = 5 for `nn_greedy` are fixed here).

### 1.7 Metrics
Per task: hits per round (def. 1) and cumulative; hits (def. 2); the 500 picks (indices) for provenance. Derived: **source entropy** (Shannon, nats) of the pick distribution over sources; **top-source share**; share from 2020_Townsend + 2021_Kelly; **flat-structure entropy** and **number of distinct flat structures** among picks; **labels-to-X** (smallest number of labels at which cumulative hits ≥ X for X ∈ {50, 100, 150}; mean over seeds that reach it and the fraction reaching it); per-round learning curve. Regime L only (descriptive): **held-out transfer** — a final ensemble fitted on all revealed labels (initial set + 500 picks) is scored on E (800 peptides from held-out labs, `make_eval_slice`, never revealed): pooled Spearman with within-source-standardised labels and mean per-source Spearman over held-out sources with ≥ 15 peptides in E.

### 1.8 Statistics and decision rules
Seed-paired differences; **primary interval = 99 % percentile bootstrap CI of the mean paired difference** (resample the 30 seeds, B = 10 000, fixed RNG seed 20261030). The L5-style 99 % spread of the difference distribution is also reported (descriptive, wider). For each regime the **best baseline** is the arm among {greedy, ucb, rule_phys} with the highest mean hits in that regime on the evaluation seeds (an ex-post choice that favours the baseline; conservative).
- **S1 (yield):** in regime B or L: relative gain (mean diff / mean hits of the best baseline) ≥ 0.05 AND CI lower bound > 0. 
- **S2 (non-inferiority in A):** lower 99 % bound of (hits_prov − hits_best) ≥ −0.10 × mean hits_best.
- **S3 (concentration):** in each of A, B and L: lower 99 % bound of (source entropy_prov − source entropy_greedy) > 0 AND upper 99 % bound of (top-source share_prov − top-source share_greedy) < 0.
**Supported = S1 ∧ S2 ∧ S3.** **Kill criterion (registered): S1 fails in both B and L → the technique is reported as a null for yield and no yield claim is made.** If S1 holds but S2 or S3 fails, it is reported as partial with the failing criterion named. Second hit definition and regime C are sensitivity analyses (same machinery, no decision role).

### 1.9 Controls (all with the frozen configuration; failure of a control means debugging our code, not retuning)
- **C1 planted series (positive control, synthetic labels on the real fingerprints, seeds 900–904, regime A):** labels = standard-normal noise + 3.0 for members of hidden series. P1: one series of ≥ 200 members inside the largest source (peptides with one chosen mid-frequency fingerprint bit set). P2: three series (≥ 80 members each) in three different sources. Pass: (a) greedy hits ≥ 3× random in P1 and P2 (otherwise the control is invalid and is debugged); (b) prov hits ≥ 0.8 × greedy hits in P1 and P2, and prov recovers ≥ 0.8 × greedy's recall of planted members in every series of P2 — i.e. diversity does not suppress genuine multi-series signal. 
- **C2 shuffled labels:** labels permuted within source (seeds 2000–2009, regimes A and B; arms random, greedy, prov). Pass: (prov − random) and (greedy − random) 95 % CIs include 0; a gain indicates a leak and is investigated as our bug.
- **C3 near-duplicate sensitivity:** regime C on seeds 0–29 (arms random, greedy, ucb, rule_phys, prov): same contrasts, flat-structure entropy; descriptive.
- **C4 reproduction audit (before the evaluation run):** `greedy` and `random` reproduce the stored L5 `fp` and `random` per-round hits exactly for regimes A and B on seeds 0–2 (`res5` on S3, read-only); otherwise our runner is wrong and is fixed before anything else.
- **C5 unit tests:** caps are respected; λ = 0 without caps reproduces the UCB+prior selection; the copied `setup_L` equals `run_l7a.setup_L`; the binary Tanimoto equals RDKit's on random pairs; K_phys formula equals L7f's.

### 1.10 Compute
CPU only, spot, per-task S3 checkpointing (L5 pattern), tag `project=cyclic-selector`, instances terminated when done; no paid APIs. Cost is estimated from timed debug tasks (seeds ≥ 900) before launch and recorded here.

### 1.11 Known limitations (declared now)
One finite dataset (6,960 peptides): development and evaluation seeds draw different initial sets/held-out labs from the same library, so selection on development seeds does not make the evaluation seeds independent of the data. PAMPA permeability only. Two source labs dominate hits (L5 audit). A retrospective replay can only reveal already-measured compounds; it cannot test novel-molecule generation. The hit definition's composition effect (2020_Townsend hit rate 12.8 % vs nominal 10 %) is unchanged from L5.

## Part 1 addendum A1 (before any scored run) — error log, preflight outcome
- **Preflight (spot c5.4xlarge, 2026-10-28 ~13:00–13:26 UTC): C4 reproduction PASS** — `greedy` and `random` reproduce stored L5 `fp`/`random` per-round hits exactly in 12/12 cases (regimes A, B; seeds 0–2; pool sizes equal) (`res_preflight/repro.json`). Aggregator decision-rule tests (synthetic known verdicts) PASS.
- **Our bug, fixed:** the C5 planted-series unit test failed its validity assertion (greedy 99 vs random 52 hits; required ≥ 3×) because the synthetic fixture defined hits by a 10 % quantile, which caps greedy/random below ~3× for a small series. Per 1.9 C1(a) this is a fixture error, not a result; fixture changed to an absolute threshold on the noise scale (series prevalence ≈ 5 %, 3000 peptides, effect 4.0); the pre-registered criterion (≥ 3×) is unchanged. A first aggregator bug (crash when a result lacks a metric) was found by the positive-control test and fixed (`arr()` skips missing metrics instead of failing or zero-filling).
- **Compute:** CPU spot; `--procs` now `$(nproc)`; development grid, baseline evaluation (regimes A,B and L,C) and the unit test run as parallel stages; `prov`/`div` evaluation and controls wait for the frozen config.
