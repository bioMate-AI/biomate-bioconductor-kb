# PD-L1 blockade macrocycles — generation G1 (sequences to order/screen)

**Date:** 2026-10-13 · Single-target PD-L1 blockade (PD-1/PD-L1 PPI block). Design: amphipathic head-to-tail
macrocycle (11–13 aa) presenting an aromatic/hydrophobic face to the PD-1-binding cleft of PD-L1, one D-Pro
turn + one N-methyl for rigidity/plasma stability, **no chelator handle** (blocker, not radioligand). All passed
a developability filter (no NG/NS deamidation, no DG/DS isomerization, no free Cys, no Met, net charge in range,
no ≥4 hydrophobic run). Generator: `cyclic_llm`-style sampler, seed 20261013; data in
`research/guangzhou_all_atom/results/pdl1_g1_candidates.json`.

**Honest status — PRE-DOCKING design candidates.** PD-L1 is a discontinuous interface with no linear motif, so
no rule guarantees binding. These are screening/docking inputs, not validated binders. Two legitimate ways to
use them: (a) dock + rank to prioritize a few before ordering, or (b) order the diverse set and screen
empirically in the PD-1/PD-L1 competition assay (reasonable here precisely because there is no motif to design to).

## New candidates (G1)
| id | HELM | len | arom | net chg |
|---|---|---|---|---|
| PDL1-G1-01 | `cyclo(V-N-[2Nal]-K-W-R-[2Nal]-[NMeF]-N-[dP]-[2Nal]-T)` | 12 | 5 | +2.0 |
| PDL1-G1-02 | `cyclo(L-[dP]-R-Y-E-F-N-V-R-[2Nal]-[NMeF]-Q)` | 12 | 4 | +1.0 |
| PDL1-G1-03 | `cyclo(V-Q-Y-D-L-R-[2Nal]-[NMeW]-D-V-[dP]-H-[2Nal])` | 13 | 4 | −0.5 |
| PDL1-G1-04 | `cyclo(W-H-L-R-[2Nal]-[dP]-S-V-E-[NMeI]-[2Nal]-Q-Y)` | 13 | 4 | +0.5 |
| PDL1-G1-05 | `cyclo([2Nal]-Q-F-H-[dP]-F-E-V-[NMeL]-S-Y)` | 11 | 4 | −0.5 |
| PDL1-G1-06 | `cyclo(Y-S-[NMeW]-F-D-I-[dP]-T-W-H-L)` | 11 | 4 | −0.5 |
| PDL1-G1-07 | `cyclo([NMeF]-L-Q-I-D-L-T-L-S-[2Nal]-[dP]-Q-[2Nal])` | 13 | 3 | −1.0 |
| PDL1-G1-08 | `cyclo(V-K-[NMeF]-[dP]-F-Q-I-N-Y-H-L)` | 11 | 3 | +1.5 |
| PDL1-G1-09 | `cyclo(V-K-W-[NMeI]-N-I-D-I-E-Y-[dP]-Q)` | 12 | 2 | −1.0 |
| PDL1-G1-10 | `cyclo(I-H-[2Nal]-T-I-[dP]-R-[2Nal]-[NMeI]-T-L)` | 11 | 2 | +1.5 |

## Prior Round-3 (re-checked, liability-clean)
| id | HELM | arom | net chg |
|---|---|---|---|
| PDL1-K-01 | `cyclo(F-W-L-[dP]-Y-S-[NMeF]-D-T-K)` | 4 | 0 |
| PDL1-K-02 | `cyclo(W-[Nle]-F-[dP]-I-[NMeL]-S-E-K-G)` | 2 | 0 |
| PDL1-K-05 | `cyclo(W-Y-F-[dP]-L-[NMeI]-T-E-N-K-S-G)` | 3 | 0 |

**Legend (full stereochem):** upper-case = L-α-amino acid; `[dP]` = D-Pro; `[NMeX]` = Nα-methyl-X;
`[2Nal]` = L-3-(2-naphthyl)alanine; `[Nle]` = norleucine. Cyclization = head-to-tail backbone lactam.
≥95% HPLC, ESI-MS confirmation, acetate salt. No radiolabel / no chelator.

## Recommended before/at order
- A published BMS macrocyclic-peptide PD-L1 control in the same screen (source-verify sequence/IC50, no fabrication) — anchors the competition assay.
- PD-L2 counter-screen for selectivity.
