# Session: GROMACS + REINVENT4 Workflow Implementation

**Date**: 2026-03-21
**Branch**: connection_formal
**Status**: COMPLETE

---

## Why This Work Exists

This session is **Phase 3B** of a planned drug discovery workflow expansion. Here is the chain of decisions that led to it:

### The Gap BioMate Had

BioMate's drug discovery coverage before this session:

| Workflow | What it does | Status |
|---------|--------------|--------|
| `structure_prediction_docking` | AlphaFold3/Boltz-2 structure prediction + GNINA docking | ✅ running |
| `scaffold_hopping` | RDKit RECAP fragmentation + MMP analysis | ✅ running |
| `nca_pknca` | Non-compartmental PK analysis | ✅ running |
| `alphafold_db_search` | Structural search vs AlphaFold Human Proteome DB | ✅ running |

**The missing piece**: Every drug discovery project that does docking must next ask:
*"Does the ligand actually stay bound? What is the binding free energy?"*
BioMate had no answer. The standard workflow after docking is:

```
Docking (GNINA) → MD refinement → ΔGbind ranking → lead selection
                  ↑ this gap
```

Also missing: any way to **generate** new molecules. BioMate could evaluate compounds but not design them.

### Why GROMACS (not AMBER or OpenMM)

A survey of 35 tools across 8 categories was done (see `docs/20260321_drug_discovery_tool_survey.md`). GROMACS was selected because:

1. **LGPL-2.1** — fully free, containerizable with no redistribution restriction
2. **Official Docker Hub image** (`gromacs/gromacs`) — no image to build
3. **Dominant in academia** — ~45% of all MD publications use GROMACS; 10,000+ citations/year
4. **AMBER was demoted**: AMBER pmemd has a non-redistribution clause — it cannot be put in a shared Docker image deployed to multiple users. The UCSD license only permits individual use. This was an initial planning error that was caught during the survey.
5. **OpenMM alternative**: Valid, but GROMACS has 5–10× more users and better force-field documentation for protein-ligand systems.

### Why REINVENT4 (not other generative tools)

1. **Apache-2.0** — fully free, containerizable
2. **709 GitHub stars, J. Cheminform. 2024 publication** — pharma standard (AstraZeneca)
3. **4 design modes in one tool**: de novo, scaffold decoration, linker design, scaffold hopping — covers all generative use cases
4. **BioMate had zero generative workflows** — a clear competitive gap
5. **Alternatives considered**: DiffLinker (fragment linking only, narrower), ReinventCommunity (older), GraphINVENT (graph-based, harder to containerize). REINVENT4 is the most general.

### Schrödinger and MOE — why NOT built

- Schrödinger FEP+ is **$100,000/year** commercial (not $7,500 as initially estimated). No free tier. Building this now would serve zero current users.
- MOE requires FlexNet licensing and SVL scripting (no Python API). Niche use case (covalent docking). Will be built only if ≥3 users specifically request it.

---

## What Was Built

### 1. `gromacs_protein_md/main.nf`

**Path**: `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/gromacs_protein_md/main.nf`
**DB id**: 12799

An 8-process Nextflow workflow covering the full protein-ligand MD + MM-GBSA pipeline:

```
receptor.pdb + ligand.sdf
   ↓
1. LIGAND_PREP      — antechamber + parmchk2 → GAFF2 force-field params
2. SYSTEM_SETUP     — tleap: solvate, neutralize → GROMACS gro/top via ParmEd
3. EM               — GROMACS steepest descent (H-only → all-atom)
4. NVT_EQUIL        — 100 ps NVT thermostat (V-rescaling, position restrained)
5. NPT_EQUIL        — 100 ps NPT barostat (Parrinello-Rahman, position restrained)
6. PRODUCTION_MD    — N ns NPT production (default 10 ns = 5M × 2 fs steps)
7. TRAJ_ANALYSIS    — RMSD, RMSF, H-bond occupancy → PNG + CSV
8. MM_GBSA          — gmx_MMPBSA: ΔGbind ± SE + per-residue decomposition
   ↓
trajectory.xtc, binding_summary.json, rmsd_plot.png, mmgbsa_results.csv
```

**Key parameters**:
- `--force_field` amber99sb-ildn | charmm36m
- `--n_steps` 5000000 (10 ns default)
- `--temperature` 300 K
- `--mmgbsa_startframe` 500 (skip first 1 ns equilibration buffer)
- `--mock_mode true` for testing without GROMACS installed

**Mock mode produces**: synthetic RMSD convergence curves, density plots, ΔGbind ~ -8 kcal/mol, per-residue decomposition table.

**Containers**:
- `ambermd/ambertools:23` — LIGAND_PREP, SYSTEM_SETUP
- `gromacs/gromacs:2025.1` — EM through TRAJ_ANALYSIS
- `simonbray/gmx_mmpbsa:1.6.3` — MM_GBSA

---

### 2. `reinvent4_lead_design/main.nf`

**Path**: `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/reinvent4_lead_design/main.nf`
**DB id**: 12800

A 4-process Nextflow workflow for generative drug design:

```
seed_smiles + scoring_config
   ↓
1. VALIDATE_INPUT   — RDKit validation; add [*] attachment points for scaffold_decoration
2. REINVENT_DESIGN  — REINVENT4 RL loop: sample → score → update policy (N epochs)
3. FILTER_RANK      — PAINS filter, Lipinski, Tanimoto novelty, QED/SA thresholds,
                      Murcko scaffold diversity clustering, ETKDG 3D conformers → SDF
4. REPORT           — Score trajectory plot, HTML grid, design_summary.json
   ↓
generated_molecules.csv, top_compounds.sdf, score_trajectory.png, design_report.html
```

**Design modes** (via `--mode`):
- `de_novo` — unconstrained generation (uses `reinvent` prior)
- `scaffold_decoration` — grow R-groups on fixed core (uses `libinvent` prior)
- `linker_design` — connect two fragments (uses `linkinvent` prior)
- `scaffold_hopping` — find isosteric replacements (uses `mol2mol` prior)

**Scoring functions** (via `--scoring_function`):
- `qed_sa` — QED + synthetic accessibility (default, no target needed)
- `docking_gnina` — GNINA docking score against receptor (requires `--receptor`)
- `custom_toml` — user-supplied REINVENT4 TOML config

**Key parameters**:
- `--seed_smiles` starting scaffold/molecule
- `--n_steps` 500 (RL epochs; 200 for quick demo, 2000+ for production)
- `--top_n` 50 (molecules in final SDF)
- `--mock_mode true` for testing

**Mock mode produces**: 25 drug-like SMILES sampled across RL epochs, score trajectory, HTML report with color-coded compound table.

**Container**: `ghcr.io/molecularai/reinvent4:4.4.14`

---

## Registration + Routing

### galaxy_ai_tools.db

Both workflows registered with rich metadata:

| ID | Name | Tags (excerpt) |
|----|------|----------------|
| 12799 | GROMACS Protein-Ligand MD + MM-GBSA | gromacs, molecular-dynamics, mm-gbsa, binding-free-energy, protein-ligand, ambertools, gaff2, rmsd |
| 12800 | REINVENT4 Generative Lead Design | reinvent4, generative-design, de-novo, scaffold-hopping, scaffold-decoration, lead-generation, reinforcement-learning |

FTS full-text search verified: `gromacs` → returns id=12799; `reinvent4` → returns id=12800.

### AI System Prompt (`galaxy-assistant.ts`)

Two routing clauses added to the main BioMate response system prompt:

```
- For "MD simulation", "molecular dynamics", "protein stability", "binding free energy",
  "MM-GBSA", "post-docking refinement", or "explicit solvent MD":
  suggest the gromacs_protein_md workflow

- For "generative drug design", "de novo design", "scaffold hopping", "lead generation",
  "molecule optimization", "REINVENT", or "fragment decoration":
  suggest the reinvent4_lead_design workflow
```

### Search Scoring (`unified_workflow_search.py`)

14 new keyword weights added to the drug discovery scoring dict:

```python
'gromacs': 3.5, 'molecular dynamics': 3.5, 'md simulation': 3.5,
'mm-gbsa': 3.5, 'mmgbsa': 3.5, 'binding free energy': 3.5,
'reinvent': 3.5, 'reinvent4': 3.5, 'generative design': 3.5,
'de novo': 3.5, 'de-novo': 3.5, 'lead generation': 3.0, ...
```

---

## What Is Still NOT Done (on-demand only)

| Workflow | Reason not built yet |
|---------|----------------------|
| `openfe_rbfe` | Build when a user asks for rigorous ΔΔGbind (FEP accuracy) |
| `autodock_hts_screen` | Build when user has >10k compound library to screen |
| `haddock3_pp_docking` | Build when user asks for protein-protein or antibody docking |
| `difflinker_fbld` | Build when user asks for fragment linking by name |
| `xtb_conformer_gen` | Build when user asks for QM conformers or pKa prediction |
| Schrödinger Glide/FEP+ | Enterprise only ($100k/yr); build if clear enterprise customer |
| AMBER pmemd MD | Cannot containerize (redistribution prohibited); user must sign UCSD license |

---

## Files Changed

| File | Change |
|------|--------|
| `backend/biomni_workflows/.../gromacs_protein_md/main.nf` | **NEW** — 1,181 lines |
| `backend/biomni_workflows/.../reinvent4_lead_design/main.nf` | **NEW** — 977 lines |
| `backend/galaxy_ai_tools.db` | +2 workflow rows (id 12799, 12800) + FTS entries |
| `frontend/server/galaxy-assistant.ts` | +2 system prompt routing clauses |
| `backend/lib/galaxy/ai/unified_workflow_search.py` | +14 keyword scoring entries |
