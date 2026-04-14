# BioMate Nextflow Container Architecture

**Date**: 2026-04-07
**Status**: Active — all x86 domain images rebuilt from `biomate-nextflow-base`

---

## Principle

Every BioMate container that runs as a Nextflow AWS Batch task **must inherit from
`biomate-nextflow-base:latest`**. The base image supplies:

- AWS CLI v2 (`/usr/local/bin/aws`) — required by Nextflow's `nxf_s3_upload` /
  `nxf_s3_download` shell functions that stage files to/from the S3 `workDir`
- Common Python stack (`numpy`, `scipy`, `pandas`, `biopython`, `rdkit`, `gget`)
- `procps` — for Nextflow CPU/memory metrics collection
- `bash`, `python3`, `curl`, `unzip`, `ca-certificates`

Without this base, every task fails immediately with:
```
bash: line 1: aws: command not found    # or: /opt/aws-cli/bin/aws: No such file
```

---

## Image Hierarchy

```
biomate-nextflow-base:latest          (aws_infrastructure/configs/Dockerfile.nextflow-base)
        │
        ├── biomate/biomni-tools:x86  (backend/docker/biomni-tools/Dockerfile)
        │       └── also tagged as:
        │           biomate/biomni-pharma:x86
        │           biomate/biomni-pharma:latest
        │           biomate/biomni-microbiology:latest
        │
        └── biomate/biomni-drug-discovery-nf:x86  (backend/docker/drug-discovery-nf/Dockerfile)
```

`biomate-nextflow-base:latest` is also used **directly** as the default container for
any Nextflow process that does not declare its own `container` directive.

---

## ECR Repositories

| ECR repo | Tag(s) | Source Dockerfile | Used by |
|---|---|---|---|
| `biomate-nextflow-base` | `latest` | `aws_infrastructure/configs/Dockerfile.nextflow-base` | Default container for all Batch tasks |
| `biomate/biomni-tools` | `x86`, `latest` | `backend/docker/biomni-tools/Dockerfile` | 400+ pharmacology / drug-discovery workflows |
| `biomate/biomni-pharma` | `x86`, `latest` | same as biomni-tools | Pharma-specific workflow aliases (ADMET, IVIVE, etc.) |
| `biomate/biomni-microbiology` | `latest` | same as biomni-tools | Microbiology workflows |
| `biomate/biomni-drug-discovery-nf` | `x86` | `backend/docker/drug-discovery-nf/Dockerfile` | AiZynthFinder, REINVENT4, pyDeseq2 |

---

## Base Image (`biomate-nextflow-base`)

**Source**: `aws_infrastructure/configs/Dockerfile.nextflow-base`

Key contents:
- `FROM python:3.11-slim`
- `apt-get`: curl, unzip, ca-certificates, procps
- AWS CLI v2 installed to `/usr/local/bin/aws`
- `pip`: cryosparc-tools, gget, numpy, scipy, pandas, biopython, rdkit

**Build & push**:
```bash
cd /home/yzhang/biomate/aws_infrastructure/configs
docker buildx build --platform linux/amd64 \
  -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest \
  -f Dockerfile.nextflow-base --push .
```

---

## Domain Image (`biomni-tools`)

**Source**: `backend/docker/biomni-tools/Dockerfile`

Key contents on top of base:
- System: `libgomp1`, `libgfortran5`, `libxrender1`, `libxext6`, `swig`
- ViennaRNA, AutoDock Vina, Meeko, OpenBabel
- codon-tools, adjustText, seaborn, plotly, pubchempy, scikit-learn, matplotlib

**Build & push all tags**:
```bash
cd /home/yzhang/biomate
ECR=399683337364.dkr.ecr.us-west-2.amazonaws.com

aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin $ECR

# Build once, push multiple tags
docker buildx build --platform linux/amd64 \
  -f backend/docker/biomni-tools/Dockerfile \
  -t $ECR/biomate/biomni-tools:x86 \
  -t $ECR/biomate/biomni-tools:latest \
  -t $ECR/biomate/biomni-pharma:x86 \
  -t $ECR/biomate/biomni-pharma:latest \
  -t $ECR/biomate/biomni-microbiology:latest \
  --push .
```

---

## Executor Config (`aws.batch.cliPath` — REMOVED)

The `cliPath` setting in `_generate_executor_config()` was removed because the CLI is
now in every task container directly. There is no need for a host-level bind-mount.

```groovy
# BEFORE (unreliable — required pre-installed CLI on host AMI):
aws.batch.cliPath = '/opt/aws-cli/bin/aws'

# AFTER (CLI is in the container via biomate-nextflow-base inheritance):
# No cliPath needed.
```

---

## Adding a New Domain Image

1. Create `backend/docker/<domain>/Dockerfile`
2. Start with:
   ```dockerfile
   FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest
   # Add domain-specific tools here
   RUN pip install --no-cache-dir <domain-packages>
   ```
3. Build and push:
   ```bash
   docker buildx build --platform linux/amd64 \
     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/<domain>:x86 \
     --push -f backend/docker/<domain>/Dockerfile .
   ```
4. In workflow `.nf` files:
   ```groovy
   container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] \
     ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/<domain>:x86' \
     : 'biomate/<domain>:latest'
   ```

---

## Why Not `cliPath` + AMI?

The AMI `ami-051fc3d11efefcb16` (`nextflow-ecs-al2-base-20251127-222233`) was designed
to install the CLI via user-data, but EC2 instances provisioned by Batch do not have
internet access in the BioMate VPC (private subnets, no NAT gateway). The user-data
`curl` to `awscli.amazonaws.com` silently fails.

Baking the CLI into every container image via `FROM biomate-nextflow-base` is simpler,
more reliable, and requires zero EC2/AMI configuration.
