# ANDV Compute Output Package (BioMate in silico)

Generated: 2026-06-07T01:01:22.964735+00:00

_No wet-lab work — ranked compute artifacts for manuscript / workflow demo._

## Summary
- Cross-species conserved 9-mers (full GP): **54**
- MHC binders (epitope run): **47** (20 unique peptides)
- Conserved ∩ binder overlap: **0**
- Docking hits (top ranked): **20**
- ZINC screen docked: **5006**
- Inhibitor compute lead: **INH-01** (Vina + pose QC; Z600-R1 backup)
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
| INH-01 | `CN1N[C@H](c2ccc(O)cc2)[C@@H]2C(=O)NC(=O)[C@H]21` | **-6.952** | 9P3I | HIGH |
| INH-02 | `NC(=O)NC(=O)c1nc2ccccc2[nH]c1=O` | **-6.878** | 9P3I | HIGH |
| INH-03 | `O=C1N[C@@]2(O)C(=O)c3ccccc3[C@]2(O)N1` | **-6.855** | 9P3I | HIGH |
| INH-04 | `C[C@@H]1CN(C)c2nc3c(c(=O)[nH]c(=O)n3C)n2C1` | **-6.762** | 9P3I | HIGH |
| INH-05 | `Cc1cc2c(cn1)CN(C(=O)[C@@H]1CNC(=O)N1)C2` | **-6.754** | 9P3I | HIGH |
| INH-06 | `O=C(NCCO)c1c(O)[nH]c2ccccc2c1=O` | **-6.735** | 9P3I | MEDIUM |
| INH-07 | `Cc1cc(N2CC3(CNC(=O)N3C)C2)nc(=N)[nH]1` | **-6.72** | 9P3I | MEDIUM |
| INH-08 | `O=C1c2ccccc2C[C@H]1n1ccc(O)nc1=O` | **-6.691** | 9P3I | MEDIUM |
| INH-09 | `Nc1nc(=O)c2c([nH]1)CN(Cc1ccccc1)C2` | **-6.675** | 9P3I | MEDIUM |
| INH-10 | `CC1=NNc2nc3c(c(=O)[nH]c(=O)n3C)n2[C@@H]1C` | **-6.642** | 9P3I | MEDIUM |
| INH-11 | `N=c1ccc(C(=O)N2C[C@H](O)[C@@H](F)C2)c[nH]1` | **-6.636** | 9P3I | MEDIUM |
| INH-12 | `O=C1N[C@@H](c2ccccc2)C(=O)N2C[C@H](O)C[C@@H]12` | **-6.615** | 9P3I | MEDIUM |
| INH-13 | `O[C@H]1C=CC2=C([C@H](O)c3ccccc32)[C@H]1O` | **-6.6** | 9P3I | MEDIUM |
| INH-14 | `CN1C(=O)N(C)[C@@]2(O)c3ccccc3C(=O)[C@@]12O` | **-6.548** | 9P3I | MEDIUM |
| INH-15 | `N=C(N)NC(=O)NC(=O)NC(=N)N` | **-6.527** | 9P3I | MEDIUM |
