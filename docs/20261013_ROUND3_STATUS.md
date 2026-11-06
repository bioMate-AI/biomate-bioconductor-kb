# Round-3 status — acceptance-gated αvβ6/PD-L1 (supersedes the withdrawn v2 order)

**Date:** 2026-10-13 · The v2 CRO order failed external review (0/8 αvβ6 pass hard gates — every one missing
the H5 chelator handle). Root cause: v2 was built against a prose critique, not the acceptance spec; the
"renal fix" removed the Lys that is the **mandatory single chelator handle** (published scaffold = N-methyl-Lys
at P9). Now operationalized as a gate and regenerated.

## WITHDRAWN
`results/CRO_SEND_v2.csv` / `docs/20261013_CRO_SEND_v2.csv` — **do NOT ship.** 0/8 αvβ6 pass H5 (no handle);
several fail H4 (broken aromatic flank). Kept for the record only.

## The gate (fix to "detect it yourself")
`cyclic_llm/acceptance_gate.py` operationalizes the sequence-evaluable αvβ6 hard gates (H1 RGD, H2 RGDL,
H3 turn+N-methyl, H4 aromatic flanks P1/P7∈{F,Y,W}, H5 single Lys handle + cyclic) + H8 FTO-genus flag.
Validated: it reproduces the review's **0/10 pass** on v2. v1.1 additions (chelator chemistry, control-
validation gate, multivalency, full-stereochem representation, renal flag, PD-L1 sink, constrained generation)
in `docs/20261013_acceptance_criteria_v1.1.yaml`.

## Round-3 αvβ6 — 8/8 pass H1–H5 + H4 (gate-verified)
Scaffold `cyclo(P1-R-G-D-L-P6-P7-[dP]-[NMeK])` — P1/P7 aromatic, P6 small (selectivity knob), **NMe-Lys P9 =
rigidity + single chelator handle**, exactly one Lys. Novelty varied at P1/P6/P7 (none is Trivehexin `YAY` or
avebehexin `FAF`):
| id | HELM | P1/P6/P7 |
|---|---|---|
| AVB6-R3-01 | cyclo(W-R-G-D-L-A-F-[dP]-[NMeK]) | W/A/F |
| AVB6-R3-02 | cyclo(F-R-G-D-L-A-W-[dP]-[NMeK]) | F/A/W |
| AVB6-R3-03 | cyclo(W-R-G-D-L-A-W-[dP]-[NMeK]) | W/A/W |
| AVB6-R3-04 | cyclo(Y-R-G-D-L-A-W-[dP]-[NMeK]) | Y/A/W |
| AVB6-R3-05 | cyclo(W-R-G-D-L-A-Y-[dP]-[NMeK]) | W/A/Y |
| AVB6-R3-06 | cyclo(Y-R-G-D-L-S-F-[dP]-[NMeK]) | Y/S/F |
| AVB6-R3-07 | cyclo(F-R-G-D-L-G-W-[dP]-[NMeK]) | F/G/W |
| AVB6-R3-08 | cyclo(W-R-G-D-L-S-F-[dP]-[NMeK]) | W/S/F |

## Round-3 PD-L1 — pass P2/P3 (class + single handle), provenance pending
K-05 `cyclo(W-Y-F-[dP]-L-[NMeI]-T-E-N-K-S-G)`, K-02 `cyclo(W-[Nle]-F-[dP]-I-[NMeL]-S-E-K-G)`, K-01
`cyclo(F-W-L-[dP]-Y-S-[NMeF]-D-T-K)` — each one Lys handle. (v2 K-07 dropped: no handle, P3 fail; K-03/K-04/K-08
remain committee NO-GO.)

## NOT yet synthesis-authorized — remaining gates before any CRO send
1. **H6/H7 (αvβ6 affinity + selectivity)** — dock vs αvβ6 AND αvβ8/αvβ3/αvβ5/α5β1, with the **controls in-batch**
   and the **control-validation gate (A2)**: pipeline must reproduce Trivehexin > avebehexin + known selectivity
   first. K1/K2/K3 apply.
2. **P1/P4 (PD-L1)** — docked PD-L1/PD-1 pose + ΔG, and PD-L1/PD-L2 (A6: + the expression-sink caveat).
3. **H8 / P5 FTO** — counsel opinion vs the TRIMT/Notni αvβ6 nonapeptide estate and the BMS PD-L1 estate
   (all Round-3 αvβ6 trip H8 — they are in the active genus by construction).
4. **X2 + A1** — score the **labeled construct** (peptide + DOTA/TRAP chelator), not the bare peptide.
5. **A3 valency** — decide monomer vs multivalent (Trivehexin is trimeric).

Round-3 clears the sequence-evaluable gates; synthesis waits on the docking + FTO + construct steps above.
