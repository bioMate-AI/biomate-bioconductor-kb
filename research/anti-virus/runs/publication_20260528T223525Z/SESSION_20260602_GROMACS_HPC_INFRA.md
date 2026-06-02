# Session log — GROMACS inh01, MM-GBSA, Batch HPC queue repair

**Date:** 2026-06-01 / 2026-06-02  
**Campaign run:** `publication_20260528T223525Z`  
**Pipeline run (inhibitor):** `andv_nf_pipeline_20260513T032000Z`  
**Branch:** `integration/next-phase` (commit `9f09aef59` — ANDV artifacts + GROMACS GPU routing)

---

## Executive summary

| Area | Outcome |
|------|---------|
| **inh01 production MD** | **Complete** on CPU fallback (~500k steps, ~1 ns); `trajectory.xtc` 15 MB on S3 |
| **Trajectory analysis** | **Complete** — backbone RMSD mean 0.41 nm |
| **MM-GBSA** | **Job ran** via standalone Batch script; **ΔG_bind null** (gmx_MMPBSA MPI runtime error in container) |
| **Spot GPU queue** | aws-cli 127 fixed (AMI override on `biomate-gpu-spot-v1`) |
| **HPC queue** | Was **INVALID** → **repaired and smoke-tested** |
| **Stale Batch jobs** | 7 zombie RUNNABLE jobs **cancelled** |

---

## 1. GROMACS inh01 — run timeline

### Ligand

SMILES `N=C(N)NC(=O)c1nccnc1N` (inh01), pocket-box crop on 9P3I, 500k MD steps (smoke / ~1 ns).

### Run `33193f6f` — spot GPU queue (failed)

- Queue: `biomate-gpu-spot-queue`
- **Failure:** `PRODUCTION_MD` exit **127** — `/opt/aws-cli/bin/aws: No such file or directory`
- **Cause:** Spot CE used stock `ECS_AL2023_NVIDIA` without pre-baked AWS CLI; user-data race on cold instances
- **Fix applied:** `biomate-gpu-spot-v1` updated to `imageIdOverride=ami-0f02c2b015a9cf35c` + LT `$Latest`

### Run `28fd9a07` — on-demand GPU queue (MD complete, MM-GBSA stuck)

- Queue: `galaxy-cloud-queue-gpu` (PRODUCTION_MD), `biomate-hpc-queue` (MM-GBSA)
- **PRODUCTION_MD:** GPU attempt failed (OpenCL GROMACS + `-bonded gpu`); **CPU fallback succeeded** (~19.5 h)
- **Outputs:** `s3://biomate-nextflow-work/.../d64daac1/md/trajectory.xtc`, `analysis/rmsd_plot.png`
- **MM-GBSA:** Submitted to `biomate-hpc-queue`, stuck **RUNNABLE** (see §3)

### Code change — GPU flags (not yet in ECR rebuild)

`gromacs_protein_md/main.nf`: removed `-bonded gpu` from `PRODUCTION_MD` GPU flags (conda GROMACS is OpenCL; bonded-on-GPU unsupported). Next run may get partial GPU acceleration.

---

## 2. MM-GBSA — queue blockage and standalone relaunch

### Why MM-GBSA never started (Nextflow path)

`MM_GBSA` was routed to `biomate-hpc-queue` → CE `biomate-nextflow-hpc-v1` was **INVALID** (§3). No RUNNING jobs; 7 stale RUNNABLE orphans (April–June) blocked nothing but also never cleared.

### Stale jobs cancelled (2026-06-02)

| Job name | Submitted |
|----------|-----------|
| `ALPHAFOLD_DB_SEARCH` ×2 | 2026-04-17 |
| `PROTEIN_PREP`, `LIGAND_PREP` | 2026-05-07 |
| `MM_GBSA_mm_gbsa` ×3 | 2026-05-29 – 2026-06-01 |

### Why Batch does not auto-remove RUNNABLE jobs

- AWS Batch keeps job records until a **terminal** state (`SUCCEEDED`, `FAILED`, `CANCELLED`)
- No `jobStateTimeLimitActions` configured on BioMate queues
- Nextflow/Galaxy do not cancel Batch jobs when the head process exits or CE breaks
- **Recommendation:** add queue TTL (e.g. cancel RUNNABLE > 7 days) + periodic cleanup Lambda

### Standalone MM-GBSA (working path)

Full Nextflow `-resume -process.only MM_GBSA` re-staged SMILES and re-triggered upstream steps. Instead:

1. Script uploaded: `s3://biomate-nextflow-work/inputs/andv_campaign/mmgbsa_inh01_batch.sh`
2. Batch job on **`biomate-nextflow-queue`** (v6 succeeded)

| Field | Value |
|-------|--------|
| **Job ID** | `0e36bdcf-c213-4df1-aad0-b26a7e183a60` |
| **Status** | **SUCCEEDED** |
| **Outputs** | `.../d64daac1/mmgbsa/binding_summary.json`, `mmgbsa_results.csv`, `mmgbsa_run.log` |

**Result:** `delta_g_bind_kcal_mol: null` — `gmx_MMPBSA` failed at runtime:

```
RuntimeError: cannot load MPI library (libmpi.so)
```

Root cause: ECR image `ambertools-gromacs-nf:latest` does not ship `gmx_MMPBSA` or OpenMPI; runtime `pip install` + `conda install gmx_mmpbsa` succeeded for the CLI but MPI linkage failed at execution.

**Follow-up:** Rebuild ECR with `conda install gmx_mmpbsa openmpi` baked in, or use dedicated `simonbray/gmx_mmpbsa` image on Batch.

Local copy script: `research/anti-virus/scripts/run_mmgbsa_standalone_batch.sh` (wrapper; production path uses S3 script v6).

---

## 3. HPC queue repair — root cause and fix

### Symptom

`biomate-nextflow-hpc-v1` status **INVALID**:

> none of the instances joined the underlying ECS Cluster

`biomate-hpc-queue` had **0 RUNNING** jobs; new work (MM-GBSA) stayed **RUNNABLE** indefinitely.

### Root cause

CE pinned to launch template **`nextflow-awscli-mime-20251127-223103` v12**:

```yaml
bootcmd:
  - systemctl stop ecs || true
```

User-data stops ECS at boot to pre-pull the agent image. If install/pull fails before `systemctl start ecs`, instances never register → CE **INVALID**.

Working CE `biomate-nextflow-ce-v2` uses **`lt-099eb24c4fe1b477e` v9** (no ECS stop at boot).

### Fix applied (2026-06-02)

| Setting | Before | After |
|---------|--------|-------|
| Launch template | `nextflow-awscli-mime` **v12** | `lt-099eb24c4fe1b477e` **v9** |
| AMI | top-level `imageId` + mismatched LT AMI | `imageIdOverride=ami-08fe495be97a3dbf4` |
| Subnets | 2 | 4 (match ce-v2) |
| Fallback `cpu-v2` | DISABLED | ENABLED (LT v16) |

**Verification:**

- CE status: **VALID**
- Smoke job `hpc-queue-smoke-test` (`9efaf6e6`) on `biomate-hpc-queue`: **SUCCEEDED**
- Log: `hpc-smoke-ok`, `aws-cli/2.34.58`, `/opt/aws-cli/bin/aws` OK

**Repeatable script:** `infra/scripts/fix_biomate_hpc_batch_ce.sh`

**Prevention:** Never pin Batch CEs to LT v12. Use v9/v16 or `lt-099eb24c4fe1b477e` v9. See also `docs/nextPhase/20260410_AWS_BATCH_CLIPATH_COMPLETE_FIX.md`.

---

## 4. Spot GPU queue fix (earlier in session)

`biomate-gpu-spot-v1`:

- Added `imageIdOverride=ami-0f02c2b015a9cf35c` (pre-baked AWS CLI GPU AMI)
- Launch template `$Latest` (v6 user-data)

---

## 5. Files changed (code / infra)

| Path | Change |
|------|--------|
| `backend/biomni_workflows/.../gromacs_protein_md/main.nf` | Remove `-bonded gpu`; CPU GPU fallback retained |
| `backend/biomni_workflows/.../gromacs_protein_md/nextflow.config` | Restored `biomate-hpc-queue` routing after HPC fix |
| `backend/docker/ambertools-gromacs-nf/Dockerfile` | AWS CLI install path → `/opt/aws-cli/bin/aws` (needs ECR rebuild) |
| `infra/scripts/fix_biomate_hpc_batch_ce.sh` | **New** — repair HPC + enable cpu-v2 fallback |
| `research/anti-virus/scripts/run_mmgbsa_standalone_batch.sh` | **New** — Batch MM-GBSA from S3 artifacts |
| S3 `inputs/andv_campaign/mmgbsa_inh01_batch.sh` | Standalone MM-GBSA driver (v6) |
| S3 `inputs/andv_campaign/mmgbsa_parse.py` | Result parser |

---

## 6. Key S3 paths (inh01 GROMACS)

```
s3://biomate-nextflow-work/nextflow/outputs/parallel-inhibitor-20260513T032000Z/d64daac1/
  md/trajectory.xtc          # 15 MB — production trajectory
  md/production.gro
  md/md.log
  analysis/rmsd_plot.png
  analysis/analysis_summary.json
  mmgbsa/binding_summary.json   # ΔG null — see §2
  mmgbsa/mmgbsa_run.log
```

Local pipeline dir: `research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/05_gromacs_mmgbsa_inh01/`  
(Session logs: `gromacs_inh01_ondemand_gpu.log`, `gromacs_inh01_spot_gpu.log`, `gromacs_inh01_mmgbsa_only.log`)

---

## 7. Open items

1. **ECR rebuild** — bake `gmx_mmpbsa` + OpenMPI + `/opt/aws-cli`; redeploy `ambertools-gromacs-nf:latest`
2. **Re-run MM-GBSA** on repaired `biomate-hpc-queue` via Nextflow or standalone script after image fix
3. **CUDA GROMACS** in ECR for real GPU MD (current conda build is OpenCL-only)
4. **Batch job TTL** — auto-cancel stale RUNNABLE jobs
5. **Salvage** `binding_summary.json` + per-residue CSV locally into `05_gromacs_mmgbsa_inh01/` after MM-GBSA succeeds
6. **Production MD** — optional 5M-step rerun on on-demand GPU once CUDA image available

---

## 8. Useful commands

```bash
# HPC queue health
aws batch describe-compute-environments --region us-west-2 \
  --compute-environments biomate-nextflow-hpc-v1 \
  --query 'computeEnvironments[0].{status:status,lt:computeResources.launchTemplate}'

# Re-apply HPC fix
bash infra/scripts/fix_biomate_hpc_batch_ce.sh

# Poll standalone MM-GBSA
aws batch describe-jobs --region us-west-2 --jobs 0e36bdcf-c213-4df1-aad0-b26a7e183a60

# Download MM-GBSA outputs
aws s3 sync s3://biomate-nextflow-work/nextflow/outputs/parallel-inhibitor-20260513T032000Z/d64daac1/mmgbsa/ \
  research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/05_gromacs_mmgbsa_inh01/
```
