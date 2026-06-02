# AWS Batch HPC queue repair + GROMACS MM-GBSA session notes

**Date:** 2026-06-02  
**Campaign:** ANDV publication `publication_20260528T223525Z`  
**Detailed run log:** `research/anti-virus/runs/publication_20260528T223525Z/SESSION_20260602_GROMACS_HPC_INFRA.md`

---

## HPC queue (`biomate-hpc-queue`) — why it broke

The compute environment `biomate-nextflow-hpc-v1` was **INVALID** because EC2 instances could not join the ECS cluster.

**Cause:** Launch template `nextflow-awscli-mime-20251127-223103` **version 12** runs `systemctl stop ecs` in cloud-init `bootcmd`. If user-data fails before `systemctl start ecs`, instances never register with Batch.

**Symptom:** Jobs on `biomate-hpc-queue` stuck in **RUNNABLE** with zero **RUNNING** jobs — not because of competing workload, but because the CE could not scale.

**Fix:** Align with healthy `biomate-nextflow-ce-v2`:

- Launch template: `lt-099eb24c4fe1b477e` version **9**
- AMI: `ami-08fe495be97a3dbf4` via `ec2Configuration.imageIdOverride`
- Subnets: all four VPC subnets used by ce-v2
- Re-enable fallback CE `biomate-nextflow-cpu-v2` (LT v16)

**Script:** `infra/scripts/fix_biomate_hpc_batch_ce.sh`  
**Verified:** CE **VALID**; smoke job **SUCCEEDED** on `biomate-hpc-queue`.

**Do not use** LT v12 for new Batch CEs.

---

## Stale RUNNABLE jobs — why they persist

AWS Batch does not expire RUNNABLE jobs automatically. BioMate has no cleanup hook when:

- Nextflow head process exits without cancelling Batch submissions
- A compute environment goes INVALID (jobs wait forever)

Seven orphans (AlphaFold searches from April, prep jobs from May, MM-GBSA retries) were manually cancelled 2026-06-02.

**Recommendation:** Configure `jobStateTimeLimitActions` on queues (e.g. cancel RUNNABLE > 7 days).

---

## GROMACS inh01 — outcomes

| Step | Status | Notes |
|------|--------|-------|
| Prep / EM / NVT / NPT | OK | `biomate-nextflow-queue` / HPC |
| PRODUCTION_MD | OK | CPU fallback after OpenCL GPU failure; 500k steps |
| TRAJECTORY_ANALYSIS | OK | RMSD mean 0.41 nm |
| MM-GBSA | Partial | Standalone Batch job succeeded; ΔG_bind **null** (MPI missing in container) |

Primary run ID: `28fd9a07-a31d-4ba8-a8e1-e49dc8abb777`  
S3 outdir: `.../d64daac1/`

---

## Spot GPU queue

`biomate-gpu-spot-v1` lacked pre-baked AWS CLI → `PRODUCTION_MD` exit 127 on first spot attempt (`33193f6f`). Fixed with `ami-0f02c2b015a9cf35c` override (same as on-demand GPU industrial CE).

---

## Code / infra artifacts

- `gromacs_protein_md/main.nf` — drop `-bonded gpu` for OpenCL GROMACS
- `gromacs_protein_md/nextflow.config` — route CPU/MM-GBSA to `biomate-hpc-queue`
- `backend/docker/ambertools-gromacs-nf/Dockerfile` — AWS CLI at `/opt/aws-cli` (rebuild pending)
- `research/anti-virus/scripts/run_mmgbsa_standalone_batch.sh` — MM-GBSA from S3 artifacts

---

## Next steps

1. Rebuild ECR image with `gmx_mmpbsa`, OpenMPI, and CUDA-capable GROMACS
2. Re-run MM-GBSA after image fix
3. Add Batch queue job TTL policy
4. Optional: full-length (5M step) production MD on on-demand GPU
