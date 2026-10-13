# v2 CRO order — selection rationale (internal; the shipped CSV is score-free)

**Date:** 2026-10-13 · Ship-ready order: `docs/20261013_CRO_SEND_v2.csv` (= `results/CRO_SEND_v2.csv`),
GenScript CRO_SEND schema, **score-free** (no ΔG/iptm/tier/FTO columns — internal evidence stays here).
Selection rule: **multi-objective Pareto front ∩ (NOT committee NO-GO) ∩ liability-acceptable**, on the
candidates that cleared pharmacophore + liability + FTO + MM-GBSA. 6 candidates (4 αvβ6 + 2 PD-L1).

## What ships (production HELM, with the real ncAA)
| Item | id | HELM (N→C, cyclic) | internal evidence |
|---|---|---|---|
| AVB6-V2-01 | AVB6-K-02 | cyclo(W-R-G-D-L-T-F-[dP]-[NMeV]) | MM-GBSA **−26.5** (lead), Pareto, FTO-clean, RGDL+lock |
| AVB6-V2-02 | AVB6-K-06 | cyclo(R-G-D-L-Q-F-[dP]-[NMeS]-G) | MM-GBSA −22.8, Pareto, PASS tier, committee top pick |
| AVB6-V2-03 | AVB6-K-03 | cyclo(Y-R-G-D-L-G-H-[dP]-[NMeL]) | MM-GBSA −18.0, Pareto, PASS, committee top pick |
| AVB6-V2-04 | AVB6-K-01 | cyclo(F-R-G-D-L-S-W-[dP]-[NMeA]) | MM-GBSA −16.6, Pareto, FTO-clean |
| PDL1-V2-01 | PDL1-K-05 | cyclo(W-Y-F-[dP]-L-[NMeI]-T-E-N-K-S-G) | MM-GBSA **−29.0** (PD-L1 best), Pareto, committee top pick |
| PDL1-V2-02 | PDL1-K-02 | cyclo(W-[Nle]-F-[dP]-I-[NMeL]-S-E-K-G) | MM-GBSA −22.9, Pareto, Met→**Nle** (oxidation fix, production form) |

## Why these and not others
- **αvβ6:** the scored Pareto front is {K-02, K-06, K-03, K-01} (K-04 dominated); none committee-NO-GO → all 4 ship.
  K-05/07/08/09/10 have no MM-GBSA ΔG (the 5/10 psfgen build bug, stopped after 3 fixes) so they are not in
  the physics-selected set this round.
- **PD-L1:** Pareto front {K-05, K-03, K-04, K-02}, but the committee **NO-GO'd K-03 and K-04** (their liability-fix
  edits — Asp-Ser→Ser-Asp, K-D-G→K-G-D tail reorder — risk breaking the structure-gated binding, an activity
  cliff). Respecting that, PD-L1 ships only **K-05 and K-02**. K-03/K-04 are dock-validate/redesign-first.

## Honest caveats (carry into the assay plan, not the CRO CSV)
- **Binding-only physics.** MM-GBSA/cofold rank *binding*; the CRO order must be paired with **functional +
  selectivity assays** — αvβ6 vs αvβ3/αvβ5/αvβ8 counterscreen; PD-L1 PD-1/PD-L1 blockade reporter. Binding ≠ function.
- **Proxies, not trained models.** Permeability (RDKit TPSA) and safety (liability tier) in the Pareto step are
  transparent proxies — the trained EnsembleCycPerm / HistGBM-P[stable] models are a follow-up.
- **MM-GBSA is relative-within-set** (entropy omitted, rₚ≈0.75); it decides ranking, not absolute affinity.
  FEP on the αvβ6 leaders (K-02/K-06) is the accuracy upgrade (pending the OpenFE build).
- **PD-L1 physics is confounded-weak** vs round-1's generator set (pose-source + length confounds); K-05/K-02
  are the best *within v2*, not proven strong binders.
- **ncAA synthesis:** Nle (PDL1-V2-02) and D-Pro/N-methyl are in the HELM; confirm GenScript can source them.

## Pre-ship gate (the lesson, applied)
This set cleared, in order: **pharmacophore (mechanism) → liability/SAR → FTO → MM-GBSA (binding) →
multi-objective Pareto → cross-model committee**. That is the gate round-1 lacked when its 0/12-RGD panel
reached the order stage. Nothing here is a validated drug — it is the best-evidenced *hypothesis set* to test.
