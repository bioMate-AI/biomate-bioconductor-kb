# AWS Batch + Nextflow Executor Setup

**Date**: 2026-04-07
**Branch**: integration/next-phase
**Status**: Operational — all 6 drug-discovery workflows routing to AWS Batch

---

## Overview

BioMate runs all Nextflow workflows on AWS Batch by default. This document covers the
executor routing pipeline, the AMI/launch-template requirement, and the
`aws.batch.cliPath` pattern that makes Nextflow's S3 staging work inside task containers
that do not ship with the AWS CLI.

---

## 1 — AWS Batch Routing

### Root cause of the bug (2026-04-07)

`frontend/server/execution-env-policy.ts::buildNextflowComputeConfig()` was defaulting
`executor = "local"` for every request.  Because the backend's routing condition was:

```python
if _use_aws_env and not compute.get("executor"):
```

…the backend never upgraded to Batch; `compute["executor"] = "local"` is truthy so the
condition was never satisfied.

### Fix applied

**Frontend** (`frontend/server/execution-env-policy.ts`):

```typescript
if (!nextflowComputeConfig.executor) {
  // Default to awsbatch — BioMate platform standard
  // Override with NEXTFLOW_DEFAULT_EXECUTOR=local for local dev
  nextflowComputeConfig.executor = process.env.NEXTFLOW_DEFAULT_EXECUTOR || "awsbatch";
}
```

**Backend** (`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`):

```python
_executor_requested = compute.get("executor", "")
if _use_aws_env or _executor_requested == "awsbatch":
    # route to AWS Batch
```

The condition now fires when *either* `NEXTFLOW_USE_AWS=true` (backend env) **or** the
frontend sends `executor=awsbatch`.  Both are true in production; local dev uses
`NEXTFLOW_DEFAULT_EXECUTOR=local` to override.

### How to verify

Check `biomate_executor_override.config` for a running workflow:

```
/tmp/nextflow_runs/<run_id>/biomate_executor_override.config
```

It should show `executor = 'awsbatch'` and a `workDir = 's3://...'`.

---

## 2 — AWS CLI in Task Containers

### Problem

Nextflow 25.x injects shell functions `nxf_s3_upload` / `nxf_s3_download` into every
`.command.run` script.  These functions call `aws s3 cp`.  BioMate task containers
(`biomni-pharma:x86`, `biomni-tools:x86`, etc.) do **not** include the AWS CLI, so
every task failed immediately with:

```
bash: line 1: aws: command not found
```

### Solution: `aws.batch.cliPath`

Nextflow has a first-class config option for this:

```groovy
aws {
  batch {
    cliPath = '/opt/aws-cli/bin/aws'
  }
}
```

When `cliPath` is set, Nextflow automatically creates a bind-mount in every container job
definition that makes the host path visible inside the container at the same path.  No
`volumes` entry is required (and adding one for the same path causes a duplicate-mount
error: *"containerPath values aren't unique across mountPoints"*).

This config is written to `biomate_executor_override.config` by
`_generate_executor_config()` in `nextflow_executor.py`.

### Important: do NOT also set `aws.batch.volumes` for the same path

```groovy
# WRONG — causes duplicate mount error
aws.batch.volumes = '/opt/aws-cli:/opt/aws-cli'
aws.batch.cliPath = '/opt/aws-cli/bin/aws'

# CORRECT — cliPath alone handles the mount
aws.batch.cliPath = '/opt/aws-cli/bin/aws'
```

---

## 3 — EC2 Launch Template (AMI prerequisite)

The host EC2 instance must have the AWS CLI at `/opt/aws-cli/bin/aws`.

**Launch template**: `nextflow-awscli-mime-20251127-223103`

This template uses a MIME multi-part user-data script to install AWS CLI v2 to
`/opt/aws-cli` at instance boot time.  It was attached to the
`biomate-nextflow-cpu-v1` compute environment:

```bash
aws batch update-compute-environment \
  --compute-environment biomate-nextflow-cpu-v1 \
  --compute-resources \
    "launchTemplate={launchTemplateName=nextflow-awscli-mime-20251127-223103,version=\$Latest}"
```

**Important**: existing running EC2 instances in the compute environment were provisioned
*before* the launch template was attached and therefore do **not** have the CLI.  Only
instances launched *after* the update will have it.  To force new instances:

```bash
# Drain and scale-in so Batch provisions fresh nodes with the new LT
aws batch update-compute-environment \
  --compute-environment biomate-nextflow-cpu-v1 \
  --compute-resources desiredvCpus=0

# Then let Batch auto-scale up on the next job submission
```

---

## 4 — Executor Config Structure

Every Nextflow run gets a file `biomate_executor_override.config` in its local run dir.
This file is passed with `-c` to the Nextflow command.  Example:

```groovy
params {
    container = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest'
    outdir    = 's3://biomate-nextflow-work/nextflow/outputs/<user_id>/<run_id_short>'
}

process {
    executor  = 'awsbatch'
    queue     = 'biomate-nextflow-queue'
    container = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest'
    environment = [
        BIOMATE_USER_ID: '<user_id>',
        BIOMATE_RUN_ID:  '<run_id>',
    ]
}

aws {
    region = 'us-west-2'
    client {
        maxConnections    = 20
        uploadChunkSize   = 104857600   // 100 MB chunks
    }
    batch {
        cliPath = '/opt/aws-cli/bin/aws'
    }
}

docker.enabled = true
workDir = 's3://biomate-nextflow-work/nextflow/work/<user_id>/<run_id>'
```

Key points:
- `outdir` is always auto-set to S3 when executor is `awsbatch`.
- `workDir` is the Nextflow scratch space for intermediate files; also S3.
- Per-process `container` can be overridden inside individual workflow `.nf` files.

---

## 5 — Environment Variables

| Variable | Value | Purpose |
|---|---|---|
| `NEXTFLOW_USE_AWS` | `true` | Backend flag: route all runs to Batch |
| `AWS_BATCH_QUEUE` | `biomate-nextflow-queue` | Batch job queue |
| `AWS_S3_BUCKET` | `biomate-nextflow-work` | Work + outputs bucket |
| `AWS_DEFAULT_REGION` | `us-west-2` | AWS region |
| `AWS_ACCESS_KEY_ID` | set in `start_backend.sh` | Backend IAM credentials |
| `AWS_SECRET_ACCESS_KEY` | set in `start_backend.sh` | Backend IAM credentials |
| `NEXTFLOW_DEFAULT_EXECUTOR` | `local` (local dev only) | Frontend override to skip Batch |

For local dev without Batch, add to `frontend/.env`:
```
NEXTFLOW_DEFAULT_EXECUTOR=local
```

---

## 6 — Container ECR Availability

| Container | ECR Tag | Local | Notes |
|---|---|---|---|
| `biomate/biomni-pharma` | `biomni-pharma:x86` | Not pulled locally | IVIVE, ADMET, assay ranking, CRO |
| `biomate/biomni-tools` | *(empty in ECR)* | n/a | 474 workflows blocked until rebuilt |
| `biomate/biomni-drug-discovery-nf` | *(does not exist)* | n/a | AiZynthFinder, REINVENT4 |

**Action items**:
1. Build `biomni-tools:x86` from `backend/biomni_workflows/galaxy/docker/Dockerfile`
2. Build `biomni-drug-discovery-nf:x86` from `backend/docker/drug-discovery-nf/Dockerfile`
3. Push both to ECR under `399683337364.dkr.ecr.us-west-2.amazonaws.com/`

---

## 7 — Adding AWS Batch to a New Workflow

For any new `.nf` workflow that should run on Batch:

1. **Container directive** — every `process` block must declare a `container`.  Use ECR
   URIs, not Docker Hub names, for reliable Batch pull:
   ```groovy
   process MY_STEP {
       container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-pharma:x86'
       ...
   }
   ```

2. **S3 publishDir** — use `params.outdir` (auto-set to S3 by the executor config):
   ```groovy
   publishDir "${params.outdir}", mode: 'copy'
   ```

3. **No local-path inputs** — Batch containers cannot read files from the head node.
   All inputs must be S3 URIs or inline strings passed via `params`.

4. **Do not ship AWS CLI in the container** — rely on the host CLI mount via `cliPath`.
   Shipping it anyway is harmless but wastes image size.

5. **Mock mode** — add a `params.mock_mode = true` default and guard all network/compute
   calls with `if (params.mock_mode)` for local dev without Batch.  The backend
   auto-forces `mock_mode = false` for `awsbatch` runs.

---

## 8 — E2E Rate-Limit Bypass

The global rate limiter (`1000 req / 15 min per IP`) was blocking E2E execute calls
because the Chromium browser sends requests from localhost without the bypass header.

**Fix applied (2026-04-07)**:
- `frontend/server/security-config.ts`: added `skip: _isGlobalE2EBypass` to
  `globalRateLimiter`.
- `frontend/playwright.config.ts`: added `extraHTTPHeaders` with `X-E2E-Test-Token` so
  every browser request from Playwright carries the bypass token automatically.

For this to work, `E2E_TEST_TOKEN` must be set in the frontend process environment
(it is set in `frontend/.env` and the `tsx server/index.ts` launch command).
