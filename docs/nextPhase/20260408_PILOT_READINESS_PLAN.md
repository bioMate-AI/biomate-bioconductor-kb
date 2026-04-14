# BioMate Pilot Readiness Plan — Drug Discovery + CryoEM

**Date**: 2026-04-08
**Goal**: Full E2E execution of both pilot studies through the UI with timing, detailed logging, and complete Lago billing

---

## Phase 1 — Infrastructure: AMI Rebuild (blocks everything else)

**Problem**: All third-party containers fail on AWS Batch because EC2 instances have no AWS CLI. The launch template tries to download it from the internet, but BioMate VPC subnets have no NAT gateway.

**Solution**: Bake AWS CLI into the AMI directly from S3 (no internet needed).

**Steps**:
```bash
# 1. Upload CLI installer to S3 (already present)
#    s3://biomate-nextflow-work/tools/aws-cli-x86_64

# 2. Launch EC2 from current AMI in same VPC/subnet
aws ec2 run-instances \
  --image-id ami-051fc3d11efefcb16 \
  --instance-type t3.medium \
  --subnet-id subnet-0254e4c3634b41bfc \
  --iam-instance-profile Name=ecsInstanceRole \
  --security-group-ids sg-0de9af2d4437a8c90 \
  --user-data '#!/bin/bash
    aws s3 cp s3://biomate-nextflow-work/tools/aws-cli-x86_64 /tmp/awscliv2.zip
    cd /tmp && unzip -q awscliv2.zip && ./aws/install
    /usr/local/bin/aws --version > /tmp/aws-install-done.txt' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=biomate-ami-builder}]'

# 3. Wait for user-data to complete, then create AMI
aws ec2 create-image \
  --instance-id <instance-id> \
  --name "biomate-nextflow-awscli-$(date +%Y%m%d)" \
  --no-reboot

# 4. Update Batch compute environment
aws batch update-compute-environment \
  --compute-environment biomate-nextflow-cpu-v1 \
  --compute-resources imageId=<new-ami-id>

# 5. Drain old instances so Batch provisions fresh ones
aws batch update-compute-environment \
  --compute-environment biomate-nextflow-cpu-v1 \
  --compute-resources desiredvCpus=0
```

**Result**: All containers (third-party + BioMate) get `/usr/local/bin/aws` via host bind-mount with `cliPath`.

**After AMI is live**: Re-add `cliPath = '/usr/local/bin/aws'` to `nextflow_executor.py` so Nextflow mounts it into every container.

---

## Phase 2 — Container Gaps

### 2A. Containers already built and pushed (ECR, FROM biomate-nextflow-base)
| Image | Status | Covers |
|---|---|---|
| `biomate-nextflow-base:latest` | ✓ | Default for all Batch tasks |
| `biomni-tools:x86` | ✓ + statsmodels/scikit-image/DeepPurpose | Drug discovery S1,S2,S5,S6 + all pharmacology |
| `biomni-structure-to-drug:x86` | ✓ + fpocket | Drug discovery S3,S4 |
| `biomni-drug-discovery-nf:x86` | ✓ | REINVENT4, AiZynthFinder, drug MoA RNA-seq |
| `genomics-germline:x86` | ✓ | WGS germline pipeline |
| `sra-tools:3.1.1` | ✓ | SRA download step |

### 2B. Container needed: `biomate/biomni-cryoem:x86` (NEW)
**Blocks**: All cryo-EM pilot workflows

**Current container in cryo-EM workflows**: `biomate/cryo-em-tools:1.0` — ECR repo exists? unknown. Needs audit.

**Tools needed** (from cryo_em/ and cryo_et/ workflows):
- CryoSPARC Python SDK (`cryosparc-tools`) — already in `biomate-nextflow-base`!
- `globalphasing/grade:2.0` — phasing tool (third-party, needs AMI CLI fix)
- `phenix/phenix:dev` — structure refinement (third-party, needs AMI CLI fix)
- `quay.io/biocontainers/python:3.11` — replace with `biomate-nextflow-base:latest`

**Note**: CryoSPARC workflows use the Python SDK (not the CryoSPARC server CLI). The SDK is already in `biomate-nextflow-base`. Most cryo-EM subworkflows likely only need `biomate-nextflow-base` or `biomni-tools`.

**Action**: Audit each cryo_em and cryo_et .nf file for exact tool requirements, then build `biomni-cryoem:x86` if custom tools are needed beyond the base.

### 2C. Third-party containers unblocked by AMI rebuild (Phase 1)
| Image | Used by | Action |
|---|---|---|
| `gromacs/gromacs:2025.1` | MD simulation | AMI fix sufficient |
| `ambermd/ambertools:23` | MD prep, NCA | AMI fix sufficient |
| `simonbray/gmx_mmpbsa:1.6.3` | MM-GBSA | AMI fix sufficient |
| `rocker/r-ver:4.3.1` | NCA/PKNCA | AMI fix sufficient |
| `rocker/tidyverse:4.3.1` | NCA/PKNCA | AMI fix sufficient |
| `nlmixr2/nlmixr2:latest` | Population PK | AMI fix sufficient |
| `steineggerlab/foldseek:latest` | AlphaFold DB search | AMI fix sufficient |
| `soedinglab/mmseqs2:latest` | AlphaFold DB search | AMI fix sufficient |
| `catgumag/alphafold3:latest` | Structure prediction | AMI fix sufficient |
| `simonelenz/diffdock:latest` | DiffDock docking | AMI fix sufficient |
| `cford38/autodockvina:latest` | AutoDock Vina | AMI fix sufficient |
| `globalphasing/grade:2.0` | CryoEM structure | AMI fix sufficient |
| `phenix/phenix:dev` | CryoEM refinement | AMI fix sufficient |

### 2D. Containers to fix in .nf files
| Current image | Replacement | File |
|---|---|---|
| `quay.io/biocontainers/python:3.11` | `biomate-nextflow-base:latest` | cryo_em workflows |
| `biomate/biomni-pharma:latest` (static, non-conditional) | `biomni-tools:x86` conditional | `apply_vcog_grade/main.nf` |

### 2E. License-gated (no action needed until partner provides key)
- `amber24-cuda:latest` — AMBER GPU MD
- `schrodinger2024:latest` — Glide docking
- `moe2024:latest` — MOE covalent docking

---

## Phase 3 — Workflow Fixes

### 3A. Drug discovery pilot (S1–S6) — READY after Phase 1+2A
All 6 sessions use only `biomni-tools:x86` and `biomni-structure-to-drug:x86`. No blocking gaps.

### 3B. Additional drug discovery workflows (extended study)
- GROMACS MD: unblocked after AMI rebuild
- AMBER MD: unblocked after AMI rebuild (CPU path; GPU needs license)
- NCA/PKNCA: unblocked after AMI rebuild
- Population PK: unblocked after AMI rebuild
- AlphaFold DB search: `quay.io/biocontainers/python:3.11` → `biomate-nextflow-base:latest` + AMI fix
- REINVENT4: verify `biomni-drug-discovery-nf:x86` has working REINVENT4 binary

### 3C. CryoEM pilot workflows
- Audit `cryo_em/` and `cryo_et/` for exact container per process
- Most use `biomate/cryo-em-tools:1.0` (check if ECR repo exists + has content)
- `quay.io/biocontainers/python:3.11` → `biomate-nextflow-base:latest`
- Build `biomni-cryoem:x86` if `cryo-em-tools:1.0` is missing or outdated
- `phenix` and `grade` containers: unblocked after AMI rebuild

---

## Phase 4 — E2E Pilot Tests (full UI, timing, Lago billing)

### Drug Discovery Pilot (6 sessions)
Based on `BioMate_DrugDiscovery_Pilot_Study_Proposal.md`:

| Session | Workflow | Container | Expected runtime |
|---|---|---|---|
| S1 | ADMET profiling (15 BCR-ABL1 compounds) | `biomni-tools:x86` | ≤15 min |
| S2 | IVIVE hepatic clearance | `biomni-tools:x86` | ≤15 min |
| S3 | Pocket detection (BCR-ABL1 1IEP) | `biomni-structure-to-drug:x86` | ≤15 min |
| S4 | Pharmacophore filtering (ABL1 selectivity) | `biomni-structure-to-drug:x86` | ≤30 min |
| S5 | Assay data upload + compound ranking | `biomni-tools:x86` | ≤15 min |
| S6 | CRO export (WuXi AppTec format) | `biomni-tools:x86` | ≤10 min |

**Billing targets** (from proposal):
- LLM cost per session: ~$0.05–0.15
- Compute cost per session: ~$0.20–0.50
- Total pilot: <$6.00

### CryoEM Pilot (pending Phase 2B + 3C completion)
Based on `BioMate_CryoEM_Pilot_Study_Proposal.md`:

| Session | Workflow | Container | Expected runtime |
|---|---|---|---|
| P0-A | Cryo-EM processing (EMPIAR-10061) | `biomni-cryoem:x86` or CryoSPARC | 8–10 hrs |
| P0-B | mRNA antigen design (mRNA-1273) | `biomni-tools:x86` | ≤5 min |
| P0-C | Mpro docking (PDB 7RFS) | `biomni-structure-to-drug:x86` | ≤15 min |
| P0-D | GLP-1R pharmacophore (PDB 7KI0) | `biomni-structure-to-drug:x86` | ≤30 min |
| P0-E | Semaglutide PK/PD simulation | `rocker/r-ver:4.3.1` or `biomni-tools:x86` | ≤5 min |

### Test requirements per session
- Full multi-turn conversation through the UI (not direct Nextflow)
- Timing: t_send → t_workflow_card → t_confirm_run → t_terminal_status
- Screenshots at each turn
- Lago billing delta: LLM tokens (in/out), LLM cost, compute cost
- Output files verified (file count, types, key outputs)
- Pass criteria from pilot proposals (RMSD, AUC-ROC, CAI, etc.)

---

## Execution Order

```
[TODAY]
  ├── Phase 1: AMI rebuild (30–45 min)
  │     └── Then: re-add cliPath to nextflow_executor.py
  ├── Phase 2B: Audit cryo_em/ .nf containers (parallel)
  │     └── Build biomni-cryoem:x86 if needed
  └── Phase 2D: Fix quay.io/biocontainers/python:3.11 in .nf files

[AFTER AMI IS LIVE]
  ├── Phase 4: Drug discovery E2E (S1–S6) — all containers ready
  └── Phase 3B/3C: Fix remaining workflow issues

[AFTER CRYO-EM CONTAINER READY]
  └── Phase 4: CryoEM E2E (P0-B through P0-E first; P0-A last — needs GPU + data)
```

---

## Open Questions

1. **CryoEM GPU instances**: CryoSPARC and RELION need GPU (g6.2xlarge or p3). Is there a GPU Batch compute environment? Current CE is CPU only.
2. **EMPIAR data for P0-A**: 38,088 micrographs from EMPIAR-10061 need to be staged to S3 first.
3. **REINVENT4 in `biomni-drug-discovery-nf`**: Binary installed? Needs smoke test.
4. **Lago compute billing**: Does Lago capture Nextflow Batch job cost (seconds × instance price), or only LLM tokens? If not, needs wiring.
