# Inhibitor Track C — Computational Shortlist (ZINC150)

**Generated:** 2026-06-03  
**Source:** `zinc150_screen/vina/docking_autodock_vina_results.json` (145 ligands, PDB 9P3I top pocket)

> **Wet-lab:** INH-01 MM-GBSA **ΔG_bind = −10.49 ± 0.46 kcal/mol** (strong binder). Proceed to medchem ADMET review before synthesis order.

## Top 5 by rigid Vina score

| ID | SMILES | Vina (kcal/mol) | Notes |
|----|--------|-----------------|-------|
| INH-01 | `N=C(N)NC(=O)c1nccnc1N` | **−6.267** | MD + MM-GBSA **−10.49 kcal/mol** (Ki ≈ 20 nM) |
| INH-02 | `CNC1=NC(N)=C2NCCN=C2N1` | −5.881 | hERG 0.357 — flag for medchem |
| INH-03 | `Nc1oc2c(N)[n+]([O-])n(O)c2c1O` | −5.678 | DILI 0.756, ClinTox 0.158 |
| INH-04 | `O=C(O)[C@@H]1O[C@H](O)[C@@H](O)[C@H](O)[C@@H]1O` | −5.603 | Sugar-like; poor BBB |
| INH-05 | `C[C@]12NCCN3CCN(CCN1)[C@@H]32` | −5.599 | hERG 0.162 |

## Recommended validation tier

1. **INH-01** — primary: best Vina + MD + MM-GBSA (−10.49 kcal/mol)  
2. **INH-02** — backup if SPR/pseudotype fails  
3. Aspirin — negative/control (ensemble −6.22 kcal/mol on 9P3Y in demo sprint)

## Assays (when cleared)

1. SPR or thermal shift on GP ectodomain (9P3I/9P3Y)  
2. Pseudotype entry inhibition (BSL-2)  
3. ADMET panel confirmation for top 1–2

Full table: `wet_lab_package/WET_LAB_CANDIDATES.md` Track C.
