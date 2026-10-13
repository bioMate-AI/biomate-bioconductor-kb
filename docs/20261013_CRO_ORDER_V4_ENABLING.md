# CRO order v4 — the enabling order (controls + warhead), NOT a novelty bet

**Date:** 2026-10-13 · Supersedes the withdrawn v2 order. This is the order to send **today**. It is
deliberately small and honestly scoped: it is **not** a claim of a novel αvβ6 monomer (there isn't one to
make — see below). It is the enabling experiment that validates the binding/selectivity assay and sources the
targeting warhead for the construct program, which is where real differentiation lives.

## Why this is NOT a novelty order (the genus trap, acknowledged)
The acceptance gate fixes the scaffold `cyclo(P1-R-G-D-L-P6-P7-[dP]-[NMeK])` — which **is** the TRIMT/Notni
nonapeptide genus. Only P1/P6/P7 are free, and ncAA-decorated cyclic-RGD is one of the most heavily mined
scaffolds in the field (two decades of N-methyl/aromatic RGD SAR, cilengitide lineage). Point swaps in those
three slots are low-diversity, unmotivated, and almost certainly already explored. We will **not** spend CRO
budget pretending otherwise. Differentiation for this program lives at the **construct** level (multivalent
geometry, chelator–radionuclide pairing, the αvβ6×PD-L1 bispecific) + **indication** + the closed DMTA loop —
see `20261013_RULE_VS_NOVELTY_AND_PATH.md` and `20261013_TREATMENT_PROBLEMS_VS_SEQUENCE.md`.

## What is in the order (4 peptides) — `20261013_CRO_ORDER_V4_ENABLING.csv`
| id | role | HELM | purpose |
|---|---|---|---|
| CTRL-TRIVEHEXIN-mono | control | `cyclo(Y-R-G-D-L-A-Y-[dP]-[NMeK])` | A2 assay validation (pipeline must rank it ≥ avebehexin) |
| CTRL-AVEBEHEXIN | control | `cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])` | A2 assay validation, dynamic range + selectivity order |
| AVB6-R4-09 | warhead | `cyclo(W-R-G-D-L-A-F-[dP]-[NMeK])` | conservative warhead for the construct; P1 Phe→Trp, lowest risk |
| AVB6-R4-01 | sel-probe | `cyclo([2Nal]-R-G-D-L-A-F-[dP]-[NMeK])` | one exploratory αvβ6/αvβ8 flank-bulk SAR point (labeled, not novelty) |

All 4 pass `acceptance_gate.avb6_gate` H1–H5 (verified 12/12 in `results/round4_avb6_candidates.json`).

**Monomer legend (full stereochemistry, A4):** upper-case single letters = L-α-amino acids;
`[dP]` = D-proline; `[NMeK]` = Nα-methyl-L-lysine (backbone N-methyl → rigidity; side-chain ε-amine → the
single chelator handle); `[2Nal]` = L-3-(2-naphthyl)alanine. Cyclization = head-to-tail backbone lactam.

**Chelator (A1):** DOTA conjugated to the NMe-Lys side-chain ε-amine (Lu-177 therapeutic endpoint). Ga-68/
NODAGA imaging companion and radiolabeling deferred to the radiochemistry step. Scale 5 mg net peptide,
≥95% HPLC, ESI-MS confirmation, acetate salt (TFA removed), lyophilized.

## What this order explicitly does NOT claim / does NOT authorize
- **Not a novel/differentiated monomer.** AVB6-R4-09 is in the genus; R4-01 is a mined-space ncAA probe.
- **Not synthesis-authorized for development.** H6/H7 (docking affinity + αvβ8/αvβ3/αvβ5/α5β1 selectivity,
  with controls in-batch and the A2 validation gate) and the FTO counsel read are **still pending**.
- **FTO posture:** research-use synthesis of a published genus for assay validation is standard and does not
  require FTO clearance. FTO counsel gates **commercial/clinical** development of any monomer taken forward —
  it is not a blocker to sending this research-use synthesis order today. Flag to counsel regardless (H8/P5).

## What this order DOES buy
1. A **validated binding/selectivity assay** (controls recover the known order, or the assay is not trusted).
2. The **targeting warhead** (whichever of the controls/R4-09 binds cleanest) to carry into the construct.
3. One honest SAR data point on flank bulk vs αvβ6/αvβ8 (R4-01).

## Next deliverable (where novelty actually goes)
Construct design — structure-motivated, not ad hoc: multivalent geometry (the real Trivehexin mechanism),
chelator/radionuclide pairing, and the αvβ6×PD-L1 bispecific thesis. That is the order worth differentiating.
