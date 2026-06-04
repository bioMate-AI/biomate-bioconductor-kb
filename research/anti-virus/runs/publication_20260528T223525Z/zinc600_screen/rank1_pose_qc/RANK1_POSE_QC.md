# ZINC600 rank-1 pose QC (GROMACS MD)

Updated: 2026-06-04T16:16:35+00:00 (S3 artifact pull + local RMSD)

| Field | Value |
| --- | --- |
| Compound | **Z600-R1** |
| SMILES | `N=C(N)NC(=O)NC(=O)NC(=N)N` |
| Vina (kcal/mol) | **−6.527** |
| Galaxy run_id | `b89f1662-cd13-494e-877e-fab88643404b` |
| Pose QC | **complete** |
| Ligand RMSD mean (nm) | **0.260** |
| Ligand RMSD max (nm) | 0.466 |

**Verdict vs INH-01 baseline (~0.20 nm):** PASS (≤0.35 nm)

**Compute lead recommendation:** Z600-R1 passes pose QC but has **higher** ligand RMSD than INH-01 (0.26 vs 0.20 nm) and similar guanidine chemotype. Keep **INH-01** as primary compute lead until ADMET/medchem review of rank-1; Z600-R1 is a **backup** with better rigid Vina only.
