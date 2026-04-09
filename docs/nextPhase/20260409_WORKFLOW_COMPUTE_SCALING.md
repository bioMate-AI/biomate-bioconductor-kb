# BioMate Workflow Compute Scaling — 2026-04-09

## Why workflows are slow: root causes

### 1. Instance family mismatch (biggest factor)
The original `biomate-nextflow-cpu-v1` compute environment used `m5.large / m5.xlarge / m5.2xlarge`.
The `m5` family is **general-purpose** (balanced CPU/memory). For compute-intensive scientific
workloads (GROMACS, Foldseek, AMBER prep), compute-optimized `c5` instances deliver ~25–30% higher
single-thread throughput at the same cost-per-vCPU.

| Instance     | vCPU | RAM  | $/hr  | Use for |
|---|---|---|---|---|
| c5.xlarge    | 4    | 8 GB | $0.17 | Light CPU: data parsing, CSV, CRO export |
| c5.2xlarge   | 8    | 16 GB| $0.34 | Medium CPU: pharmacophore, DESeq2 (small) |
| c5.4xlarge   | 16   | 32 GB| $0.68 | Heavy CPU: GROMACS EM/NVT/NPT, Foldseek |
| c5.9xlarge   | 36   | 72 GB| $1.53 | Very heavy: large Foldseek, OpenFE RBFE |
| r5.4xlarge   | 16   |128 GB| $1.01 | Memory-heavy: AlphaFold3, large DESeq2 |
| g4dn.xlarge  | 4    | 16 GB| $0.53 | GPU: MD production, DiffDock |
| g4dn.2xlarge | 8    | 32 GB| $0.75 | GPU: large GPU MD, OpenFE RBFE production |

### 2. Per-Batch-job startup overhead (~2.5 min each)
Each Nextflow process submits a separate AWS Batch job. The EC2 instance must:
spin up → pull Docker image from ECR → stage S3 inputs → start process.
With 8 sequential GROMACS steps × 2.5 min overhead = **20 min of pure infrastructure overhead**
on every pipeline run, regardless of compute time.

### 3. Inherently sequential pipelines
MD simulation requires sequential steps: each depends on the prior output.
```
LIGAND_PREP → SYSTEM_SETUP → EM → NVT → NPT → PRODUCTION_MD → ANALYSIS → MM_GBSA
```
No step can run in parallel. This is a physics constraint, not a BioMate limitation.

### 4. Expected wall times (50k-step demo run, post-upgrade)

| Step | Instance | Compute | Overhead | Total |
|---|---|---|---|---|
| LIGAND_PREP | c5.2xlarge | ~5 min | 2.5 min | ~8 min |
| SYSTEM_SETUP | c5.2xlarge | ~8 min | 2.5 min | ~11 min |
| ENERGY_MINIMIZATION | c5.4xlarge | ~20 min | 2.5 min | ~23 min |
| NVT (2-stage, 100 ps) | c5.4xlarge | ~30 min | 2.5 min | ~33 min |
| NPT (100 ps) | c5.4xlarge | ~30 min | 2.5 min | ~33 min |
| PRODUCTION_MD (GPU) | g4dn.xlarge | ~8 min | 5 min | ~13 min |
| TRAJECTORY_ANALYSIS | c5.2xlarge | ~10 min | 2.5 min | ~13 min |
| MM_GBSA | c5.4xlarge | ~20 min | 2.5 min | ~23 min |
| **Total** | | **~131 min** | **~22 min** | **~157 min** |

Real production (5M steps, 10 ns) would be ~15–40 hours — this is inherent to MD simulation physics.

---

## What we changed (pre-configured, not ad hoc)

### Compute environment architecture

**Before:** One CE (`biomate-nextflow-cpu-v1`) with `m5.large / m5.xlarge / m5.2xlarge` for everything.

**After:** Two CPU tiers + existing GPU:

| Queue | CE | Instances | Purpose |
|---|---|---|---|
| `biomate-nextflow-queue` | `biomate-nextflow-cpu-v1` | `c5.xlarge`, `c5.2xlarge` | Light CPU (≤8 vCPU, ≤16 GB): data processing, CRO export, pharmacophore, pocket detection |
| `biomate-hpc-queue` | `biomate-nextflow-hpc-v1` | `c5.4xlarge`, `c5.9xlarge`, `r5.4xlarge` | Heavy CPU (16+ vCPU, 32+ GB): MD prep, Foldseek, RBFE, DESeq2 |
| `galaxy-cloud-queue-gpu` | `galaxy-cloud-compute-gpu-industrial` | `g4dn.xlarge` – `g4dn.16xlarge` | GPU: MD production, DiffDock, AlphaFold3 |

### Why c5 over m5?
- `c5` uses Intel Xeon Platinum / AMD EPYC, higher clock speed than `m5`
- **Same cost per vCPU** ($0.0425/vCPU-hr for both c5 and m5) — no cost increase
- `c5` has higher memory bandwidth, critical for GROMACS PME electrostatics
- `r5.4xlarge` added for jobs needing >32 GB RAM (AlphaFold3: 64 GB, large RNAseq)

### Why `BEST_FIT_PROGRESSIVE` allocation strategy?
AWS Batch picks the smallest instance that satisfies the job's `cpus` + `memory` request.
This means: a 4-vCPU job gets `c5.xlarge`, an 8-vCPU job gets `c5.2xlarge`, a 16-vCPU job
gets `c5.4xlarge`. No over-provisioning — resources match the workload.

---

## Workflows updated (pre-configured in nextflow.config)

All changes are in the workflow's `nextflow.config` under the `gpu_batch` or `aws` profile.
The queue assignment lives in the code — no AWS console intervention needed for new runs.

### Moved to `biomate-hpc-queue`

| Workflow | Why heavy? | Key resource upgrade |
|---|---|---|
| `gromacs_protein_md` | GROMACS PME is memory-bandwidth-bound | NVT/NPT: 8→16 vCPU, 16→32 GB |
| `amber_pmemd_md` | AMBER similar to GROMACS for prep steps | EM/NVT/NPT: new 16 vCPU, 32 GB entries |
| `alphafold_db_search` | Foldseek structural search scales with vCPU | Foldseek/MMseqs2: 8→16 vCPU, 32→64 GB |
| `openfe_rbfe` | RBFE setup/analysis are memory-intensive graph computations | RBFE_SETUP/ANALYSIS: 4→16 vCPU, 16→32 GB |
| `drug_moa_rnaseq` | DESeq2 loads full count matrix into R memory | DESeq2: 4→8 vCPU, 16→32 GB |
| `reinvent4_lead_design` | REINVENT4 RL training requires large model in RAM | GENERATE: 4→8 vCPU, 16→32 GB |

### Stayed on `biomate-nextflow-queue` (light CPU)
`assay_ingestion_and_ranking`, `cro_submission_export`, `cyp_ddi_panel`,
`pharmacophore_filtering`, `pocket_detection_druggability`, `nca_pknca`,
`aizynthfinder_retrosynthesis`, `p0_*` validation workflows.
These are pure data processing (pandas, RDKit, R) that fit in 2–4 vCPU / 4–8 GB.

---

## GROMACS NVT stability fix (Batch19)

### Root cause of step-111 failures (Batch17 + Batch18)
Both failed at **exactly step 111** regardless of timestep (dt=0.002 → step 111 = 0.222 ps;
dt=0.001 → step 111 = 0.111 ps). This confirmed the failure was **step-count driven, not
wall-time driven** — pointing to initial velocity assignment, not numeric precision.

**What happens without `gen_vel`:** GROMACS EM produces a structure with zero velocities.
When NVT starts with `ref_t = 310 K`, V-rescale thermostat immediately applies a large
velocity scaling to bring the system from 0 K to 310 K. On step 1, every atom gets a
random large velocity. For the imatinib ligand (GAFF2 params, C-H bonds), some H atoms
receive velocities that stretch their bonds transiently before LINCS can correct them.
By step 111, enough bond distortions have accumulated to make water SETTLE impossible.

### Fix: two-stage NVT heating
```
Stage 1: 10 ps at 100 K  (gen_vel=yes, gen_temp=100K, lincs_iter=2, lincs_order=6)
Stage 2: 90 ps at target T (continues from stage-1 output)
```

Stage 1 assigns velocities from a 100 K Maxwell-Boltzmann distribution — 3.1× lower
kinetic energy than at 310 K. This keeps bond velocities within LINCS correction range.
By the end of stage 1 (10 ps), the system is thermalized at 100 K and can heat safely
to target T in stage 2.

`lincs_iter=2` (default 1) and `lincs_order=6` (default 4) increase LINCS accuracy for
highly-constrained ligand bond geometries.

---

## Near-future: spot instances + GPU capacity backup

See `docs/nextPhase/20260409_SPOT_AND_GPU_BACKUP_PLAN.md` for the optimization plan.
Summary:
- g4dn capacity is constrained in us-west-2 → add g5.xlarge (A10G) as backup
- Spot instances reduce GPU cost 60–70% but need checkpoint/resume support
- GROMACS native `.cpt` checkpoints enable spot-safe MD (restart from last checkpoint)
