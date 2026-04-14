# GROMACS & AMBER GPU — AWS Batch End-to-End Test
*April 2026 · Assignee: Platform Eng.*

This document is a self-contained task brief for running the GROMACS and AMBER pmemd molecular dynamics workflows on a real AWS Batch GPU instance. Both workflows exist and pass local mock tests. This test validates them against a real GPU workload and produces the evidence record needed for the drug discovery pilot.

---

## Background

Two GPU molecular dynamics workflows are in the codebase:

| Workflow | Path | Engine | Default run |
|---|---|---|---|
| `gromacs_protein_md` | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/gromacs_protein_md/` | GROMACS 2025 + gmx_MMPBSA | 10 ns (5M steps × 2 fs) |
| `amber_pmemd_md` | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/amber_pmemd_md/` | AMBER 24 pmemd.cuda + MMPBSA.py | 10 ns (5M steps × 2 fs) |

Both use the ECR image `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86` and submit to the `biomate-nextflow-queue` Batch queue.

---

## Test Case: BCR-ABL1 / imatinib

Use the ABL1 kinase domain co-crystallised with imatinib. This is the canonical drug discovery benchmark target.

| Input | Value |
|---|---|
| Receptor PDB | `1IEP` (ABL1 kinase domain + imatinib, 2.10 Å) — download from RCSB |
| Ligand SMILES | `Cc1ccc(cc1Nc2nccc(n2)c3cccnc3)NC(=O)c4ccc(cc4)CN5CCN(CC5)C` (imatinib) |
| Ligand name | imatinib |
| Chain to keep | Chain A only (strip waters, HETATM ligand STI retained for reference) |

**Preparation steps:**
1. Download `1IEP.pdb` from `https://files.rcsb.org/download/1IEP.pdb`
2. Keep chain A; strip waters; save as `bcrabl1_receptor.pdb`
3. Convert imatinib SMILES to `imatinib_ligand.sdf` using RDKit or OpenBabel:
   ```
   obabel -ismi "Cc1ccc(cc1Nc2nccc(n2)c3cccnc3)NC(=O)c4ccc(cc4)CN5CCN(CC5)C" -osdf -O imatinib_ligand.sdf --gen3d
   ```
4. Upload both files to S3: `s3://biomate-workflow-inputs/gromacs-gpu-test/`

---

## Run 1: GROMACS

### Submit command

```bash
cd backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/gromacs_protein_md

nextflow run main.nf \
  -profile aws \
  --receptor s3://biomate-workflow-inputs/gromacs-gpu-test/bcrabl1_receptor.pdb \
  --ligand   s3://biomate-workflow-inputs/gromacs-gpu-test/imatinib_ligand.sdf \
  --n_steps  5000000 \
  --temperature 300 \
  --outdir   s3://biomate-nextflow-outputs/gromacs-gpu-test/ \
  -work-dir  s3://biomate-nextflow-work/gromacs-gpu-test/ \
  -with-report report.html \
  -with-trace trace.txt
```

To use GPU acceleration, add `-profile aws,gpu` (requires the Batch queue to have a GPU compute environment attached — see **AWS Setup** below).

### Pipeline steps that run

1. `LIGAND_PREP` — AmberTools 23 antechamber: SMILES → GAFF2 mol2 + frcmod
2. `SYSTEM_SETUP` — gmx pdb2gmx + solvate + genion: TIP3P water box, 150 mM NaCl, net neutralisation
3. `ENERGY_MINIMIZATION` — steepest descent, convergence Fmax < 1000 kJ/mol/nm
4. `NVT_EQUILIBRATION` — 100 ps, heat 0 → 300 K, position-restrained heavy atoms
5. `NPT_EQUILIBRATION` — 100 ps, 300 K / 1 bar, Parrinello-Rahman barostat
6. `PRODUCTION_MD` — 10 ns NPT unrestrained MD
7. `TRAJECTORY_ANALYSIS` — RMSD backbone (protein), RMSD ligand heavy atoms, RMSF per residue
8. `MM_GBSA` — gmx_MMPBSA: ΔGbind (GB model), per-residue decomposition, frames 500 → end

### Pass criteria

| Check | Pass threshold | Notes |
|---|---|---|
| All 8 steps `status=COMPLETED` | Required | No process may exit non-zero |
| `binding_summary.json` present in S3 outdir | Required | Key output file |
| `rmsd_plot.png` present | Required | Visual stability check |
| Protein backbone RMSD plateau | ≤ 3.0 Å | Extracted from `rmsd_data.csv` |
| ΔGbind (MM-GBSA) produced | Any finite value | Absolute accuracy not checked at this stage |
| Total wall-clock time | ≤ 4 hours | On g4dn.xlarge or g4dn.2xlarge |

---

## Run 2: AMBER pmemd

### Submit command

```bash
cd backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/amber_pmemd_md

nextflow run main.nf \
  -profile aws \
  --receptor s3://biomate-workflow-inputs/gromacs-gpu-test/bcrabl1_receptor.pdb \
  --ligand   s3://biomate-workflow-inputs/gromacs-gpu-test/imatinib_ligand.sdf \
  --n_steps  5000000 \
  --temperature 300 \
  --outdir   s3://biomate-nextflow-outputs/amber-gpu-test/ \
  -work-dir  s3://biomate-nextflow-work/amber-gpu-test/ \
  -with-report report.html \
  -with-trace trace.txt
```

### Pipeline steps that run

1. `LIGAND_PREP` — antechamber (GAFF2) + parmchk2
2. `SYSTEM_SETUP` — tleap: ff19SB + GAFF2, TIP3P solvation, net neutralisation, AMBER topology
3. `ENERGY_MINIMIZATION` — sander: 2500-step H-only + 2500-step all-atom steepest descent
4. `EQUILIBRATION` — pmemd.cuda: 100 ps NVT (0 → 300 K, restrained) + 100 ps NPT (1 atm, restrained)
5. `PRODUCTION_MD` — pmemd.cuda: 10 ns NPT unrestrained
6. `TRAJECTORY_ANALYSIS` — cpptraj: RMSD, RMSF, H-bonds, radius of gyration
7. `MM_GBSA` — MMPBSA.py: GB model igb=2, per-residue energy decomposition

### Pass criteria

| Check | Pass threshold | Notes |
|---|---|---|
| All 7 steps `status=COMPLETED` | Required | |
| `binding_summary.json` present | Required | ΔGbind field must be numeric |
| `rmsd_plot.png` present | Required | |
| Ligand RMSD plateau | ≤ 3.0 Å | From `trajectory_analysis/` |
| ΔGbind (MM-GBSA) | Any finite value, typically −5 to −12 kcal/mol | imatinib/ABL1 published ≈ −10 kcal/mol |
| Total wall-clock time | ≤ 4 hours | On g4dn.xlarge |

---

## AWS Setup Required

### Batch compute environment

Both workflows need a GPU-enabled Batch compute environment. If one does not yet exist:

```
Name:       biomate-gpu-compute-env
Type:       MANAGED, EC2 (not Fargate — GPU not supported on Fargate)
AMI:        Amazon Linux 2 ECS-optimized GPU AMI (auto-selected by Batch)
Instance types: g4dn.xlarge (1× NVIDIA T4, 4 vCPUs, 16 GB RAM)
               g4dn.2xlarge (1× T4, 8 vCPUs, 32 GB RAM) — use if OOM
Min vCPUs:  0
Max vCPUs:  8
IAM role:   ecsInstanceRole (needs S3 + ECR read access)
```

Then create a GPU job queue:
```
Name:       biomate-gpu-queue
Priority:   10
Compute env: biomate-gpu-compute-env
```

And update the Nextflow config to use it for GPU processes (or pass `-profile aws` and override the queue via `--queue biomate-gpu-queue`).

### ECR image

The workflows use `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86`.  
Verify this image contains GROMACS 2025, AmberTools 23, and gmx_MMPBSA before submitting:

```bash
aws ecr describe-images \
  --repository-name biomate/biomni-drug-discovery-nf \
  --image-ids imageTag=x86 \
  --region us-west-2
```

If the image is untagged layers only (see open task 1.2 in `20260408_PILOT_STUDY_OPEN_TASKS.md`), build and push it first.

---

## Outputs to Capture

After both runs complete, collect the following for the pilot evidence record:

```
gromacs-gpu-test/
  binding_summary.json          -- ΔGbind, RMSD stats, step timing
  rmsd_plot.png                 -- protein backbone + ligand RMSD vs time
  rmsf_per_residue.csv          -- residue-level flexibility
  mmgbsa_results.csv            -- per-residue energy decomposition
  pipeline_info/timeline.html   -- per-step wall-clock times
  pipeline_info/trace.txt       -- CPU/memory/exit codes for each task

amber-gpu-test/
  binding_summary.json
  rmsd_plot.png
  trajectory_analysis/rmsd.csv
  mmgbsa_results.csv
  pipeline_info/timeline.html
  pipeline_info/trace.txt
```

Upload the `pipeline_info/` folders and `binding_summary.json` files to:  
`s3://biomate-pilot-evidence/md-gpu-test-20260408/`

---

## What to Report Back

Create a brief note (can be a Slack message or email) with:

1. **GROMACS result**: PASS / FAIL — ΔGbind value, backbone RMSD plateau, total runtime
2. **AMBER result**: PASS / FAIL — ΔGbind value, ligand RMSD plateau, total runtime
3. **GPU instance used**: instance type, Batch queue name
4. **Any failures**: exact error message + which step failed

If either workflow fails with a container error, check open task 1.2 first (ECR image may be missing required tools). If it fails with an AWS CLI error (`No such file: /opt/aws-cli/bin/aws`), check open task 1.1.

---

## References

- GROMACS workflow: `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/gromacs_protein_md/main.nf` (961 lines)
- AMBER workflow: `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/amber_pmemd_md/main.nf` (772 lines)
- Open tasks doc: `docs/nextPhase/20260408_PILOT_STUDY_OPEN_TASKS.md` (tasks 1.1, 1.2, 5.1)
- BCR-ABL1/imatinib structure: Schindler T et al. *Science* 289:1938–1942 (2000); PDB 1IEP
- AmberTools GAFF2: Wang J et al. *J. Comput. Chem.* 25:1157–1174 (2004)
- GROMACS: Abraham MJ et al. *SoftwareX* 1–2:19–25 (2015)
- AMBER: Case DA et al. *J. Chem. Inf. Model.* 63:6183–6200 (2023)

---

*Generated 2026-04-08 · BioMate AI · Assign to Platform Eng.*
