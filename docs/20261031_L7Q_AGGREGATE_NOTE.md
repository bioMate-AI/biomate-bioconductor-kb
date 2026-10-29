# L7q re-aggregation: new frozen aggregate, completeness, determinism, K_phys vs shuffled-knowledge (2026-10-29 ~00:50 CDT; exploratory)

## Aggregate
- New `research/guangzhou_all_atom/cyclic_llm/loop_retro/results/l7_aggregate.json`, sha256 **12940022caa89c364a44d2cabc7401948d7a28cd139199a2ca48cf6c1fbf4ec8** (replaces e5da79e9ab27…ef13; the drafts still cite the old hash, so `qa_audit/verify_artifacts.py` fails exactly one check, "aggregate sha256 matches frozen file and drafts", until the writer folds this in).
- **Determinism:** two independent runs with the dataset (`--csv`, source-cluster contrasts) give identical sha256; two runs without `--csv` are also identical to each other (2afd866c…). The L7q runs are themselves deterministic (seeds 0–1, regime L, PYTHONHASHSEED 1 vs 2: identical, see L7 log).
- **Existing groups unchanged:** the 11 groups of the old aggregate are byte-identical (JSON-compared) in the new one; the LLM block is identical. 28 groups are new (below).
- **Collection bug fixed** (commit e515fd1c1): `collect_l7.sh` matched only `res7[af]_`, so res7k (confirmatory development), res7m (source-matched diagnostics), res7n (L9 sensitivity) and res7q (deterministic K_shuf) were never aggregated; the pattern is now `res7[a-z]_` excluding the LLM directory, with a regression test. New groups: `gbm_aware_confirm`, `gbm_aware_srcmatch`, `gbm_physchem_srcmatch`, `gbm_{aware,blind,physchem}_detK`, `gbm_aware_detK_confirm`, `chemberta_phys`, `atom_lm|A,B`, `chemberta|L`, and `gbm_physchem|M` (= the L9 sensitivity run, 7 files; not used in any draft table; the verifier's table checks are restricted to regimes A/B/L).
- **Verifier bug fixed:** `verify_artifacts.py` computed a cluster cell for every group before checking whether it is one of the tabled learners; groups with insufficient clusters (ci_cluster None) crashed it.

## Completeness (S3 listing vs expected)
res7q_gbm_aware 30/30, res7q_gbm_blind 30/30, res7q_gbm_phys 30/30 (10 seeds × regimes A, B, L), res7q_gbm_confirm 60/60 (aware, seeds 10–29 × A, B, L). `done.flag` written, instance i-0e2a95b93490b44b0 terminated. Not complete elsewhere: the atom-LM directories (res7f_atom_L_a/L_b/phys: 0 files; res7a_atom_lm 4), ChemBERTa L/B (5 files each) — those GPU jobs are not finished; groups built from them are n ≤ 5 and are NOT evidence.

## K_phys (textbook rule combination, `loop_kphys_sub`) vs deterministic shuffled knowledge (`loop_kshuf_sub`) vs plain loop (`loop_sub`) — EXPLORATORY
Unit: total hits over the rounds in the sub protocol (as `yield_total`). Seed-level paired contrasts: percentile bootstrap 95% CI of the mean over seeds; p = paired sign-flip test (exact for n = 10, Monte Carlo 20,000 for n = 20); Holm and BH within each contrast family (12 groups); file `results/kphys_multiplicity_l7q.json`, code `kphys_multiplicity.py`. Seeds are not independent across groups and (regime L) the same labs are held out in every seed, so the corrections are approximate.

K_phys − K_shuf (primary question; mean hits [95% seed-bootstrap CI]; Holm p):
| learner | A | B | L |
|---|---|---|---|
| aware, confirmatory seeds 10–29 (n = 20; new seeds) | +4.95 [2.95, 6.9]; 0.0055 | +4.85 [2.7, 7.1]; 0.0055 | +4.90 [3.6, 6.15]; 0.0006 |
| aware, development seeds 0–9 | +5.00 [3.3, 6.7]; 0.018 | +1.90 [0.2, 3.6]; 0.39 | +1.80 [−1.8, 5.7]; 1.0 |
| blind, seeds 0–9 | +6.00 [4.2, 7.8]; 0.018 | +4.10 [2.1, 5.9]; 0.068 | +5.20 [1.6, 9.3]; 0.16 |
| physchem, seeds 0–9 | +2.90 [0.2, 5.7]; 0.45 | +0.10 [−2.1, 2.4]; 1.0 | +0.50 [−2.3, 3.3]; 1.0 |

K_phys − plain loop (secondary): aware confirmatory +2.75 [0.55, 4.85] (Holm 0.21), +3.65 [2.25, 5.15] (Holm 0.0024), +1.25 [−0.4, 2.85] (1.0) for A, B, L; development and blind and physchem groups mostly include 0 after Holm (aware dev A +4.70, B +4.80 [Holm 0.078 and 0.043]; blind B +4.90 [0.11]).

Source-cluster contrasts (within-source Spearman of the final E scores, unit = held-out laboratory, `contrasts_cluster` in the aggregate): K_phys − K_shuf and K_phys − loop intervals include 0 in every group except physchem regime B, where K_phys is WORSE (−0.049 [−0.093, −0.013] vs K_shuf; −0.040 [−0.091, −0.000] vs loop).

**Plain statement.** With deterministic shuffled knowledge, the textbook K_phys loop picks about 5 more hits per run than the shuffled-knowledge loop in the chirality-aware and stereo-blind learners (replicated on 20 new seeds in all three regimes, Holm ≤ 0.0055), and not for the physchem learner. Two cautions: (1) the shuffled-knowledge arm is itself 1.2–3.7 hits BELOW the plain loop on the confirmatory seeds, so part of the K_phys − K_shuf contrast is harm from wrong knowledge; the gain over the plain loop is smaller (+1.3 to +3.7; significant after Holm only in regime B); (2) it is a yield effect only: the held-out ranking (source-cluster Spearman) does not improve, so the loop's model does not learn better, the rule-guided picks hit more often. Held-out labs are not independent across seeds in regime L, and transductive source standardisation applies here as in the rest of L7. The claim stays exploratory.

## Replaces / affects in the drafts (writer to fold in; I did not edit the drafts)
- The [REGEN-K] K_phys-vs-shuffled numbers (all K_shuf contrasts) → use the `*_detK*` groups above; the old K_shuf rows in `gbm_aware|A` etc. (res7f, set-iteration nondeterministic K_shuf) stay in the aggregate but must be labelled nondeterministic and not used for K_phys-vs-shuffled claims.
- The abstract/appendix statement that the K_phys loop effect is "unresolved pending L7q" can be replaced by the table above, labelled exploratory.
- New hash in every place that cites e5da79e9; the confirmatory seeds 10–29 become available as an independent check.
- Spend: the L7q resume instance ran about 2.7 h (21:36 → done flag by 00:18 CDT) at the script's quoted spot price of about USD 0.55/h, i.e. about USD 1.5 (estimate; no billing record read). This step added no new compute.
