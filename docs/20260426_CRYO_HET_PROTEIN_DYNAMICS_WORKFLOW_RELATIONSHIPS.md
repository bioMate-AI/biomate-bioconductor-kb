# Workflow Relationships: Cryo-EM Heterogeneity + Protein Dynamics

Date: 2026-04-26

## Context

Two new workflows were registered in the BioMate workflow DB (ids 12885 and 12886) as part of the protein dynamics + cryo-EM heterogeneity AWS Batch pass. This document maps how those workflows relate to the existing cryo-EM and drug discovery workflows already in the system.

---

## Workflow 12885 — Cryo-EM Conformational Heterogeneity (cryoDRGN)

### Role in the Pipeline Ecosystem

12885 is a **downstream post-SPA analysis** workflow. It does not replace the existing SPA workflows — it consumes their outputs.

```
CryoSPARC Standard SPA (12833)
  OR Saposin Nanodisc SPA  (12808)
  OR GPCR Complex SPA      (12809)
  OR Liposome Pore SPA     (12812)
         │
         │  outputs: poses.pkl + CTF.pkl
         │           (from homogeneous consensus reconstruction)
         ▼
  cryoDRGN Heterogeneity (12885)
         │
         │  outputs: latent space UMAP, kmeans volumes,
         │           ensemble_pockets.json, heterogeneity_report.json
         ▼
  Drug Discovery workflows (ADMET, docking, etc.)
```

### Relation to Other Heterogeneity Workflows

| Existing Workflow | Relationship | When to Choose |
|---|---|---|
| **3D Variability Pipeline (12836)** | Functional sibling — both model conformational heterogeneity | 3DVA: faster, linear PCA model, good for large datasets; cryoDRGN (12885): nonlinear VAE, better for complex/multi-modal motions, produces explicit 3D volumes |
| **RELION Multi-Body Refinement (12813)** | Complementary — models heterogeneity as rigid-body motions of known domains | RELION multi-body: when domain boundaries are known a priori; cryoDRGN: when conformational landscape is unknown or continuous |
| **CryoSPARC Standard SPA (12833)** | Primary upstream supplier | SPA produces the homogeneous reconstruction; 12885 then decomposes the residual heterogeneity hidden in that dataset |
| **Saposin/GPCR/Liposome SPA (12808/09/12)** | Same upstream role as 12833 | Any SPA workflow that outputs poses + CTF can feed into 12885 |

### Key Input/Output Contract

- **Inputs** (from SPA): `particles.mrcs`, `ctf.pkl`, `poses.pkl`
- **Outputs**: `analyze.<epoch>/kmeans<N>/vol_*.mrc` (density maps per conformational state), `umap.png`, `ensemble_pockets.json`, `heterogeneity_report.json`
- **Parameters**: `n_zdim` (latent dimensionality, default 8), `n_epochs` (default 20), `n_clusters` (conformational states, default 10)

---

## Workflow 12886 — Protein Dynamics Conformational Ensemble (BioEmu)

### Role in the Pipeline Ecosystem

12886 is **independent of the cryo-EM SPA stack** — it operates entirely from a PDB structure file and generates conformational ensembles computationally. It intersects with the cryo-EM workflows in two specific ways:

#### 1. Cross-Validation of Cryo-EM Heterogeneity

Run 12886 on a structure determined by 12833 (or any SPA workflow), then compare the BioEmu/MDAnalysis ensemble against the cryoDRGN conformational states from 12885:

- **Agreement**: validates that the experimentally observed heterogeneity is thermodynamically accessible
- **Discrepancies**: may reveal force-field artifacts, cryo-vitrification bias, or conformers missed by the cryo-EM dataset

#### 2. Standalone Drug Discovery Without Cryo-EM Data

When no experimental cryo-EM data exists, 12886 provides a purely computational ensemble for pocket analysis and downstream drug discovery:

```
PDB structure (AlphaFold, homology model, or experimental)
         │
         ▼
  Protein Dynamics (12886)
         │  outputs: conformers + pocket scan + UMAP
         ▼
  ADMET / Docking / Pharmacology workflows
```

### Input/Output Contract

- **Inputs**: `protein.pdb` (or `.fasta` for sequence-only mode; fallback to structure modeling required)
- **Outputs**: `ensemble_pdbs/*.pdb` (N conformers), `pocket_results/*.txt` (fpocket per-conformer), `summary_report.json`, `conformational_umap.png`
- **Key metrics**: RMSD distribution, Rg (radius of gyration), UMAP projection of conformational space

---

## Combined Drug Discovery Chain

The two new workflows compose naturally with existing cryo-EM and drug discovery workflows:

```
┌─────────────────────────────────────────────────────────┐
│                  EXPERIMENTAL DATA PATH                  │
│                                                         │
│  CryoSPARC SPA (12833)                                  │
│         │                                               │
│         ├──► cryoDRGN Heterogeneity (12885)             │
│         │           │                                   │
│         │           └──► ensemble_pockets.json          │
│         │                       │                       │
│         └──► export best-conformer PDB                  │
│                       │                                 │
└───────────────────────┼─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│                 COMPUTATIONAL PATH                       │
│                                                         │
│  Protein Dynamics (12886) ─────────────────────────────►│
│         │  (cross-validates cryo-EM OR                  │
│         │   runs standalone from PDB)                   │
│         └──► conformer ensemble + pockets               │
│                                                         │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
           Combined druggability analysis
                        │
           ┌────────────┴─────────────┐
           ▼                          ▼
    ADMET workflow             Docking workflow
    (12861–12884 range)        (DiffDock / AutoDock)
```

---

## Summary Table

| Workflow ID | Name | Upstream of 12885/86? | Downstream? | Parallel alternative? |
|---|---|---|---|---|
| 12833 | CryoSPARC Standard SPA | ✓ upstream of 12885 | — | — |
| 12808/09/12 | Saposin/GPCR/Liposome SPA | ✓ upstream of 12885 | — | — |
| 12836 | 3D Variability Pipeline | — | — | ✓ alternative to 12885 (linear vs. VAE) |
| 12813 | RELION Multi-Body Refinement | — | — | ✓ complementary to 12885 (rigid-body) |
| 12885 | **cryoDRGN Heterogeneity** | — | ✓ downstream of SPA | — |
| 12886 | **Protein Dynamics Ensemble** | — | ✓ downstream of any PDB | — |
| 12861–12884 | Drug dev gap workflows | — | ✓ downstream of 12885/86 | — |

---

## Current Limitations (as of 2026-04-26)

- **BioEmu not installed in container**: GitHub clone blocked at Docker build time; MDAnalysis Gaussian fallback (σ=0.5 Å) is used — valid for pipeline testing, not scientifically equivalent to learned generative sampling
- **PocketMiner not installed**: Same GitHub-access issue; fpocket geometry-based detection used as fallback
- **BIOEMU_SAMPLE on CPU queue**: Temporarily routed to `biomate-nextflow-queue`; should revert to `galaxy-cloud-queue-gpu` once real BioEmu is enabled
- **No direct Nextflow wiring between 12885 and 12886**: The cross-validation chain described above requires manual export of a PDB from the cryoDRGN output before running 12886 — a combined chain workflow is a future enhancement
