# Publication ZINC — Vina docking summary

_Generated: 2026-06-05T06:36:26.409730+00:00_
_Progress: **100/5006** docked — **IN PROGRESS**; 0 failed/empty in merged JSON._

## Library funnel (build)

| Stage | Count |
|-------|------:|
| Raw tranche union | 42128 |
| Drug-like | 28722 |
| Pharmacophore pass (≥3) | 12215 |
| Dock set | 5006 |

**Tranches:** https://files.docking.org/2D/AB/ABAA.smi, https://files.docking.org/2D/AB/ABAB.smi, https://files.docking.org/2D/AB/ABAC.smi, https://files.docking.org/2D/BB/BBAA.smi, https://files.docking.org/2D/BC/BCAC.smi

## Controls (injected)

| Label | Vina (kcal/mol) | Status |
|-------|-----------------|--------|
| INH-01 | -6.208 | docked |
| Z600-R1 | -6.527 | docked |
| umifenovir | -6.362 | docked |
| favipiravir | -4.384 | docked |
| ribavirin | -5.569 | docked |
| oseltamivir | — | pending |

## Top 20 hits (publication deck)

| Rank | Vina | ZINC ID | Tranche | MW | QED | SMILES |
|------|------|---------|---------|----|-----|--------|
| 1 | -6.527 | CONTROL_Z600-R1 | control | 187.2 | 0.168 | `N=C(N)NC(=O)NC(=O)NC(=N)N` **Z600-R1** |
| 2 | -6.362 | CONTROL_umifenovir | control | 274.8 | 0.840 | `CC(C)(C)c1ccc(C(O)c2ccc(Cl)cc2)cc1` **umifenovir** |
| 3 | -6.288 | 13571425 | BBAA | 216.2 | 0.457 | `Nn1c(=O)[nH]c2c([nH]c3ccccc32)c1=O` |
| 4 | -6.208 | CONTROL_INH-01 | control | 180.2 | 0.314 | `N=C(N)NC(=O)c1nccnc1N` **INH-01** |
| 5 | -6.102 | 58037673 | BBAA | 209.2 | 0.574 | `Cn1[nH]c(=O)c2c(=O)c(C(=O)O)c[nH]c21` |
| 6 | -5.985 | 33369574 | BCAC | 220.3 | 0.735 | `Nc1nccc(C(=O)N2CCCCC2)c1N` |
| 7 | -5.956 | 211588802 | BBAA | 239.3 | 0.682 | `N[C@H]1CC[C@H](NC(=O)CCc2cc(=O)[nH]o2)C1` |
| 8 | -5.952 | 159603862 | ABAB | 194.2 | 0.636 | `C[C@H]1CN(c2cc(=O)[nH]cn2)CCN1` |
| 9 | -5.852 | 71773004 | BBAA | 208.2 | 0.647 | `O=c1[nH]c2ccccc2n1C[C@H](O)CO` |
| 10 | -5.848 | 2265279225 | BCAC | 232.2 | 0.720 | `COc1ccc(C=C2NC(=O)CNC2=O)cc1` |
| 11 | -5.832 | 34082246 | BCAC | 245.2 | 0.817 | `Cn1cc(O)c(=O)cc1C(=O)Nc1cccnc1` |
| 12 | -5.823 | 210392191 | BBAA | 234.3 | 0.741 | `O=C1CN(Cc2ccccc2)C(=O)[C@H](CO)N1` |
| 13 | -5.818 | 6925573 | ABAB | 194.1 | 0.399 | `N=C(N)n1[nH]c(C(F)(F)F)cc1=O` |
| 14 | -5.809 | 2512239 | BBAA | 213.2 | 0.513 | `Nn1c(S(=O)(=O)O)nc2ccccc21` |
| 15 | -5.656 | 4769777 | BBAA | 234.2 | 0.779 | `Cn1c(=O)c2ccccc2n(CC(=O)O)c1=O` |
| 16 | -5.643 | 70713912 | BBAA | 211.2 | 0.737 | `Cc1ccn(C[C@](C)(O)C(=O)O)c(=O)c1` |
| 17 | -5.621 | 102669645 | BBAA | 205.2 | 0.658 | `O=C1C[C@H](NCc2ccncc2)C(=O)N1` |
| 18 | -5.593 | 1701698 | BBAA | 213.2 | 0.700 | `O=C1c2ccccc2S(=O)(=O)N1CO` |
| 19 | -5.569 | CONTROL_ribavirin | control | 209.2 | 0.592 | `NC(=O)c1nc(C=C(C)CO)c(C=O)[nH]1` **ribavirin** |
| 20 | -5.545 | 104395563 | ABAC | 163.2 | 0.551 | `NCc1cnc2c(N)n[nH]c2c1` |

## Headline comparison

- **Publication deck best (so far):** -6.527 kcal/mol
- **Blog-tier ZINC600 best:** -6.527 kcal/mol (`N=C(N)NC(=O)NC(=O)NC(=N)N…`)
- **INH-01 rank:** #4 of 100 docked (-6.208 kcal/mol)

## Interpretation (do not overclaim)

- Publication deck is **target-informed** (pharmacophore + multi-tranche); blog 600 AAAC is **not**.
- Vina scores remain **weak in silico hits**; no antiviral potency claim.
- After full dock: run ensemble + pose QC on top-20; compare purchasability via `lookup_zinc_purchasability.py`.

**Artifacts:** `research/anti-virus/runs/publication_20260528T223525Z/publication_zinc/vina/docking_autodock_vina_results.json`, `research/anti-virus/runs/publication_20260528T223525Z/publication_zinc/vina/dock_progress.json`
