# AWS Batch + Nextflow Runbook
**Verified**: 2026-03-11
**Status**: Full 24-step CryoSPARC SPA pipeline — **SUCCESS in 13m 41s on real AWS Batch**
**Author**: Engineering (BioMate infra session 2026-03-10/11)

---

## Overview

BioMate runs Nextflow pipelines on AWS Batch for cloud-scale bioinformatics. Each workflow step runs as an isolated Batch job using a container from ECR. Progress is tracked async via Nextflow's trace file and surfaced to the user via polling — the chat session returns immediately; the user can do other things while the job runs.

---

## 1. AWS Infrastructure (Verified Config)

### 1.1 Compute Environment

| Field | Value |
|---|---|
| Name | `biomate-nextflow-cpu-v1` |
| Type | EC2 (MANAGED) |
| Allocation strategy | `BEST_FIT_PROGRESSIVE` |
| Instance types | `m5.large`, `m5.xlarge`, `m5.2xlarge` |
| Min / Max vCPUs | 0 / 128 |
| Subnets | `subnet-0254e4c3634b41bfc`, `subnet-03b277a7a08d388c1` |
| Security group | Default VPC SG |
| Launch template | None (no custom AMI needed) |
| Service role | `AWSServiceRoleForBatch` |
| Instance role | `arn:aws:iam::399683337364:instance-profile/ecsInstanceRole` |

> **Do NOT use** `galaxy-cloud-compute-final-v1` or `galaxy-cloud-queue`. The old queue has 18 stuck SAREK jobs that cause Batch to repeatedly zero out the ASG (`UpdateAutoScalingGroup(MaxSize=0, DesiredCapacity=0)` every 3s via CloudTrail). Always use the clean `biomate-nextflow-queue`.

### 1.2 Job Queue

| Field | Value |
|---|---|
| Name | `biomate-nextflow-queue` |
| Priority | 100 |
| Compute environment | `biomate-nextflow-cpu-v1` (order 1) |

### 1.3 S3 Work Bucket

| Field | Value |
|---|---|
| Bucket | `biomate-nextflow-work` |
| Region | `us-west-2` |
| Nextflow work prefix | `s3://biomate-nextflow-work/nextflow/work` |
| Production data | `s3://biomate-production-data-399683337364` (us-east-1) |

### 1.4 IAM — ecsInstanceRole

The EC2 instances launched by Batch assume `ecsInstanceRole`. It needs:

| Policy | Type | Purpose |
|---|---|---|
| `AmazonEC2ContainerServiceforEC2Role` | AWS managed | ECS agent registration |
| `AmazonSSMManagedInstanceCore` | AWS managed | SSM access |
| `GalaxyNextflowS3Access` | Customer managed (v3+) | S3 read/write on work bucket |
| `ECRPushAccess` | Inline | ECR pull for task containers |

**`GalaxyNextflowS3Access` v3** (current) covers:
- `s3:::biomate-nextflow-work` and `biomate-nextflow-work/*` — full CRUD
- `s3:::galaxy-cloud-data-1760241377` — full CRUD (legacy)
- `s3:::ngi-igenomes`, `s3:::broad-references` — read-only (reference genomes)

> If you add a new work bucket, add it to `GalaxyNextflowS3Access` before the first run.

---

## 2. Task Container Image

### 2.1 Why a Custom Image

Nextflow's `.command.run` wrapper (injected into every Batch task) uses:
- `bash` — to run the wrapper script itself
- `python3` — to execute the pipeline step's `.command.sh`
- `aws s3 cp` — for all S3 staging (`nxf_s3_upload` / `nxf_s3_download` functions)
- `ps` — for CPU/memory metrics collection

Public images that seem suitable each fail in a different way:

| Image | bash | python3 | aws | ps | Verdict |
|---|---|---|---|---|---|
| `python:3.11-slim` | ✓ | ✓ | ✗ | ✗ | **exit 127** (no aws) |
| `civitaspo/python-awscli:latest` | ✗ | ✓ | ✓ | ✗ | **exec not found** (no bash) |
| `ghcr.io/nf-core/base:2.1.0` | ✓ | ✓ | ✓ | ✓ | **403 denied** (auth required from Batch) |
| `amazon/aws-cli` | ✓ | ✗ | ✓ | ✗ | No python3 |

**Solution**: Custom ECR image — `python:3.11-slim` + AWS CLI v2 + `procps`.

### 2.2 Image Details

**ECR URI**: `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest`

**Dockerfile** (`aws_infrastructure/configs/Dockerfile.nextflow-base`):
```dockerfile
FROM python:3.11-slim

# Install AWS CLI v2 + procps (ps command for Nextflow metrics)
# Nextflow .command.run requires: bash (included), python3 (included), aws, ps
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates procps \
    && curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws \
    && rm -rf /var/lib/apt/lists/*
```

### 2.3 Rebuilding / Updating the Image

```bash
# 1. Login to ECR
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-west-2
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# 2. Build for amd64 (CRITICAL — this machine may be ARM64; Batch uses x86_64)
IMAGE="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/biomate-nextflow-base:latest"
docker buildx build \
  --platform linux/amd64 \
  -t "$IMAGE" \
  --push \
  aws_infrastructure/configs/  # directory containing Dockerfile.nextflow-base
```

> Always use `--platform linux/amd64`. The development machine is ARM64 (Apple M-series or AWS Graviton). Batch uses x86_64.

---

## 3. Nextflow Backend Configuration

### 3.1 Generated Batch Config (`_generate_executor_config`)

File: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

When a user runs a workflow with `executor=awsbatch`, the backend auto-generates:

```nextflow
process {
    executor = 'awsbatch'
    queue = 'biomate-nextflow-queue'
    container = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest'
}
aws {
    region = 'us-west-2'
    client {
        maxConnections = 20
        uploadChunkSize = 104857600  // 100 MB
    }
}
docker.enabled = true
workDir = 's3://biomate-nextflow-work/nextflow/work'
```

Environment variable overrides:
- `AWS_BATCH_QUEUE` — override queue name
- `AWS_DEFAULT_REGION` — override region
- `NEXTFLOW_S3_BUCKET` — override work bucket name
- `NEXTFLOW_BATCH_CONTAINER` — override task container image

### 3.2 Trace File (Progress Tracking)

The backend adds `-with-trace <log_dir>/workflow-trace.txt` to every Nextflow invocation. This TSV file is updated by Nextflow as each task changes state. The `/api/nextflow/status/{run_id}` endpoint reads it via `_parse_trace_progress()` and returns:

```json
{
  "completedTasks": 17,
  "failedTasks": 0,
  "runningTasks": 1,
  "totalTasks": 24,
  "progressPercent": 70,
  "is_batch": true,
  "processes": [...]
}
```

The frontend polls this endpoint every 3 seconds. On Batch, the idle timeout before giving up is 1800s (30 min) to accommodate cold-start provisioning time.

---

## 4. Cold-Start Timing

End-to-end first-task latency on a clean `biomate-nextflow-queue` (no warm instances):

| Phase | Duration |
|---|---|
| Nextflow submits job to Batch | ~5s |
| Batch routes job to CE, triggers ASG scale-out | ~30-60s |
| EC2 instance launches (m5.large from AMI) | ~2-3 min |
| ECS agent registers, pulls ECR image | ~30-60s (ECR in same region = fast) |
| Container starts, downloads task inputs from S3 | ~10-30s |
| **Total cold start** | **~4-5 min** |

Subsequent tasks on the **same instance** skip EC2+ECS provisioning and ECR pull — they start in 5-15s.

**The 24-step SPA pipeline completed in 13m 41s total** (1 cold start + 23 warm starts).

### Reducing Cold Start

| Option | Saves | Cost |
|---|---|---|
| ECR image (already done) | 60-120s vs DockerHub | Free |
| `minvCpus=2` on CE | Entire cold start | ~$70/mo (m5.large 24/7) |
| Pre-bake image into AMI | ECR pull step | ~$1/mo (AMI storage) |

For the beta, leave `minvCpus=0` (cost-efficient). Once steady-state users exist, set `minvCpus=2` so the first job of each day starts in seconds.

---

## 5. Async UX Architecture

The user submits a workflow from the chat UI. The flow is:

```
User sends message
       │
       ▼
Chat → AI assistant generates workflow_definition + nextflow_path
       │
       ▼
Frontend: POST /api/nextflow/execute   ← returns immediately (non-blocking)
       │                                  Nextflow process started in background
       ▼
Workflow card shows in UI with:
  "Running on AWS Batch — provisioning instances (first job ~5-8 min).
   You can close this panel and continue chatting."
       │
       ▼  (polls every 3s)
Frontend: GET /api/nextflow/status/{run_id}
  → reads workflow-trace.txt on disk
  → returns { completedTasks, progressPercent, is_batch, ... }
       │
       ▼
Progress bar updates in UI as tasks complete
       │
       ▼
QC monitor (background thread) reads trace, posts SSE events for gate failures
       │
       ▼
Workflow card shows "SUCCESS" / "FAILED" with QC summary
```

The user can send new messages, start other workflows, or close the workflow card at any time. The Batch job continues running regardless.

---

## 6. Debugging Guide

### Job fails with exit 127
AWS CLI not found in container. Check that `NEXTFLOW_BATCH_CONTAINER` is set to the ECR image, not `python:3.11-slim` or another public image without `aws`.

### Job fails: `CannotPullImageManifestError: denied`
The container image requires authentication (e.g. `ghcr.io`). Use ECR (same account, automatic IAM auth) or a public DockerHub image.

### Job fails: `exec: "bash": executable file not found`
Container has no `bash`. Alpine-based images often lack bash (use `sh`). Nextflow requires `bash`. Switch to a Debian/Ubuntu-based image.

### Job fails: `AccessDenied on s3:PutObject`
The `ecsInstanceRole` does not have write access to the work bucket. Add the bucket to `GalaxyNextflowS3Access` managed policy.

### Job stuck in RUNNABLE, `desiredvCpus: 0`
Two possible causes:
1. **Old queue / poisoned CE**: Check CloudTrail for `UpdateAutoScalingGroup(MaxSize=0)` events. If present, a different queue has stuck RUNNABLE jobs that flood the Batch scheduler. Use `biomate-nextflow-queue` only.
2. **Subnet misconfiguration**: Verify CE subnets are in the same VPC as the EC2 instances and have outbound internet access (NAT gateway) or VPC endpoints for ECR + S3.

### Task succeeds but `ps` warning in logs
The image lacks `procps`. Nextflow prints the warning but (by default) does NOT fail because of it — exit code still reflects the task script. If you see exit 1 alongside the `ps` warning, verify `procps` is installed in the image (`apt-get install procps`).

### Trace file is empty / no progress shown
The `-with-trace` flag must be passed to Nextflow. Verify `execute_nextflow()` in `nextflow_executor.py` includes `-with-trace <path>`. Also verify `_runs[run_id]["trace_path"]` is set correctly so the status endpoint reads the right file.

---

## 7. Useful AWS CLI Commands

```bash
# List all CE states
aws batch describe-compute-environments --region us-west-2 \
  --query 'computeEnvironments[*].{Name:computeEnvironmentName,State:state,desiredvCpus:computeResources.desiredvCpus}'

# Count jobs by status on biomate-nextflow-queue
for S in SUBMITTED PENDING RUNNABLE STARTING RUNNING SUCCEEDED FAILED; do
  C=$(aws batch list-jobs --job-queue biomate-nextflow-queue --job-status $S \
    --region us-west-2 --query 'length(jobSummaryList)' --output text 2>/dev/null)
  echo "$S: $C"
done

# Get CloudWatch logs for a Batch job
JOB_ID="<uuid>"
LOG_STREAM=$(aws batch describe-jobs --jobs "$JOB_ID" --region us-west-2 \
  --query 'jobs[0].container.logStreamName' --output text)
aws logs get-log-events \
  --log-group-name /aws/batch/job \
  --log-stream-name "$LOG_STREAM" \
  --region us-west-2 \
  --query 'events[*].message' --output text

# Manual test run (dev/debug)
nextflow run backend/biomni_workflows/pipeline_composition/pipelines/cryosparc_standard_spa/main.nf \
  -c /tmp/batch_test.config \
  -profile standard \
  --outdir s3://biomate-nextflow-work/test/manual_$(date +%s) \
  -with-trace /tmp/test_trace.txt
```

---

## 8. Recommended Next Steps

| Priority | Item | Effort |
|---|---|---|
| Medium | Set `minvCpus=2` on `biomate-nextflow-cpu-v1` for warm instance pool | 5 min |
| Medium | Smoke-test GPU CE for AlphaFold / DiffDock (needs `p3.2xlarge` or `g4dn.xlarge`) | 1 day |
| Low | Bake ECR image into custom AMI to shave ~30s off cold start | 2 hr |
| Low | Cancel the 18 stuck SAREK jobs in `galaxy-cloud-queue` | 10 min |
| Low | Add CloudWatch alarm: any FAILED Batch job → SNS → Slack | 1 hr |
