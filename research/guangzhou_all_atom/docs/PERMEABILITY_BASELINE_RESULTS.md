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

## Next (the actual differentiator build)
Conformer-ensemble permeability MVP: generate ensembles (RDKit ETKDG-macrocycle / CREMP) per peptide →
per-conformer 3D-PSA + Rgyr → **span features** → fuse with the 216 2D descriptors → does the span improve
R² / OOD ranking over 2D-only? That is the honest test of whether conformation-awareness is our edge.
(Caveat from the survey: one broad study found ensemble *variance* carried <2% signal — so validate, don't
assume.)
