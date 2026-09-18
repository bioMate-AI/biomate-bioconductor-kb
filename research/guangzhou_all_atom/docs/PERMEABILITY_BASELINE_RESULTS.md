# Permeability baseline — beat the R²=0.23 floor; static-descriptor ceiling confirmed

The differentiator track, step 1: fix the R²=0.23 permeability floor and establish the honest
static-descriptor ceiling on CycPeptMPDB (8466 cyclic peptides, `Permeability` = log Papp).
Code: `research/guangzhou_all_atom/permeability_baseline.sh`.

## Results (gradient-boosted trees on CycPeptMPDB features)
| feature set | split | HistGBM R² | Spearman | note |
|---|---|---|---|---|
| thin (Morgan-1024 + 10 desc) | random | 0.285 | 0.59 | beat the floor |
| thin | scaffold | 0.414 | 0.65 | (scaffold degenerate — see below) |
| **rich (216 precomputed desc incl 3D-PSA)** | random | **0.449** | **0.75** | approaching field |
| rich | scaffold | 0.406 | 0.69 | |

Prior baseline R²=0.231; field yardstick DMPNN R²≈0.555 (BenchmarkCycPeptMP).

## Honest findings
1. **The floor was features/model, not data** — rich descriptors nearly doubled R² over thin (0.29→0.45)
   and beat the prior 0.23. **Spearman 0.75** is genuinely usable for *ranking* designs by permeability.
2. **Static descriptors plateau ~0.45–0.5**, short of the field's ~0.55 (DMPNN learned features + CycPeptMP
   conformer augmentation win). This is the honest ceiling of the 2D approach.
3. **Scaffold ≈ random (0.41 vs 0.45)** — Murcko scaffolds are near-degenerate for macrocycles (all reduce
   to similar ring systems), so scaffold-splitting is NOT a meaningfully harder generalization test for this
   class. A sequence/composition-based split is needed for a true OOD number.

## Strategic conclusion (empirically confirmed)
The transfer survey said 2D models cap ~0.55 and the real lift is conformation-aware descriptors. This run
confirms it: even 216 descriptors (incl. single-conformer 3D-PSA, which helped reach 0.45) plateau. **The
genuine differentiator is the 3D-PSA "span" across a conformer ensemble** (the molecular-chameleon signal:
polar↔apolar reorganization a single conformer cannot capture). CycPeptMPDB ships single-conformer
3D-PSA; CREMP (staged, partial) provides ensembles.

## Differentiator experiment (conformer-ensemble span) — HONEST NEGATIVE result (2026-09-18)
Tested the hypothesis directly (898-peptide stratified subsample, shuffled 5-fold CV; RDKit
ETKDGv3-macrocycle 12-conformer ensembles; per-conformer polar-SASA 3D-PSA + Rgyr; span/mean/std features):
| model | R² | Spearman |
|---|---|---|
| 2D-only (216 desc) | 0.262 | 0.627 |
| 2D + ensemble-span | 0.246 | 0.594 |
| ensemble-span only | −0.226 | 0.139 |

**Cheap conformer-ensemble span does NOT add signal** (slightly hurt; span-only non-predictive) —
consistent with the survey's caution that ensemble *variance* carried <2% signal. **Knowing this for ~$0.5
prevents over-investing in the cheap path.**

**Caveat (do not over-conclude):** this refutes the CHEAP version, not the differentiator hypothesis. The
real chameleon signal needs (1) realistic **MD ensembles** (not ETKDG — even CycPeptMPDB's minimized 3D is
"unrealistic" per the survey) and (2) 3D-PSA span across **polar↔apolar environments** (water vs
membrane-like), not conformational spread in one condition. A proper test = MDML_PeptPerm-style
two-environment MD (~400 ns/peptide) — expensive, uncertain payoff (<2%-variance caveat).

## Honest strategic conclusion
- **Usable now:** the 2D-descriptor permeability ranker (R² 0.45 / Spearman 0.75 on full data) — good enough
  to rank designs in the loop.
- **Cheap conformation-awareness: does not help** (tested, negative).
- **Real conformation-awareness (two-environment MD): expensive with uncertain payoff** — defer unless a
  program milestone justifies it; learned representations (DMPNN, ~0.55) are a cheaper incremental option.

## Next (options, not obvious wins)
Conformer-ensemble permeability MVP: generate ensembles (RDKit ETKDG-macrocycle / CREMP) per peptide →
per-conformer 3D-PSA + Rgyr → **span features** → fuse with the 216 2D descriptors → does the span improve
R² / OOD ranking over 2D-only? That is the honest test of whether conformation-awareness is our edge.
(Caveat from the survey: one broad study found ensemble *variance* carried <2% signal — so validate, don't
assume.)
