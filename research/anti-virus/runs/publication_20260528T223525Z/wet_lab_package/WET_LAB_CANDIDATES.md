# ANDV Wet-Lab Candidate Package

Generated: 2026-06-07 (aligned with `compute_package/COMPUTE_CANDIDATES.md`)

> **Note:** Track A now uses **HC-** IDs from science tiers (tier C cytoplasmic excluded). Legacy **MB-** list (rank-sorted binders incl. cytoplasmic MB-01) is **retired**.

## Summary
- Cross-species conserved 9-mers (full GP): **54**
- MHC consensus binders: **47** pairs
- Science tiers: **4 A + 24 B** surface epitopes
- Chile tier A+B population coverage: **48.81%**
- Publication ZINC docked: **5,006**
- Inhibitor compute lead: **INH-01** (MD-validated; pub deck rank #79)

## Track A — Tier-ranked epitope candidates (synthesize first)

_Ranked by dual MHCnuggets+MHCflurry consensus + GPC surface. Tier C excluded._

| ID | Peptide | Tier | GP pos | Region | Conserved | Priority |
|----|---------|------|--------|--------|-----------|----------|
| HC-01 | VPGLHGWATVM | A | 479 | gc_ectodomain_stem | yes | HIGH |
| HC-02 | MPDVAHSLAV | A | 466 | gc_ectodomain_stem | yes | HIGH |
| HC-03 | VPGLHGWATV | A | 479 | gc_ectodomain_stem | yes | HIGH |
| HC-04 | MPDVAHSL | A | 466 | gc_ectodomain_stem | yes | HIGH |
| HC-05 | KTFEGILTK | B | 228 | gn_ectodomain | no | MEDIUM |
| HC-06 | MPKTIYEL | B | 19 | gn_ectodomain | no | MEDIUM |
| HC-07 | QRFRGSEQK | B | 414 | gn_ectodomain | no | MEDIUM |
| HC-08 | VIYEKTHCV | B | 172 | gn_ectodomain | no | MEDIUM |
| HC-09 | NPAHTLTL | B | 191 | gn_ectodomain | no | MEDIUM |
| HC-10 | VPITWTGYL | B | 359 | gn_ectodomain | no | MEDIUM |
| HC-11 | SRMLVHPR | B | 274 | gn_ectodomain | no | MEDIUM |
| HC-12 | SRIQVIYEK | B | 168 | gn_ectodomain | no | MEDIUM |
| HC-13 | IRSCMASVF | B | 158 | gn_ectodomain | no | MEDIUM |
| HC-14 | LRIVGPITAK | B | 295 | gn_ectodomain | no | MEDIUM |
| HC-15 | VPMYSSLSTL | B | 322 | gn_ectodomain | no | MEDIUM |

**Assay:** Peptide-MHC binding (DimerX/ELISA) + IFN-γ ELISpot

## Track B — Cross-species conserved 9-mers (breadth)

See `compute_package/COMPUTE_CANDIDATES.md` Track B (XSP-01…).

## Track C — Publication ZINC HTS hits (9P3I)

Primary HTS deck (`publication_zinc/vina/`). See **`INHIBITOR_COMPOUND_SHORTLIST.md`** for tiered validation order.

| ID | Vina (kcal/mol) | Notes |
|----|----------------:|-------|
| PUB-01 | −6.952 | Rigid #1 (ZINC239377869); ensemble worsened |
| PUB-02 | −6.878 | Ensemble −7.483 candidate |
| PUB-12 | −6.615 | Ensemble best **−7.562** (ZINC828873353) |
| INH-01 | −6.208 (#79) | **Primary compute lead** (MD RMSD 0.41 nm) |
| Z600-R1 | −6.527 (#15) | Blog-tier control; pose QC PASS |

Legacy ZINC150/MM-GBSA ranking superseded by publication tier.
