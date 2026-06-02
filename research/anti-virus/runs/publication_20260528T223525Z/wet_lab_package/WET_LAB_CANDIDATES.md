# ANDV Wet-Lab Candidate Package

Generated: 2026-06-02T01:44:02.946029+00:00

## Summary
- Cross-species conserved 9-mers (full GP): **54**
- MHC binders (epitope run): **922** (20 unique peptides)
- Conserved ∩ binder overlap: **10**
- Docking hits: **20**

## Track A — MHC-validated binders (synthesize first)

| ID | Peptide | Allele | Rank | BA | Conserved |
|----|---------|--------|------|-----|-----------|
| MB-01 | ATESALQAHY | HLA-A*01:01 | 0.0002 | 0.451 | no |
| MB-02 | MPKTIYEL | HLA-B*08:01 | 0.0007 | 0.727 | no |
| MB-03 | KTFEGILTK | HLA-A*03:01 | 0.0008423913043174 | 0.721 | no |
| MB-04 | YRTLGVFRY | HLA-B*27:05 | 0.0011 | 0.660 | no |
| MB-05 | IRSCMASVFTSR | HLA-B*27:05 | 0.0012 | 0.655 | no |
| MB-06 | YRTLGVFRYK | HLA-B*27:05 | 0.0013 | 0.651 | no |
| MB-07 | IPMKTDLEL | HLA-B*07:02 | 0.0017 | 0.631 | no |
| MB-08 | QRFRGSEQK | HLA-B*27:05 | 0.0021 | 0.614 | no |
| MB-09 | KRMMATKDSF | HLA-B*27:05 | 0.0022 | 0.613 | no |
| MB-10 | VIYEKTHCV | HLA-A*02:01 | 0.0024999999999977 | 0.735 | no |
| MB-11 | NPANKEESI | HLA-B*07:02 | 0.0026 | 0.599 | no |
| MB-12 | APHLERVTGF | HLA-B*07:02 | 0.0027 | 0.597 | no |
| MB-13 | FRKICGFATTPV | HLA-B*27:05 | 0.0027 | 0.594 | no |
| MB-14 | SLKYTRKVCI | HLA-B*08:01 | 0.0029 | 0.612 | no |
| MB-15 | VPITWTGYL | HLA-B*07:02 | 0.0029 | 0.592 | no |

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
| XSP-09 | KKVILTKTL | 442 | yes | HIGH |
| XSP-10 | KVILTKTLV | 443 | yes | HIGH |
| XSP-11 | VILTKTLVI | 444 | yes | HIGH |
| XSP-12 | ILTKTLVIG | 445 | pending | MEDIUM |
| XSP-13 | LTKTLVIGQ | 446 | pending | MEDIUM |
| XSP-14 | TKTLVIGQC | 447 | pending | MEDIUM |
| XSP-15 | KTLVIGQCI | 448 | yes | HIGH |

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
