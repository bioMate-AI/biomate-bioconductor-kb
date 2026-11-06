# Baseline (fingerprint GBM) error analysis — CycPeptMPDB, within-source labels (2026-10-29)
Method: HistGradientBoosting (150 iterations, lr 0.1), 2,048-bit Morgan count fingerprints radius 2, labels = within-source z-scored permeability (PREREG_LOOP L3 grouping), 6,960 peptides; 5-fold CV random vs grouped by flat structure (GroupKFold); chirality-blind (useChirality=False, as in L3) vs chirality-aware (useChirality=True). Script: scratchpad `err_analysis.py` (diagnostic; not a registered result). Caveat: CV state differs from the loop's selection-biased state.

## Results
| quantity | blind | chiral |
|---|---|---|
| distinct fingerprints (of 6,960; 2,460 flat structures) | 2,380 | 6,583 |
| Spearman, random 5-fold CV | 0.713 | 0.766 |
| Spearman, CV grouped by flat structure | 0.663 | 0.712 |
| within-flat-group Spearman under CV | −0.386 | +0.259 |
Near-duplicate inflation (random vs grouped CV) is about 0.05 Spearman for both. Chirality-aware features add about +0.05 overall.

**Correction found while analysing (important).** The blind model's within-group −0.386 is a leave-out artifact: a predictor equal to the mean of the OTHER members of a flat group has within-group Spearman exactly −1.000 (verified on the 340 groups with ≥3 members and nonzero label variance; random scores give −0.025). So "within-group ranking is chance by construction for flat features" holds only when each group is split ONCE into revealed and target members (target members then receive identical blind predictions, ties → 0). The within-group metric must be implemented that way (fixed seeded split per group; evaluate ranking among target members only; also report the revealed-mean reference). The +0.259 (chiral) vs −0.386 (blind) gap above is therefore not interpretable as a stereo effect size.

**By source (blind, random CV):** Townsend n=2,881 MAE 0.53 ρ 0.72; Kelly n=1,518 MAE 0.54 ρ 0.66; CHUGAI n=878 MAE 0.38 ρ 0.72; Furukawa n=662 MAE 0.42 ρ 0.82; **Faris n=207 MAE 0.74 ρ 0.49; Bhardwaj n=133 MAE 0.71 ρ 0.42** — the small, recent, structurally diverse sources are worst.
**By N-methyl count:** MAE 0.53 (0), 0.53 (1–2), 0.54 (3–4), **0.37 (>4)** — N-methyl-rich peptides are easiest. By ring size and size: MAE 0.40–0.54, no strong pattern (largest-size bin 0.50).
**Activity cliffs:** 88,810 pairs share an identical blind fingerprint; 28 % of them (24,483) differ by >1 SD in label — pairs the blind model cannot separate at all.
**Worst-300 errors:** 74 % lie in multi-member flat groups (71 % of all peptides do) and 68 % come from the top-2 sources (63 % of peptides) — the worst errors are NOT concentrated in stereoisomer groups or in the dominant sources.

## What this means for the hypotheses
1. The baseline is already strong (Spearman 0.66–0.77) and chirality-aware fingerprints improve it by about 0.05 overall: the fair stereo opponent is a chirality-aware GBM, and a stereo effect on aggregate error is modest.
2. Where headroom plausibly exists: small/diverse sources (ρ 0.42–0.49) — consistent with H1/H4 (prior + transfer help when per-source data are scarce) — and the 28 % identical-fingerprint cliff pairs (H2, with the corrected metric).
3. Errors are broadly distributed, not dominated by one subgroup; an LLM advantage must show up as shifted learning curves and on low-data sources, not on the dominant series.
