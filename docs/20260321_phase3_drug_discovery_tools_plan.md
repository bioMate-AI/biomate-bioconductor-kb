# Phase 3: Drug Discovery Tool Integration Plan

**Date**: 2026-03-21
**Status**: Planning — AMBER/Schrödinger/MOE credential gate done; workflows not yet built
**Branch**: connection_formal → merge to stronger_backend when ready

---

## Context: What BioMate Has Today

### Drug-discovery workflows in DB
| ID | Name | Tools | Status |
|----|------|-------|--------|
| 10642 | NCA/PKNCA | pk-pknca R | ✅ running |
| 10643 | Scaffold Hopping | rdkit, DeepFrag | ✅ running |
| 10644 | Structure Prediction + Docking | AlphaFold3/Chai-1/Boltz-2 + GNINA | ✅ mock; AF3 gated |
| 12647 | AlphaFold DB Search | Foldseek + MMseqs2 | ✅ mock; S3 DB building |

### License gate status
| Tool | Type | Source |
|------|------|--------|
| alphafold3 | docker_auth | none (apply at EBI) |
| boltz2 | api_key | none (apply NVIDIA NIM) |
| chai1 | none | biomate |
| cryosparc | license_key | biomate |
| amber | license_agreement | biomate (always resolved) |
| schrodinger | license_server | none (user's FlexLM) |
| moe | license_server | none (user's FlexNet) |

### Current gap
BioMate has **zero** Nextflow workflows for AMBER, Schrödinger, or MOE. The AI knows about these tools in general (Claude Haiku general knowledge) but cannot generate parameterized, executable workflows for them.

---

## Phase 3A: AMBER MD (Highest Priority)

### Why first
- Free for academic since April 2023 (no sales contact needed)
- pmemd.cuda: 5–10× faster than OpenMM on GPU
- MM-GBSA: competitive binding ΔG at ~1/100th FEP cost
- Directly extends the current docking workflow (docking → MD refinement → MM-GBSA ranking)

### Workflow: `protein_ligand_md`

**Path**: `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/protein_ligand_md/main.nf`

**Input → Output**:
```
receptor.pdb + ligand.sdf (or SMILES) + [n_steps, temp, ff]
   ↓
1. LIGAND_PREP     — antechamber + parmchk2 → GAFF2 params
2. SYSTEM_SETUP    — tleap: solvate, neutralize → complex.prmtop + complex.inpcrd
3. MINIMIZE        — sander: 2500 H-only + 2500 all-atom steepest descent
4. EQUILIBRATE     — pmemd.cuda: 100 ps NVT + 100 ps NPT (restrained)
5. PRODUCTION_MD   — pmemd.cuda: N ns NPT (default 10 ns)
6. ANALYSIS        — cpptraj: RMSD, RMSF, Rg, H-bonds
7. MM_GBSA         — MMPBSA.py: ΔGbind + per-residue decomposition
   ↓
outputs: trajectory.nc, mmgbsa_results.dat, rmsd.png, binding_summary.json
```

**Parameters**:
```
--receptor        receptor.pdb / S3 URI
--ligand          ligand.sdf / SMILES string
--n_steps         10000000   (10 ns production)
--temperature     300        (K)
--force_field     ff19SB     (ff14SB | ff19SB)
--water_model     tip3p      (tip3p | opc)
--box_padding     12         (Å from protein surface)
--n_cpus          8
--gpu             true
```

**Container**: `399683337364.dkr.ecr.us-west-2.amazonaws.com/amber24-cuda:latest`
(To build: register ambermd.org → download Amber24 → compile with CUDA → push to ECR)

**Mock mode**: synthetic RMSD/RMSF curves + placeholder MM-GBSA table (ΔGbind ~ -8 kcal/mol)

### Implementation steps
1. Register ambermd.org (free, instant)
2. Launch spot p3.2xlarge → compile Amber24 with CUDA → push ECR image
3. Write `main.nf` with 7 processes
4. Register in `galaxy_ai_tools.db` with tags: `amber, md, mm-gbsa, protein-ligand, binding-affinity`
5. Add system prompt context: "For MD simulations and MM-GBSA binding energy, use protein_ligand_md"
6. Mock run + E2E test

---

## Phase 3B: Schrödinger Suite (Medium Priority)

### Why
- FEP+ has no free equivalent at comparable accuracy
- Many big pharma users have institutional licenses
- Glide XP/SP is the industry benchmark for high-quality docking pose prediction

### Blocker
No free tier. Need either: (a) dev trial (schrodinger.com/freeTrial), or (b) wait for a beta user with institutional license.

### Proposed workflows

**1. `glide_docking`** — High-accuracy docking for hit-to-lead
```
receptor_grid.zip + ligands.sdf → Glide SP/XP → poses.sdf + docking_report.html
```

**2. `fep_plus_rbfe`** — Lead optimization relative binding FEP
```
protein.mae + reference_ligand.sdf + perturbation_map.csv → FEP+ → ΔΔGbind predictions + uncertainty
```

**3. `ligprep_pipeline`** — Ligand preparation (standalone utility)
```
ligands.sdf → LigPrep (ionization, tautomers, 3D) → ligands_prepared.sdf
```

### Infrastructure required
- Schrödinger Suite 2024+ installed in private ECR image (~80 GB; store on EFS not in image layer)
- FlexLM server: EC2 t3.small in us-west-2 VPC; always-on (~$15/month)
- Env var injection: `SCHRODINGER_LICENSE_FILE=27008@<private-ip>`

### Implementation steps
1. Request trial: https://www.schrodinger.com/freeTrial
2. Once approved: build ECR image; start FlexLM EC2
3. Write `main.nf` for glide_docking (start simple)
4. Register in DB with tags: `schrodinger, glide, docking, fep, lead-optimization`
5. Mock run + E2E

---

## Phase 3C: MOE (Low Priority — Demand-Gated)

### Why low priority
- No free tier, requires CCG sales contact
- SVL scripting only — no Python bindings (development friction)
- Use cases (covalent docking, FBDD) are specialist workflows

### Trigger condition
Implement when **3+ beta users** specifically request covalent docking or fragment-based drug design.

### Proposed workflow (when triggered)
**`moe_covalent_docking`**:
```
receptor.pdb + warhead_smiles + reactive_residue → MOE CovDock → covalent_poses.sdf + binding_modes.html
```

### Implementation steps (deferred)
1. Request CCG 15-day trial: chemcomp.com
2. Survey beta users for existing MOE site licenses
3. Build ECR image with MOE + SVL scripts
4. Write Python → SVL → subprocess bridge layer

---

## ⚠️ Revised Assessment: AMBER pmemd Demotion

**AMBER is demoted from Tier 1 to Tier 3.** The license prohibits redistribution — pmemd cannot be baked into a shared BioMate Docker image deployed at scale without each user individually signing the UCSD license agreement. This is a harder constraint than originally assessed.

**Alternative**: Use **AmberTools** (free GPL, conda-forge) for ligand parameterization (antechamber, tleap, GAFF2 force field) within a GROMACS-based MD workflow. Users get the same force fields (ff19SB, GAFF2) without the redistribution problem.

**GROMACS** is the correct Tier-1 MD engine: LGPL-2.1, official Docker `gromacs/gromacs`, AWS Batch workshop exists.

---

## Revised Priority: Full Open-Source Tier 1

> _Full landscape: see `docs/20260321_drug_discovery_tool_survey.md`_

### Gap Analysis vs. Competitive Platforms

BioMate currently **has zero workflows** for these Tier-1 open-source tools — all are fully containerizable, high-impact, and used daily in drug discovery:

| Missing Workflow | Tool | License | Docker | Scientific Use Case |
|----------------|------|---------|--------|---------------------|
| `gromacs_protein_md` | GROMACS 2025 | LGPL-2.1 | Official | Protein-ligand MD, stability, MM-GBSA |
| `reinvent4_lead_design` | REINVENT4 | Apache-2.0 | Unofficial | de novo design, scaffold hopping, RL optimization |
| `openfe_rbfe` | OpenFE + OpenMM | MIT | Yes | RBFE free energy perturbation (≈FEP+ accuracy) |
| `autodock_hts_screen` | AutoDock-GPU | LGPL-2.1 | NVIDIA NGC | HTS virtual screening (millions/day) |
| `xtb_conformer_gen` | xTB + CREST | LGPL-3.0 | conda-forge | QM conformer ensembles, pKa, reactivity |
| `haddock3_pp_docking` | HADDOCK3 | Apache-2.0 | Yes | Protein-protein docking with restraints |
| `difflinker_fbld` | DiffLinker | MIT | Unofficial | Fragment-based drug design linker generation |
| `admet_screening` | ADMET-AI | MIT | Yes | 41-endpoint ADMET prediction (TDC #1) |

### Significant 2025 Developments That Change Priorities

1. **OpenFE ≈ FEP+ accuracy** (ChemRxiv 2025, multi-company assessment): The gap between $100k/yr FEP+ and open-source RBFE is largely closed. OpenFE should be a top-priority workflow.

2. **Schrödinger FEP+ is $100k/yr** (not $7.5k as estimated): Enterprise-only. Do not prioritize Schrödinger integration until a clear enterprise customer segment is established.

3. **Boltz-2 binding affinity**: BioMate already has Boltz-2 integrated but only uses structure prediction. The joint ΔGbind output is not surfaced to users — a quick win to differentiate.

4. **AutoDock-GPU via NVIDIA NGC**: Free container from NVIDIA, 50-100x faster than serial AutoDock 4, LGPL. No work needed to build the image.

---

## Revised Implementation Plan

## Focused Plan: 2 Workflows Cover the Core Gap

Academic users converge on a short stack. BioMate already covers structure prediction
(Boltz-2, Chai-1) and docking (GNINA). The two missing pieces that matter to 80% of users:

### Priority 1 — `gromacs_protein_md`
**Why**: GROMACS is the dominant academic MD engine. MM-GBSA (binding free energy) is
the most widely used post-docking validation step. Together these close the
docking → MD refinement → ΔGbind ranking loop that every drug discovery project runs.

| | Details |
|-|---------|
| Tool | GROMACS 2025.3 |
| License | LGPL-2.1 (free, Docker OK) |
| Container | `gromacs/gromacs` (official Docker Hub) |
| Input | receptor.pdb + ligand.sdf (or from docking output) |
| Output | trajectory.xtc, MM-GBSA ΔGbind, RMSD plot, binding_summary.json |
| Steps | AmberTools (antechamber/tleap for GAFF2) → GROMACS minimize → equilibrate → production → gmx_MMPBSA |
| Mock mode | Synthetic RMSD curve + ΔGbind ~ -8 kcal/mol |
| Effort | 1.5 days |

### Priority 2 — `reinvent4_lead_design`
**Why**: REINVENT4 is the pharma standard for generative drug design (AstraZeneca,
Apache-2.0, 709 stars). BioMate has zero generative workflow — a clear gap for users
who want to go beyond hit-to-lead.

| | Details |
|-|---------|
| Tool | REINVENT4 |
| License | Apache-2.0 (free, Docker OK) |
| Container | Build from source (pip installable) |
| Input | seed_smiles, scoring_function config, n_steps |
| Output | generated_molecules.csv, score_trajectory.png, top_compounds.sdf |
| Steps | Single REINVENT4 process (RL optimization loop) |
| Mock mode | 5 synthetic SMILES with scores |
| Effort | 1 day |

---

### On-demand (implement when users ask)

| Workflow | Tool | Trigger |
|---------|------|---------|
| `openfe_rbfe` | OpenFE | User asks for rigorous lead optimization ΔΔG |
| `autodock_hts_screen` | AutoDock-GPU | User has >10k compound library to screen |
| `haddock3_pp_docking` | HADDOCK3 | User asks for protein-protein or antibody docking |
| `difflinker_fbld` | DiffLinker | User asks for fragment linking |
| `xtb_conformer_gen` | xTB + CREST | User asks for QM conformers or pKa |

### License-gated (user brings own)

| Workflow | Tool | When |
|---------|------|------|
| `schrodinger_glide` | Glide/FEP+ | Enterprise customers ($100k+/yr) |
| `moe_covalent_dock` | MOE | ≥3 users request covalent docking |
| `amber_pmemd_md` | AMBER pmemd | User explicitly prefers AMBER (signed license) |

---

## AI System Prompt (Minimal — 2 new clauses)

```
- For "MD simulation", "molecular dynamics", "protein stability", "binding free energy",
  "MM-GBSA", "post-docking refinement": suggest gromacs_protein_md
- For "generative drug design", "de novo design", "scaffold hopping", "lead generation",
  "molecule optimization", "REINVENT": suggest reinvent4_lead_design
```

## Immediate Actions

- [ ] Write `gromacs_protein_md/main.nf` with mock mode
- [ ] Write `reinvent4_lead_design/main.nf` with mock mode
- [ ] Register both in `galaxy_ai_tools.db`
- [ ] Add 2 system prompt clauses to `galaxy-assistant.ts`
