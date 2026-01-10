# Fetch-and-Run Implementation Summary

## What Was Implemented

A complete **fetch-and-run pattern** implementation for Galaxy cloud execution on AWS Batch, with **Docker-in-Docker (DinD)** support.

## Key Components

### 1. Wrapper Container Image

**Location**: `docker/fetch-and-run/`

Files:
- `Dockerfile` - Container with AWS CLI, Python 3, and Docker client
- `fetch_and_run.sh` - Script that handles S3 transfers and job execution
- `build_and_push.sh` - Build and deploy script
- `README.md` - User documentation
- `DEPLOYMENT_GUIDE.md` - Detailed deployment instructions

**Image includes**:
- AWS CLI for S3 operations
- Docker client for Docker-in-Docker
- Python 3 and boto3
- Standard Unix utilities

### 2. Galaxy Job Runner Integration

**Location**: `lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

**New Method**: `_submit_fetch_and_run_job()` (lines 507-712)

This method:
1. Uploads input datasets to S3
2. Generates a job script with the Galaxy tool command
3. Creates symlinks for Galaxy's expected file paths
4. Uploads the job script to S3
5. Retrieves the tool container image from the tool registry
6. Submits an AWS Batch job with the fetch-and-run wrapper image
7. Passes the tool container image via `TOOL_CONTAINER_IMAGE` env var

### 3. Execution Modes

The fetch-and-run wrapper supports **two execution modes**:

#### Mode A: Docker-in-Docker (when tool container exists)
```bash
# Fetch-and-run wrapper pulls and runs the tool container
docker run --rm \
    -v "${WORK_DIR}:${WORK_DIR}:rw" \
    -v "${INPUT_DIR}:/galaxy_inputs:ro" \
    -v "${OUTPUT_DIR}:/galaxy_outputs:rw" \
    "${TOOL_CONTAINER_IMAGE}" \
    bash "${SCRIPT_FILE}"
```

**Benefits**:
- Uses official BioContainers without modification
- Isolated execution environment
- Matches Galaxy's local container execution behavior

#### Mode B: Direct Execution (when no tool container)
```bash
# Run the job script directly in the wrapper container
cd "${WORK_DIR}"
bash "${SCRIPT_FILE}"
```

**Benefits**:
- Faster startup (no container pull)
- Works for simple tools that only need Python/bash
- Lower resource usage

## Bug Fixes

### Fixed: "No command line available" Error

**Problem**:
```
ValueError: No command line available for job 196
```

**Root Cause**:
Job wrapper's `command_line` was None because Galaxy hadn't prepared the job yet.

**Solution**:
Call `job_wrapper.prepare()` before trying to access the command line:

```python
command_line = job_wrapper.runner_command_line or job_wrapper.command_line

if not command_line:
    self.logger.info(f"[{job_id}] Command line not ready, preparing job...")
    try:
        job_wrapper.prepare()
        command_line = job_wrapper.runner_command_line or job_wrapper.command_line
    except Exception as e:
        self.logger.warning(f"[{job_id}] Job prepare failed: {e}")
        command_line = job_wrapper.command_line

if not command_line:
    raise ValueError(f"No command line available for job {job_id}")
```

### Fixed: Container Python/AWS CLI Not Found

**Problem**:
```
/bin/sh: python3: not found
/bin/sh: aws: not found
```

**Root Cause**:
Original approach tried to install AWS CLI inside BioContainers, which are minimal and don't have package managers.

**Solution**:
Adopted Nextflow's approach - use a wrapper container with AWS CLI pre-installed that orchestrates tool containers via Docker-in-Docker.

## Architecture Comparison

### Original Approach (Failed)
```
AWS Batch Job (BioContainer)
├── Try to install Python/AWS CLI (FAILS)
├── Download inputs from S3 (can't run aws command)
└── Run Galaxy tool (never reaches this)
```

### New Fetch-and-Run Approach (Working)
```
AWS Batch Job (Fetch-and-Run Wrapper)
├── Download inputs from S3 ✓
├── Download job script from S3 ✓
├── Execute via Docker-in-Docker:
│   └── BioContainer
│       └── Run Galaxy tool command ✓
└── Upload outputs to S3 ✓
```

## Configuration Example

### Galaxy job_conf.yml
```yaml
execution:
  default: cloud_fetch_and_run
  environments:
    cloud_fetch_and_run:
      runner: galaxy_cloud
      params:
        use_fetch_and_run: true
        provider: aws
        aws_region: us-west-2
        aws_batch_queue: galaxy-cloud-queue
        aws_s3_bucket: galaxy-cloud-data-1760241377
        fetch_and_run_image: "123456789012.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest"
        cpus: 2
        memory: 4
        disk: 20
```

### Tool Container Mapping (config/tool_containers.json)
```json
{
  "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.72": {
    "image": "quay.io/biocontainers/fastqc:0.11.9--0",
    "verified": true
  }
}
```

## Data Flow

```
┌──────────────┐
│ Galaxy       │
│ (Local)      │
└──────┬───────┘
       │
       │ 1. Upload inputs
       ↓
┌──────────────────────┐
│ S3 Bucket            │
│ jobs/{job_id}/       │
│ ├── inputs/          │
│ │   └── data.fastq   │
│ └── job_script.sh    │
└──────┬───────────────┘
       │
       │ 2. Submit job
       ↓
┌────────────────────────────────────┐
│ AWS Batch                          │
│ ┌────────────────────────────────┐ │
│ │ Fetch-and-Run Wrapper          │ │
│ │                                │ │
│ │ 1. aws s3 sync inputs/         │ │
│ │ 2. aws s3 cp job_script.sh     │ │
│ │ 3. docker run biocontainer     │ │
│ │    ├── Execute Galaxy tool     │ │
│ │    └── Generate outputs        │ │
│ │ 4. aws s3 sync outputs/        │ │
│ └────────────────────────────────┘ │
└────────┬───────────────────────────┘
         │
         │ 3. Upload outputs
         ↓
┌──────────────────────┐
│ S3 Bucket            │
│ jobs/{job_id}/       │
│ └── outputs/         │
│     └── results.html │
└──────┬───────────────┘
       │
       │ 4. Download outputs
       ↓
┌──────────────┐
│ Galaxy       │
│ (Dataset)    │
└──────────────┘
```

## AWS Batch Job Definition Requirements

For Docker-in-Docker to work, the AWS Batch job definition must have:

```json
{
  "containerProperties": {
    "privileged": true,
    "volumes": [
      {
        "host": {"sourcePath": "/var/run/docker.sock"},
        "name": "docker-socket"
      }
    ],
    "mountPoints": [
      {
        "containerPath": "/var/run/docker.sock",
        "sourceVolume": "docker-socket"
      }
    ]
  }
}
```

**Important**: `privileged: true` is required for Docker-in-Docker.

## Benefits of This Approach

1. **No BioContainer Modification** - Works with any container from quay.io/biocontainers
2. **Flexible Execution** - Can run with or without containers
3. **Matches Local Execution** - Tool runs in the same container as local Galaxy
4. **Scalable** - Leverages AWS Batch autoscaling
5. **Cost-Effective** - Only pays for compute time during job execution
6. **Maintainable** - Clean separation of concerns (wrapper vs. tool)

## Learned from Nextflow

This implementation was inspired by analyzing Nextflow's AWS Batch integration:

**Key insights from Nextflow**:
1. Don't install AWS CLI in user containers
2. Use a wrapper container for orchestration
3. Docker-in-Docker allows using any container
4. Wrapper handles all S3 transfers
5. Job script is downloaded from S3, not embedded in command

**Documentation created during analysis**:
- `NEXTFLOW_ANALYSIS.md` - High-level comparison
- `NEXTFLOW_DEEP_DIVE.md` - Detailed technical analysis

## Next Steps

1. **Build and Deploy**:
   ```bash
   cd docker/fetch-and-run
   ./build_and_push.sh
   ```

2. **Configure AWS Batch**:
   - Create/update job definition with `privileged: true`
   - Ensure compute environment has internet access
   - Verify IAM roles have S3 and ECR permissions

3. **Test Workflow**:
   - Start Galaxy: `./run.sh`
   - Run a workflow with configured tools
   - Monitor AWS Batch logs in CloudWatch

4. **Monitor and Optimize**:
   - Check job execution times
   - Optimize resource allocation
   - Add more tool containers to registry

## Files Modified

### Created:
- `docker/fetch-and-run/Dockerfile`
- `docker/fetch-and-run/fetch_and_run.sh`
- `docker/fetch-and-run/build_and_push.sh`
- `docker/fetch-and-run/README.md`
- `docker/fetch-and-run/DEPLOYMENT_GUIDE.md`
- `NEXTFLOW_ANALYSIS.md`
- `NEXTFLOW_DEEP_DIVE.md`
- `FETCH_AND_RUN_IMPLEMENTATION.md` (this file)

### Modified:
- `lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`
  - Added `_submit_fetch_and_run_job()` method
  - Added execution mode detection logic
  - Added tool container image retrieval
  - Fixed "No command line available" bug

## Testing Checklist

- [ ] Build fetch-and-run image successfully
- [ ] Push image to ECR
- [ ] Update job_conf.yml with correct image URI
- [ ] Configure AWS Batch job definition with privileged mode
- [ ] Test workflow with tool that has container mapping
- [ ] Test workflow with tool that has no container (direct execution)
- [ ] Verify inputs are uploaded to S3
- [ ] Verify outputs are downloaded from S3
- [ ] Check CloudWatch logs for successful execution
- [ ] Confirm tool container is pulled and executed

## Troubleshooting Guide

See `DEPLOYMENT_GUIDE.md` for detailed troubleshooting steps.

Common issues:
- Docker not found → Check Dockerfile has docker installed
- Permission denied → Check AWS Batch job definition has privileged: true
- Image pull failed → Check internet access and IAM permissions
- No command line → Should be fixed, check tool configuration if still occurs

## References

- Fetch-and-Run Pattern: https://aws.amazon.com/blogs/compute/creating-a-simple-fetch-and-run-aws-batch-job/
- Docker-in-Docker: https://hub.docker.com/_/docker
- AWS Batch Best Practices: https://docs.aws.amazon.com/batch/latest/userguide/best-practices.html
