# Inhibitor track — science QC gates

Generated: 2026-06-04T18:12:02.920321+00:00

## Protocol gates

| Gate | Status | Pass | Notes |
| --- | --- | --- | --- |
| MM-GBSA protocol | FAIL | **no** | Aspirin ΔG_bind ≤ −12 kcal/mol — MM-GBSA not calibrated for relative ranking |
| Ensemble docking | COMPLETE | yes | Ensemble scores recovered on deposit conformers; 4/15 improved vs rigid baseline (may be zero — honest negative). |

## Z600-R1 rank-1 pose QC

| Vina (kcal/mol) | Ligand RMSD (nm) | Verdict |
| ---: | ---: | --- |
| — | 0.2604 | **PASS** (INH-01 baseline ~0.20 nm) |

## Per-compound QC

| Compound | Vina | MM-GBSA ΔG | Protein RMSD (nm) | Ligand RMSD (nm) | Verdict | MM-GBSA rank? |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| INH-01 | -6.267 | -10.49 | 0.4068 | 0.204 | **VINA_ONLY** | no |
| INH-02 | -5.881 | -12.29 | 0.5265 | 0.3257 | **VINA_ONLY** | no |
| INH-03 | -5.678 | -27.09 | 0.6607 | 0.3764 | **FAIL** | no |
| INH-04 | -5.603 | -6.83 | 0.5109 | 0.2944 | **VINA_ONLY** | no |
| INH-05 | -5.599 | -12.03 | 0.4753 | 0.2519 | **VINA_ONLY** | no |
| Aspirin | — | -13.05 | 0.6647 | — | **CONTROL_FAIL** | no |

## Science verdict

- **Compute lead:** INH-01 (Vina + pose QC) — Best rigid Vina among pose-QC-validated hits (−6.27 kcal/mol); ligand RMSD ~0.20 nm; MM-GBSA not used for ranking (aspirin control failure)
- **MM-GBSA usable for ranking:** **no** (control failure)
- **Remaining blockers:**
  - MM-GBSA aspirin control failure
