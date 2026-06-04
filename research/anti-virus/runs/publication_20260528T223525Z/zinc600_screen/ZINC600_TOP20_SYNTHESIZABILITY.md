# ZINC600 — top 20 Vina hits synthesizability triage

_Screen size: **600** compounds docked (9P3I top pocket)._

**Method:** RDKit **SA Score** (Ertl & Schuffenhauer, *J. Cheminform.* 2009) via `rdkit.Contrib.SA_Score.sascorer`. Lower = easier to synthesize.

| Tier | SA range | Interpretation |
|------|----------|----------------|
| EASY | ≤ 3 | Straightforward synthesis |
| MODERATE | 3–5 | Typical medicinal chemistry |
| HARD | 5–7 | Challenging |
| VERY_HARD | > 7 | Likely difficult / specialist |

**Not run:** SynCraft retrosynthesis (BioMate workflow exists but is stub/external API per capability gap doc). SA score is a **proxy only** — not a route feasibility proof.

| Rank | Vina (kcal/mol) | SA | Tier | QED | MW | SMILES |
|------|-----------------|----|------|-----|-----|--------|
| 1 | -6.527 | 3.42 | MODERATE | 0.168 | 187.2 | `N=C(N)NC(=O)NC(=O)NC(=N)N` |
| 2 | -6.275 | 4.18 | MODERATE | 0.401 | 181.2 | `Nc1nc(=O)c2c([nH]1)N[C@H](O)C=N2` |
| 3 | -6.267 | **2.80** | **EASY** | 0.314 | 180.2 | `N=C(N)NC(=O)c1nccnc1N` (INH-01) |
| 4 | -6.099 | 4.93 | MODERATE | 0.339 | 183.2 | `C[C@@H]1CN[C@H]2NC(N)=NC(=O)[C@@H]2N1` |
| 5 | -6.065 | 3.51 | MODERATE | 0.174 | 144.1 | `N=C(N)NC(=O)NC(=N)N` |
| 6 | -6.014 | 4.30 | MODERATE | 0.388 | 182.1 | `O=C1Nc2c[nH]c(=O)nc2N[C@H]1O` |
| 7 | -5.933 | 3.30 | MODERATE | 0.559 | 198.2 | `C[C@@H](O)[C@@H]1NC(=O)[C@@H]2CCCN2C1=O` |
| 8 | -5.912 | 4.93 | MODERATE | 0.339 | 183.2 | `C[C@@H]1CN[C@@H]2NC(N)=NC(=O)[C@@H]2N1` |
| 9 | -5.902 | 3.32 | MODERATE | 0.367 | 187.2 | `CC(=O)NC1=NN(C)C(=O)C1(O)O` |
| 10 | -5.881 | 3.98 | MODERATE | 0.358 | 180.2 | `CNC1=NC(N)=C2NCCN=C2N1` |
| 11 | -5.831 | 4.53 | MODERATE | 0.386 | 181.2 | `NC1=NC(=O)C2=N[C@H](O)CNC2=N1` |
| 12 | -5.825 | 4.30 | MODERATE | 0.388 | 182.1 | `O=C1Nc2c[nH]c(=O)nc2N[C@@H]1O` |
| 13 | -5.759 | 3.26 | MODERATE | 0.459 | 179.1 | `Nc1nc(=O)[nH]c2[nH]c(=O)cnc12` |
| 14 | -5.731 | 4.93 | MODERATE | 0.339 | 183.2 | `C[C@@H]1CN[C@H]2NC(N)=NC(=O)[C@H]2N1` |
| 15 | -5.697 | **2.63** | **EASY** | 0.298 | 174.1 | `NC(=O)NC(=O)NC(=O)C(N)=O` |
| 16 | -5.678 | 4.26 | MODERATE | 0.236 | 186.1 | `Nc1oc2c(N)[n+]([O-])n(O)c2c1O` |
| 17 | -5.603 | 3.70 | MODERATE | 0.298 | 194.1 | `O=C(O)[C@@H]1O[C@H](O)[C@@H](O)[C@H](O)[C@H]1O` |
| 18 | -5.599 | 3.72 | MODERATE | 0.495 | 182.3 | `C[C@]12NCCN3CCN(CCN1)[C@@H]32` |
| 19 | -5.567 | 4.16 | MODERATE | 0.343 | 154.1 | `NN1NC(=O)c2[nH]cnc2N1` |
| 20 | -5.560 | 4.31 | MODERATE | 0.251 | 188.2 | `N=C(N)C1=C[C@@H](O)[C@@H](O)[C@@H](CO)O1` |

## Summary

| Metric | Value |
|--------|-------|
| Top 20 with SA ≤ 5 (moderate or easier) | **20/20** |
| EASY (SA ≤ 3) | 2 (ranks 3, 15) |
| MODERATE (3 < SA ≤ 5) | 18 |
| HARD / VERY_HARD | 0 |

**Lead comparison:** INH-01 (rank 3) SA **2.80** (EASY). Current rank-1 Z600-R1 SA **3.42** (MODERATE) — synthesizability is not a differentiator vs INH-01 on this proxy.

**Caveats:** Many hits are guanidine / heterocycle-rich (polar, low QED). SA score does not penalize stability, purification, or commercial building-block availability. For procurement claims, cross-check ZINC purchasability IDs separately.
