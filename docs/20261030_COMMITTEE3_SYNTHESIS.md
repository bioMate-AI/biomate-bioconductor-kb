# Committee round 3 — consolidated synthesis (2026-10-28 evening)
Sources: three independent internal Claude reviews (`docs/committee_raw/20261030c/review_{code,data_eval,manuscript}.md`, reviewers given the repo, not our conclusions) and the external round (GPT-5.5, Gemini 3.1 Pro, Claude Sonnet 4.6; `docs/20261030_COMMITTEE3_EXTERNAL_SYNTHESIS.md`; counted spend USD 0.824 of the 1.50 cap; no Opus attempt). Status words: CONFIRMED = checked against the repo by a reviewer or by us; REPORTED = one reviewer's claim, not yet re-checked by us.

## Verdicts
Main draft: **reject** (referee). Reframed v2 (evaluation/controls): **major revision**, the stronger framing; venue fit per referee: JCIM / J Cheminformatics / Digital Discovery or a workshop; not a benchmark venue (no valid benchmark is released). Numbers: 12/12 (referee) and 15/16 (data reviewer; one partial: within-lab SD 0.706–0.757 vs stated 0.740) spot checks match committed files. The problems are interpretation and design, not transcription.

## Convergent findings (two or more independent sources)
1. **The headline loop gain (P1, +186) rests on transductive source standardisation** (referee, code, all three external; disclosed in abstract/App. E but still the lead number). Raw hit rate 1.8 % in the two largest labs vs 24.4 % elsewhere; after normalisation 11.9 % vs 6.8 % (code). Regimes B/L therefore never face the lab-offset shift. Action: demote from abstract until a causal arm exists; note the loop causal arm is NOT in L7q (no causal mode in `run_l7a.py`); T2 `evalc` is the acquisition technique's causal arm, not the L7 headline.
2. **Interval type.** The L5 "interval" is a spread of per-seed differences, not a CI (code, referee): regime B loop−random spread [−1.6, 44.1] vs bootstrap CI of the mean [17.7, 26.5]; "every knowledge interval includes 0" fails for five rows under CI-of-mean. Percentile bootstrap at n=10 covers 0.894; no Holm/BH over the grid. Action: state interval type per claim; report both.
3. **Regimes do not test what their names say** (data, referee, external). L: loop pool is all training labs, only the held-out evaluation set uses unseen labs, CHUGAI and Furukawa-2016 held out in 10/10 seeds. C: 26.9 % of pool still Tanimoto ≥ 0.9 to an initial peptide, so the Discussion line "survives near-duplicate removal" is wrong. B shifts scaffold, not laboratory. Action: fix wording now; B2/C2/L9 (planned) are the repair.
4. **"Lab" means paper** (Source id; data). 0.22 leave-labs-out is an upper bound on cross-lab skill. Random CV → flat-grouped drop is only 0.711 → 0.670, so most of 0.67 → 0.22 is lab/series structure.
5. **Controls that cannot fail / missing controls** (code: frozen arm gain is 0 by construction; shuffled passes on a large negative gain; external: source-matched random control exists in code but has no result). Without it, "finds the productive laboratory" is not separated from learning.
6. **Frozen T2 config makes `div` identical to `greedy`** (code, T2 fork): the `div` evaluation arm adds no information; do not describe prov−div as a diversity ablation.
7. **Replay supports only "model-guided selection in a fixed labelled library"** (data, referee), not claims about generative loops; Townsend supplies 52.8 % of hits. In regime L the frozen model alone gets about 201 of 500 picks vs about 62 random (referee, REPORTED): most of the +186 would be the pretrained start; physchem loop − frozen is +4.9 (−4.4, 14.1).
8. **Analysis-I benchmark is not valid and not fixable by stats** (data, referee): censoring alone gives inverted AUROC 0.79; ChEMBL pretraining corpus holds 72 % of inactives vs 50 % of positives; ±0.05 margin post hoc; folds_v2 has two single-family folds holding 72 % of rows; no sequence-identity clustering.
9. **Anchor-design simulation D1 is a toy** (data): constant lab shift, weakly identified tau (CI [0.32, 0.84]). Its "no design reaches power 0.80" is conditional on that.

## Single-source findings (REPORTED)
- Loader fragility: aware/blind GBM provenance only in directory names; `collect_l7.sh` would drop res7k/m/q; silent overwrites in ladder/LLM/small loaders; one-shot cluster contrast never computed (code).
- Vacuous assertions: `test_l7a.py:205`, `test_a2.py:83`, `test_ihlm_v2.py:116`; weakened `or` in `test_ladder.py:154` (code).
- Launch scripts mask failures: bare `wait` ignores exit codes, DONE written unconditionally (code; we hit this twice today).
- Stratification enrichment p-values assume independent peptides (code).
- **K_phys offline row (median rho 0.252, p 5e-5) is probably pre-source-fix** (external fork): kb_audit results were committed before the 19:16 source fix. Action: rerun or label.
- C2 rerun does not reproduce the logged result; one bootstrap CI excludes its own point estimate (data).
- Fusion weight counts the initial 100 labels (starts at 0.5): undocumented convention (external).
- Missing prior art (referee, names to be verified by us before citing): Sieg 2019, Kalliokoski 2013, Landrum & Riniker 2024, GAUCHE, Graff 2021.

## Refuted by the external fork's check (not defects)
Stale `s` in frozen branch; fold map not keyed by family; duplicate (target, compound) rows in analysis I (0 of 9,432); initial structures not counted in the cap (by specification); zero stereo siblings (by construction). Gemini's claim that the `causal_z` variance shrinkage is "mathematically incorrect": UNCHECKABLE (matches pre-registered A2; GPT and Sonnet found no defect; no result depends on it yet).

## What the referee says is genuinely contributed
The equivalence-style validity gate and the leak-aware replay protocol (family-/lab-aware, source-aware standardisation findings). Suggested deletions from the paper: IH-LM, T2, anchors, fusion, the API arms, the 54-contrast K_phys analysis and process narrative. Missing analyses demanded: causal arm on ≥ 30 seeds; in-loop baselines (frozen, nearest neighbour, rule, Tanimoto-kernel GP with UCB); hits-by-source decomposition; t-interval/mixed-model inference; inter-lab noise ceiling from the 21 shared peptides; a second dataset; exact-Ki/Kd binding analysis.

## Tension with the owner's stated bar
"Innovation or no publication": after this review the delivered, audited contributions are evaluation techniques; the technique candidates (fusion, anchors, T2) are null/pending; IH-LM has no performance claim and the central comparison is not run. The committee's recommendation (v2, evaluation paper) is consistent with the evidence but not with an innovation-first framing. This is the owner's decision.

## Owner decisions this review makes concrete
1. Framing: v2 (recommended by referee and consistent with all external reviewers) vs main.
2. Prune IH-LM/T2/anchor/fusion/API material from the paper (referee) or keep as a short "planned" section.
3. Whether to run a causal L7 arm (≥ 30 seeds, spot CPU, order USD 5–10; needs a code mode that does not exist yet) before midnight or leave the headline demoted.
