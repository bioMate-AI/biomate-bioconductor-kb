# ANDV Compute Output Package (BioMate in silico)

Generated: 2026-06-03T19:37:06.392614+00:00

_No wet-lab work — ranked compute artifacts for manuscript / workflow demo._

## Summary
- Cross-species conserved 9-mers (full GP): **54**
- MHC binders (epitope run): **47** (20 unique peptides)
- Conserved ∩ binder overlap: **0**
- Docking hits (top ranked): **20**
- ZINC screen docked: **150**
- Chile tier A+B population coverage (17-allele strict dual): **48.81%**

## Track A — Tier-ranked epitope candidates (MHCnuggets + MHCflurry consensus)

_Ranked by dual MHCnuggets+MHCflurry consensus + GPC surface exposure. Tier C (cytoplasmic) excluded._

| ID | Peptide | Tier | GP pos | Region | Conserved | Processing proxy | Priority |
|----|---------|------|--------|--------|-----------|------------------|----------|
| HC-01 | VPGLHGWATVM | A | 479 | gc_ectodomain_stem | yes | no | HIGH |
| HC-02 | MPDVAHSLAV | A | 466 | gc_ectodomain_stem | yes | no | HIGH |
| HC-03 | VPGLHGWATV | A | 479 | gc_ectodomain_stem | yes | no | HIGH |
| HC-04 | MPDVAHSL | A | 466 | gc_ectodomain_stem | yes | yes | HIGH |
| HC-05 | KTFEGILTK | B | 228 | gn_ectodomain | no | no | MEDIUM |
| HC-06 | MPKTIYEL | B | 19 | gn_ectodomain | no | yes | MEDIUM |
| HC-07 | QRFRGSEQK | B | 414 | gn_ectodomain | no | yes | MEDIUM |
| HC-08 | VIYEKTHCV | B | 172 | gn_ectodomain | no | no | MEDIUM |
| HC-09 | NPAHTLTL | B | 191 | gn_ectodomain | no | no | MEDIUM |
| HC-10 | VPITWTGYL | B | 359 | gn_ectodomain | no | no | MEDIUM |
| HC-11 | SRMLVHPR | B | 274 | gn_ectodomain | no | no | MEDIUM |
| HC-12 | SRIQVIYEK | B | 168 | gn_ectodomain | no | no | MEDIUM |
| HC-13 | IRSCMASVF | B | 158 | gn_ectodomain | no | no | MEDIUM |
| HC-14 | LRIVGPITAK | B | 295 | gn_ectodomain | no | no | MEDIUM |
| HC-15 | VPMYSSLSTL | B | 322 | gn_ectodomain | no | no | MEDIUM |

## Track B — Cross-species conserved 9-mers (breadth)

| ID | Peptide | GP pos | MHC binder | Priority |
|----|---------|--------|------------|----------|
| XSP-01 | ESSCNFDLH | 61 | pending | MEDIUM |
| XSP-02 | CTVFCTLAG | 379 | pending | MEDIUM |
| XSP-03 | TVFCTLAGP | 380 | pending | MEDIUM |
| XSP-04 | VFCTLAGPG | 381 | pending | MEDIUM |
| XSP-05 | FCTLAGPGA | 382 | pending | MEDIUM |
| XSP-06 | GIFNISSPT | 399 | pending | MEDIUM |
| XSP-07 | IFNISSPTC | 400 | pending | MEDIUM |
| XSP-08 | FNISSPTCL | 401 | pending | MEDIUM |
| XSP-09 | KKVILTKTL | 442 | pending | MEDIUM |
| XSP-10 | KVILTKTLV | 443 | pending | MEDIUM |
| XSP-11 | VILTKTLVI | 444 | pending | MEDIUM |
| XSP-12 | ILTKTLVIG | 445 | pending | MEDIUM |
| XSP-13 | LTKTLVIGQ | 446 | pending | MEDIUM |
| XSP-14 | TKTLVIGQC | 447 | pending | MEDIUM |
| XSP-15 | KTLVIGQCI | 448 | pending | MEDIUM |

## Track C — ZINC library docking hits (9P3I top pocket)

| ID | SMILES (truncated) | Vina (kcal/mol) | Receptor | Priority |
|----|-------------------|-----------------|----------|----------|
| INH-01 | `N=C(N)NC(=O)c1nccnc1N` | **-6.267** | 9P3I | HIGH |
| INH-02 | `CNC1=NC(N)=C2NCCN=C2N1` | **-5.881** | 9P3I | HIGH |
| INH-03 | `Nc1oc2c(N)[n+]([O-])n(O)c2c1O` | **-5.678** | 9P3I | HIGH |
| INH-04 | `O=C(O)[C@@H]1O[C@H](O)[C@@H](O)[C@H](O)[C@@H]1O` | **-5.603** | 9P3I | HIGH |
| INH-05 | `C[C@]12NCCN3CCN(CCN1)[C@@H]32` | **-5.599** | 9P3I | HIGH |
| INH-06 | `N=C(N)C1=C[C@@H](O)[C@@H](O)[C@@H](CO)O1` | **-5.56** | 9P3I | MEDIUM |
| INH-07 | `NC[C@H]1O[C@@H](O)[C@@H](O)[C@@H](O)[C@@H]1O` | **-5.554** | 9P3I | MEDIUM |
| INH-08 | `CO[C@@]12C[C@H](CN)O[C@H]1NC(=O)N2` | **-5.531** | 9P3I | MEDIUM |
| INH-09 | `NC(=O)CC(O)(CC(N)=O)C(N)=O` | **-5.489** | 9P3I | MEDIUM |
| INH-10 | `O=C1NC(=O)c2[nH]c(=O)c(O)nc21` | **-5.425** | 9P3I | MEDIUM |
| INH-11 | `C[C@]12NCCN[C@@]1(C)NCCN2` | **-5.422** | 9P3I | MEDIUM |
| INH-12 | `O=C1CN2C(=O)CCN[C@H]2CN1` | **-5.4** | 9P3I | MEDIUM |
| INH-13 | `O=C(O)[C@@H](O)[C@H]1O[C@H](O)[C@H](O)[C@H]1O` | **-5.389** | 9P3I | MEDIUM |
| INH-14 | `O=C(O)[C@H](O)C[C@H](O)[C@H](O)CO` | **-5.297** | 9P3I | MEDIUM |
| INH-15 | `OC[C@@H]1O[C@H](O)[C@@H](F)[C@@H](O)[C@@H]1O` | **-5.273** | 9P3I | MEDIUM |
