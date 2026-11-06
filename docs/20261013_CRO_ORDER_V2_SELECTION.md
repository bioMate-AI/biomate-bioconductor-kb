# v2 CRO order — selection rationale (internal; the shipped CSV is score-free)

**Date:** 2026-10-13 · Ship-ready: `docs/20261013_CRO_SEND_v2.csv` (= `results/CRO_SEND_v2.csv`), GenScript
CRO_SEND schema, **score-free**. **12 candidates (8 αvβ6 + 4 PD-L1)** — round-1-comparable scale.

## Correction (why this is 12, not 6)
A first pass produced only 6 because it required an MM-GBSA ΔG to enter the Pareto selection — but the
psfgen build bug left **5/10 αvβ6 unscored**, so good candidates were dropped for a **tooling reason, not
merit** (including the original lead **K-08** and committee top-picks **K-05/K-07**). Corrected: select on
**ALL evidence** — MM-GBSA ΔG where available, else the cofold peptide↔receptor interface confidence + the
cheap gates (pharmacophore, liability, FTO) + the committee. A missing ΔG (tooling gap) is not a demerit.

## What ships
**αvβ6 (8)** — all carry RGD·L + D-Pro/N-methyl lock, liability- and FTO-screened:
| Item | id | HELM | evidence |
|---|---|---|---|
| AVB6-V2-01 | K-02 | cyclo(W-R-G-D-L-T-F-[dP]-[NMeV]) | MM-GBSA **−26.5** (lead) |
| AVB6-V2-02 | K-06 | cyclo(R-G-D-L-Q-F-[dP]-[NMeS]-G) | MM-GBSA −22.8; committee pick; PASS |
| AVB6-V2-03 | K-03 | cyclo(Y-R-G-D-L-G-H-[dP]-[NMeL]) | MM-GBSA −18.0; committee pick; PASS |
| AVB6-V2-04 | K-01 | cyclo(F-R-G-D-L-S-W-[dP]-[NMeA]) | MM-GBSA −16.6; FTO-clean |
| AVB6-V2-05 | K-04 | cyclo(H-R-G-D-L-A-W-[dP]-[NMeE]) | MM-GBSA −16.5; renal-fixed (net −1) |
| AVB6-V2-06 | K-05 | cyclo(F-R-G-D-L-I-F-[dP]-[NMeA]) | cofold iptm 0.91; **extended-affinity RGDL-I**; committee pick (ΔG pending) |
| AVB6-V2-07 | K-07 | cyclo([dL]-R-G-D-L-S-F-[dP]-[NMeT]) | cofold iptm 0.89; committee pick (ΔG pending) |
| AVB6-V2-08 | K-08 | cyclo(Y-R-G-D-L-I-W-[dP]-[NMeA]) | **original lead**: PASS + extended-affinity + FTO-clean; cofold iptm 0.91 (ΔG pending) |

**PD-L1 (4)** — committee-clean, best-within-v2 (PD-L1 physics is confounded-weak overall):
| Item | id | HELM | evidence |
|---|---|---|---|
| PDL1-V2-01 | K-05 | cyclo(W-Y-F-[dP]-L-[NMeI]-T-E-N-K-S-G) | MM-GBSA **−29.0** (best); committee pick |
| PDL1-V2-02 | K-02 | cyclo(W-[Nle]-F-[dP]-I-[NMeL]-S-E-K-G) | MM-GBSA −22.9; Met→**Nle** (oxidation fix) |
| PDL1-V2-03 | K-01 | cyclo(F-W-L-[dP]-Y-S-[NMeF]-D-T-K) | MM-GBSA −23.4; unedited |
| PDL1-V2-04 | K-07 | cyclo(F-W-[dP]-Y-I-L-[NMeF]-E-R-S) | MM-GBSA −23.2; unedited |

## Excluded on merit (not tooling)
- **αvβ6 K-09** — committee NO-GO (4-mutation FTO-dodge, cliff risk; lowest-with-K-10 cofold iptm 0.78).
- **αvβ6 K-10** — weakest cofold pose (0.73) + residual renal; heavy edit.
- **PD-L1 K-03, K-04** — committee NO-GO (liability-fix edits risk breaking the structure-gated binding).
- **PD-L1 K-08** — committee aggregation flag + weakest ΔG (−21.8); disulfide scaffold.

## Honest caveats (into the assay plan, not the CRO CSV)
- **Binding-only.** Pair with functional + selectivity assays: αvβ6 vs αvβ3/αvβ5/αvβ8 counterscreen; PD-L1
  PD-1/PD-L1 blockade. Binding ≠ function.
- **3 αvβ6 (K-05/07/08) have no MM-GBSA ΔG yet** (psfgen bug) — included on cofold-confidence + gates +
  committee; their ΔG completes once the full-10 build is fixed (deferred sub-task).
- Permeability/safety in the Pareto step were RDKit/liability **proxies** (trained models = follow-up);
  MM-GBSA is relative-within-set; PD-L1 physics confounded vs round-1; FEP (OpenFE) on finalists pending.
- ncAA (Nle, D-Pro, N-methyl) in HELM — confirm the CRO can source them.

## Gate applied (the round-1 lesson)
pharmacophore → liability/SAR → FTO → MM-GBSA → multi-objective Pareto → cross-model committee. Best-
evidenced hypothesis set to test — not validated drugs.
